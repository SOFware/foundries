# frozen_string_literal: true

module Foundries
  # Blueprint is the base class for individual factory wrappers within a Foundry.
  #
  # Each Blueprint wraps one or more factory_bot factories and knows how to:
  # - Create records using factory_bot
  # - Track created records in a collection
  # - Navigate parent-child relationships
  # - Find existing records before creating duplicates
  #
  # Subclass Blueprint and use the class-level DSL to declare behavior:
  #
  #   class UserBlueprint < Foundries::Blueprint
  #     handles :user, :admin
  #     factory :user
  #     collection :users
  #     parent :none
  #     permitted_attrs %i[name email]
  #   end
  #
  class Blueprint
    include FactoryBot::Syntax::Methods

    attr_reader :foundry

    class << self
      def handles(*methods)
        @handled_methods ||= []
        @handled_methods.concat(methods)
      end

      def handled_methods
        @handled_methods || []
      end

      # Declare which factory_bot factory this blueprint uses.
      # If not set, inferred from the class name.
      def factory(name = nil)
        if name
          @factory_name = name
        else
          @factory_name || inferred_factory_name
        end
      end

      def factory_name
        factory
      end

      # Declare the collection name for tracking created records.
      # This also defines `#collection` and `#record_class` instance methods.
      def collection(method_name = nil)
        return @collection_name unless method_name

        @collection_name = method_name

        define_method(:collection) do
          foundry.send(:"#{method_name}_collection")
        end

        define_method(:record_class) do
          method_name.to_s.classify.constantize
        end
      end

      attr_reader :collection_name

      # Declare the foreign key used to link to the parent.
      def parent_key(key = nil)
        return @parent_key_name unless key

        @parent_key_name = key
        define_method(:parent_key) { key }
      end

      # Declare how to find the parent record from `current` state.
      #
      #   parent :none        - no parent relationship
      #   parent :self        - self-referential (e.g. nested categories)
      #   parent :competency  - reads current.competency
      #
      def parent(method_name = nil)
        return @parent_method unless method_name

        @parent_method = method_name

        if method_name == :none
          define_method(:same_parent?) { |_| true }
        elsif method_name == :self
          define_method(:same_parent?) { |_| true }
          define_method(:parent) do
            current.send(current_accessor)
          end
        else
          define_method(:parent) do
            current.send(method_name)
          end

          define_singleton_method(:parent_accessor) do
            method_name
          end
        end
      end

      # Declare ancestor traversal order for ascending_find.
      #
      #   lookup_order %i[evented_mod phase cohort]
      #
      # When no parent is present, ascending_find walks these
      # ancestor types on `current`, checking collection_name
      # on each.
      def lookup_order(ancestors = nil)
        return @lookup_order || [] unless ancestors

        @lookup_order = ancestors
      end

      # Declare which attributes are allowed through to factory_bot.
      def permitted_attrs(attr_list)
        define_method(:permitted_attrs) do |attrs|
          keys = attr_list.dup
          keys << parent_key if parent_key
          attrs.slice(*keys)
        end
      end

      # Declare nested attributes (for accepts_nested_attributes_for).
      def nested_attrs(hash)
        nested_object_name, attr_names = hash.shift

        define_method(:nested_attrs) do |attrs|
          attrs_to_nest = attrs.slice(*attr_names)
          key = :"#{nested_object_name}_attributes"
          {key => attrs_to_nest}
        end
      end

      # Load state from an existing object back into a foundry.
      def load_state_from(object, foundry)
        return unless respond_to?(:parent_accessor)

        parent_object = object.send(parent_accessor)
        foundry.load_existing_objects(parent_object)
      end

      private

      def inferred_factory_name
        name&.demodulize&.delete_suffix("Blueprint")&.underscore&.to_sym
      end
    end

    def self.new(...)
      instance = super
      foundry = instance.foundry
      recorder = foundry&.instance_variable_get(:@_similarity_recorder)
      instance._wrap_for_similarity_recording!(recorder) if recorder
      instance
    end

    def initialize(foundry)
      @foundry = foundry
      @attrs = {}
    end

    def _wrap_for_similarity_recording!(recorder)
      methods_to_wrap = self.class.public_instance_methods(false).select do |m|
        self.class.instance_method(m).parameters.any? { |type, _| type == :block }
      end

      methods_to_wrap.each do |method_name|
        original = method(method_name)
        define_singleton_method(method_name) do |*args, **kwargs, &block|
          recorder.record(method_name.to_s, has_block: !block.nil?) do
            original.call(*args, **kwargs, &block)
          end
        end
      end
    end

    delegate :current=, :current, :update_current, :execute_and_restore_state,
      to: :foundry

    def assume_trait?(val)
      val.is_a?(Symbol) || val.is_a?(Array)
    end

    def inspect
      self.class.name
    end

    def parent_key
      nil
    end

    def parent
      nil
    end

    # Saves current state, yields, then restores state.
    # Use this when entering a nested block to scope context.
    def update_state_for_block(object, &block)
      execute_and_restore_state do
        update_current(object)
        current.resource = object
        instance_exec(&block)
      end
    end

    # Find or create: when no parent is present, walks ancestors
    # via lookup_order; otherwise finds from parent or creates.
    def find_or_create(name, attrs = {})
      return ascending_find(name) unless parent_present?

      find_from_parent(name) || create_object(name, attrs)
    end

    # Walk ancestor types declared in lookup_order, checking
    # collection_name on each ancestor found in current state.
    # Falls back to collection find.
    def ascending_find(name)
      object = nil
      self.class.lookup_order.each do |ancestor_type|
        ancestor = current.send(ancestor_type)
        next unless ancestor

        col = self.class.collection_name
        object = ancestor.send(col).find_by(name:)
        break if object
      end

      object || find(name)
    end

    # Whether a parent is available in the current context.
    def parent_present?
      parent_method = self.class.parent
      return true if parent_method.in?(%i[self none])

      parent
    end

    # Find from the parent's association, falling back to
    # collection find.
    def find_from_parent(name, col_name: "name")
      col = self.class.collection_name
      parent.send(col).find_by(col_name => name) ||
        find(name, col_name:)
    end

    # Find a record in the collection by name, falling back to the database.
    def find(name, col_name: "name")
      raise "#find called with nil :name, for col_name: #{col_name}." unless name

      found_record = collection.detect do |object|
        object.send(col_name).casecmp?(name) && same_parent?(object)
      end

      found_record ||
        record_class.find_by(col_name => name)&.tap { |rec| collection << rec }
    end

    # Find a record in the collection by arbitrary criteria, falling back to the database.
    def find_by(criteria = {})
      found_record = collection.detect do |object|
        criteria.all? { |attr, value| object.send(attr) == value }
      end

      return found_record if found_record

      record_class.find_by(criteria)&.tap { |record| collection << record }
    end

    def same_parent?(object)
      return true unless parent

      object.send(parent_key) == parent_id
    end

    def parent_id
      parent&.id
    end

    def current_accessor
      self.class.name.demodulize.underscore.delete_suffix("_blueprint")
    end

    def find_or_create_object
      send(:"#{mode}_object")
    end

    def mode
      current.resource.nil? ? :find : :create
    end

    def reset_attrs_and_type
      @type = nil
      reset_attrs
    end

    def reset_attrs
      @attrs = {}
    end

    # Delegate unknown methods to the foundry so that all blueprint methods
    # are available in nested blocks. Also supports dynamic find_<klass>_by.
    def method_missing(name, *args, **kwargs, &block)
      if (match = missing_find_by_request?(name))
        klass_name = match.named_captures["klass"]
        return collection_find_by(klass_name, args)
      end

      if foundry.respond_to?(name)
        return foundry.send(name, *args, **kwargs, &block)
      end

      super
    end

    def respond_to_missing?(name, include_private = false)
      missing_find_by_request?(name) || foundry.respond_to?(name) || super
    end

    private

    def missing_find_by_request?(method_name)
      method_name.match(/^find_(?<klass>.*)_by$/)
    end

    def collection_find_by(klass_name, args)
      attrs = args.first
      target_collection_name = "#{klass_name.pluralize}_collection"
      objects = foundry.send(target_collection_name)
      objects.detect do |object|
        attrs.all? { |(attr, value)| object.send(attr) == value }
      end
    end
  end
end
