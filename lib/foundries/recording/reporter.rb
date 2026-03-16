# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require_relative "aggregator"
require_relative "node"

module Foundries
  module Recording
    class Reporter
      MAX_STDOUT_CANDIDATES = 10

      def self.merge_files(paths, output_path:)
        combined_per_test = {}
        total_creates = 0

        paths.each do |path|
          data = JSON.parse(File.read(path))
          total_creates += data["total_factory_creates"]
          data["per_test"].each do |test_id, test_data|
            combined_per_test[test_id] = test_data
          end
        end

        total_tests = combined_per_test.size

        results = combined_per_test.transform_values do |test_data|
          children = (test_data["tree"] || []).map { |h| node_from_hash(h) }
          Node.new(factory: :__root__, children: children)
        end

        reporter = new(results: results, total_creates: total_creates, total_tests: total_tests)
        reporter.write_json(output_path)
        reporter.summary(json_path: output_path)
      end

      def self.node_from_hash(hash)
        children = (hash["children"] || []).map { |c| node_from_hash(c) }
        Node.new(
          factory: hash["factory"].to_sym,
          traits: (hash["traits"] || []).map(&:to_sym),
          children: children
        )
      end

      private_class_method :node_from_hash

      def initialize(results:, total_creates:, total_tests:)
        @results = results
        @total_creates = total_creates
        @total_tests = total_tests
      end

      def candidates
        @candidates ||= Aggregator.new(@results).candidates
      end

      def write_json(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(json_data))
      end

      def summary(json_path: nil)
        lines = []
        lines << "[Foundries] Recording complete. #{@total_tests} tests, #{@total_creates} factory creates."

        if candidates.empty?
          lines << "[Foundries] No preset candidates found."
        else
          lines << "[Foundries] Top preset candidates:"
          candidates.first(MAX_STDOUT_CANDIDATES).each_with_index do |candidate, index|
            lines << "  #{index + 1}. #{candidate[:structure]} (#{candidate[:frequency]} tests, score: #{candidate[:score]})"
          end
        end

        lines << "[Foundries] Full report: #{json_path}" if json_path

        lines.join("\n")
      end

      private

      def json_data
        {
          recorded_at: Time.now.utc.iso8601,
          total_tests: @total_tests,
          total_factory_creates: @total_creates,
          candidates: candidates.map { |c| stringify_candidate(c) },
          per_test: build_per_test
        }
      end

      def stringify_candidate(candidate)
        {
          structure: candidate[:structure],
          frequency: candidate[:frequency],
          tree_size: candidate[:tree_size],
          score: candidate[:score],
          tests: candidate[:tests]
        }
      end

      def build_per_test
        @results.each_with_object({}) do |(test_id, root), hash|
          hash[test_id.to_s] = {
            factories_created: root.children.size,
            tree: root.children.map(&:to_h)
          }
        end
      end
    end
  end
end
