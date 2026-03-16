# frozen_string_literal: true

require "set"
require_relative "node"

module Foundries
  module Recording
    class Aggregator
      def initialize(results)
        @results = results
      end

      def candidates
        return [] if @results.empty?

        normalized = normalize_results
        full_tree_candidates = group_by_full_tree(normalized)
        subtree_candidates = find_common_subtrees(normalized)
        merged = merge_candidates(full_tree_candidates, subtree_candidates)
        filtered = merged.reject { |c| c[:tree_size] <= 1 }
        filtered.sort_by { |c| -c[:score] }
      end

      private

      def normalize_results
        @results.transform_values(&:normalize)
      end

      def group_by_full_tree(normalized)
        groups = Hash.new { |h, k| h[k] = [] }

        normalized.each do |test_id, root|
          structure = root_structure(root)
          groups[structure] << test_id
        end

        groups.map do |structure, tests|
          sample_root = normalized[tests.first]
          tree_size = sample_root.children.sum(&:tree_size)
          {
            structure: structure,
            frequency: tests.size,
            tree_size: tree_size,
            score: tests.size * tree_size,
            tests: tests.map(&:to_s)
          }
        end
      end

      def root_structure(root)
        root.children.sort_by(&:signature).map(&:signature).join(", ")
      end

      def find_common_subtrees(normalized)
        subtree_tests = Hash.new { |h, k| h[k] = Set.new }
        subtree_nodes = {}

        normalized.each do |test_id, root|
          root.children.each do |child|
            extract_nontrivial_subtrees(child).each do |subtree|
              sig = subtree.signature
              subtree_tests[sig] << test_id
              subtree_nodes[sig] ||= subtree
            end
          end
        end

        subtree_tests.map do |sig, tests|
          subtree = subtree_nodes[sig]
          {
            structure: sig,
            frequency: tests.size,
            tree_size: subtree.tree_size,
            score: tests.size * subtree.tree_size,
            tests: tests.map(&:to_s)
          }
        end
      end

      def extract_nontrivial_subtrees(node)
        subtrees = []
        # A non-trivial subtree is a node that has children
        subtrees << node unless node.children.empty?
        node.children.each do |child|
          subtrees.concat(extract_nontrivial_subtrees(child))
        end
        subtrees
      end

      def merge_candidates(full_tree, subtree)
        by_structure = {}

        full_tree.each do |candidate|
          by_structure[candidate[:structure]] = candidate
        end

        subtree.each do |candidate|
          if by_structure.key?(candidate[:structure])
            existing = by_structure[candidate[:structure]]
            merged_tests = (existing[:tests] + candidate[:tests]).uniq
            frequency = merged_tests.size
            tree_size = candidate[:tree_size]
            by_structure[candidate[:structure]] = {
              structure: candidate[:structure],
              frequency: frequency,
              tree_size: tree_size,
              score: frequency * tree_size,
              tests: merged_tests
            }
          else
            by_structure[candidate[:structure]] = candidate
          end
        end

        by_structure.values
      end
    end
  end
end
