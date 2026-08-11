# frozen_string_literal: true

module Foundries
  module Similarity
    class StructureTree
      attr_reader :name, :children

      def initialize(name, children: [])
        @name = name.to_s
        @children = children
      end

      def self.root(children:)
        new("__root__", children: children)
      end

      def normalize
        normalized_children = children.map(&:normalize)
        collapsed = normalized_children.flat_map { |child| child.collapse_into(name) }
        deduped = collapsed
          .group_by(&:name)
          .map { |_name, group| group.max_by(&:descendant_count) }
          .sort_by(&:name)
        self.class.new(name, children: deduped)
      end

      def collapse_into(parent_name)
        if name == parent_name && !children.empty?
          children
        else
          [self]
        end
      end

      def descendant_count
        children.sum { |c| 1 + c.descendant_count }
      end

      def ==(other)
        other.is_a?(self.class) &&
          name == other.name &&
          children == other.children
      end

      alias_method :eql?, :==

      def hash
        [name, children].hash
      end

      def contains?(other)
        return true if self == other

        embeds?(other) || children.any? { |child| child.contains?(other) }
      end

      def embeds?(other)
        return false unless name == other.name

        other.children.all? do |other_child|
          children.any? { |child| child.embeds?(other_child) }
        end
      end

      def to_s
        if children.empty?
          name
        else
          "#{name} > [#{children.join(", ")}]"
        end
      end
    end
  end
end
