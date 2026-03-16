# frozen_string_literal: true

module Foundries
  module Recording
    class Node
      attr_reader :factory, :traits, :children

      def initialize(factory:, traits: [], children: [])
        @factory = factory.to_sym
        @traits = traits.map(&:to_sym).sort.freeze
        @children = children.freeze
        @self_signature = compute_self_signature
        @signature = compute_signature
        @tree_size = 1 + children.sum(&:tree_size)
        freeze
      end

      attr_reader :signature, :self_signature, :tree_size

      def normalize
        normalized_children = children.map(&:normalize)
        deduped = normalized_children
          .group_by(&:self_signature)
          .map { |_sig, group| group.max_by(&:tree_size) }
          .sort_by(&:signature)
        self.class.new(factory: factory, traits: traits, children: deduped)
      end

      def to_h
        {
          factory: factory.to_s,
          traits: traits.map(&:to_s),
          children: children.map(&:to_h)
        }
      end

      def ==(other)
        other.is_a?(self.class) && signature == other.signature
      end

      alias_method :eql?, :==

      def hash
        signature.hash
      end

      def to_s
        signature
      end

      private

      def compute_self_signature
        base = factory.to_s
        base = "#{base}[#{traits.map { |t| ":#{t}" }.join(", ")}]" unless traits.empty?
        base
      end

      def compute_signature
        base = @self_signature
        unless children.empty?
          sorted_children = children.sort_by(&:signature)
          base = "#{base} > [#{sorted_children.map(&:signature).join(", ")}]"
        end
        base
      end
    end
  end
end
