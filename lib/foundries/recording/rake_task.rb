# frozen_string_literal: true

require "rake"
require_relative "../recording"

module Foundries
  module Recording
    class RakeTask
      include Rake::DSL

      def self.install(output_path: Recording::DEFAULT_OUTPUT_PATH)
        new.install_tasks(output_path: output_path)
      end

      def install_tasks(output_path:)
        namespace :foundries do
          namespace :recording do
            desc "Merge per-worker recording files into a single report"
            task :merge do
              dir = File.dirname(output_path)
              base = File.basename(output_path, File.extname(output_path))
              ext = File.extname(output_path)
              pattern = File.join(dir, "#{base}-*#{ext}")
              files = Dir.glob(pattern).sort

              if files.empty?
                $stdout.puts "[Foundries] No worker recording files found matching #{pattern}"
                next
              end

              Foundries::Recording::RakeTask.merge(files, output_path: output_path)
            end
          end
        end
      end

      def self.merge(files, output_path:)
        summary = Reporter.merge_files(files, output_path: output_path)
        $stdout.puts summary
      end
    end
  end
end
