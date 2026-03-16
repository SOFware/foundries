# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require_relative "aggregator"

module Foundries
  module Recording
    class Reporter
      MAX_STDOUT_CANDIDATES = 10

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
