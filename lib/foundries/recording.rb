# frozen_string_literal: true

require_relative "recording/collector"
require_relative "recording/reporter"

module Foundries
  module Recording
    DEFAULT_OUTPUT_PATH = "tmp/foundries/recording.json"

    class << self
      attr_writer :enabled, :output_path

      def enabled?
        return @enabled unless @enabled.nil?
        ENV["FOUNDRIES_RECORD"] == "1"
      end

      def collector
        @collector ||= Collector.new
      end

      def output_path
        @output_path || DEFAULT_OUTPUT_PATH
      end

      def worker_output_path
        worker_id = ENV["TEST_ENV_NUMBER"]
        return output_path if worker_id.nil?

        suffix = worker_id.empty? ? Process.pid.to_s : worker_id
        base = output_path
        ext = File.extname(base)
        "#{base.chomp(ext)}-#{suffix}#{ext}"
      end

      def reset!
        @collector = nil
        @enabled = nil
        @output_path = nil
      end

      def report!
        total_tests = collector.results.size
        reporter = Reporter.new(
          results: collector.results,
          total_creates: collector.total_creates,
          total_tests: total_tests
        )
        path = worker_output_path
        reporter.write_json(path)
        $stdout.puts reporter.summary(json_path: path)
      end
    end
  end
end

if Foundries::Recording.enabled? && defined?(RSpec)
  RSpec.configure do |config|
    config.before(:each) do |example|
      Foundries::Recording.collector.start_test(example.full_description)
    end

    config.after(:each) do |example|
      Foundries::Recording.collector.stop_test(example.full_description)
    end

    config.after(:suite) do
      Foundries::Recording.report!
    end
  end
end
