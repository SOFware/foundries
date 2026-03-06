# frozen_string_literal: true

module Foundries
  module Similarity
    module Comparator
      def self.compare(new_key, new_tree, registry)
        warnings = []

        registry.each do |existing_key, existing_tree|
          next if existing_key == new_key
          pair_key = [new_key, existing_key].sort

          if new_tree == existing_tree
            warnings << {
              pair: pair_key,
              message: "[Foundries] Preset :#{preset_name(new_key)} and " \
                ":#{preset_name(existing_key)} have identical structure " \
                "(#{display_tree(new_tree)})"
            }
          end
        end

        warnings
      end

      def self.preset_name(key)
        key.to_s.split(".").last
      end

      def self.display_tree(tree)
        tree.children.map(&:to_s).join(", ")
      end

      private_class_method :preset_name, :display_tree
    end
  end
end
