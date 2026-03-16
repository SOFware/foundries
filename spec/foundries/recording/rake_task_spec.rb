# frozen_string_literal: true

require "spec_helper"
require "rake"
require "foundries/recording/rake_task"
require "json"
require "tmpdir"

RSpec.describe Foundries::Recording::RakeTask do
  describe ".install" do
    before(:each) do
      Rake::Task.clear
      described_class.install
    end

    it "defines the foundries:recording:merge task" do
      expect(Rake::Task.task_defined?("foundries:recording:merge")).to be true
    end

    it "prints a message when no worker files are found" do
      Dir.mktmpdir do |dir|
        Rake::Task.clear
        output_path = File.join(dir, "recording.json")
        described_class.install(output_path: output_path)

        expect { Rake::Task["foundries:recording:merge"].invoke }.to output(
          /No worker recording files found/
        ).to_stdout
      end
    end
  end

  describe ".merge" do
    def write_worker_json(dir, filename, total_creates:, per_test:)
      data = {
        recorded_at: Time.now.utc.iso8601,
        total_tests: per_test.size,
        total_factory_creates: total_creates,
        candidates: [],
        per_test: per_test
      }
      path = File.join(dir, filename)
      File.write(path, JSON.pretty_generate(data))
      path
    end

    it "merges files and prints summary to stdout" do
      Dir.mktmpdir do |dir|
        path1 = write_worker_json(dir, "recording-1.json",
          total_creates: 10,
          per_test: {
            "test A" => {
              factories_created: 1,
              tree: [{factory: "team", traits: [], children: []}]
            }
          })

        path2 = write_worker_json(dir, "recording-2.json",
          total_creates: 20,
          per_test: {
            "test B" => {
              factories_created: 1,
              tree: [{factory: "team", traits: [], children: []}]
            }
          })

        output_path = File.join(dir, "merged.json")

        expect {
          described_class.merge([path1, path2], output_path: output_path)
        }.to output(/2 tests.*30 factory creates/m).to_stdout

        expect(File.exist?(output_path)).to be true
      end
    end
  end
end
