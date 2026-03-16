# frozen_string_literal: true

require "spec_helper"
require "foundries/recording/node"
require "foundries/recording/aggregator"
require "foundries/recording/reporter"
require "json"
require "tmpdir"

RSpec.describe Foundries::Recording::Reporter do
  def node(factory, traits: [], children: [])
    Foundries::Recording::Node.new(factory: factory, traits: traits, children: children)
  end

  def root(*children)
    node(:__root__, children: children)
  end

  let(:results) do
    tree = root(node(:team, children: [node(:project), node(:user)]))
    {
      "test A" => tree,
      "test B" => tree
    }
  end

  let(:reporter) do
    described_class.new(results: results, total_creates: 3841, total_tests: 482)
  end

  describe "#candidates" do
    it "delegates to Aggregator and returns candidates" do
      candidates = reporter.candidates
      expect(candidates).to be_an(Array)
      expect(candidates.first[:structure]).to eq("team > [project, user]")
    end

    it "memoizes the result" do
      expect(reporter.candidates).to be(reporter.candidates)
    end
  end

  describe "#write_json" do
    it "writes valid JSON to the specified path" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        reporter.write_json(path)

        content = File.read(path)
        data = JSON.parse(content)
        expect(data).to be_a(Hash)
      end
    end

    it "creates parent directories if they don't exist" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "deep", "report.json")
        reporter.write_json(path)

        expect(File.exist?(path)).to be true
      end
    end

    it "includes recorded_at timestamp" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        reporter.write_json(path)

        data = JSON.parse(File.read(path))
        expect(data["recorded_at"]).to be_a(String)
        expect { Time.parse(data["recorded_at"]) }.not_to raise_error
      end
    end

    it "includes total_tests and total_factory_creates" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        reporter.write_json(path)

        data = JSON.parse(File.read(path))
        expect(data["total_tests"]).to eq(482)
        expect(data["total_factory_creates"]).to eq(3841)
      end
    end

    it "includes candidates with correct structure" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        reporter.write_json(path)

        data = JSON.parse(File.read(path))
        candidates = data["candidates"]
        expect(candidates).to be_an(Array)
        expect(candidates.first).to include(
          "structure", "frequency", "tree_size", "score", "tests"
        )
      end
    end

    it "includes per_test section with factories_created and tree" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        reporter.write_json(path)

        data = JSON.parse(File.read(path))
        per_test = data["per_test"]
        expect(per_test).to be_a(Hash)
        expect(per_test.keys).to contain_exactly("test A", "test B")

        test_data = per_test["test A"]
        expect(test_data["factories_created"]).to eq(1)
        expect(test_data["tree"]).to be_an(Array)
        expect(test_data["tree"].first["factory"]).to eq("team")
      end
    end
  end

  describe "#summary" do
    it "includes test and create counts" do
      output = reporter.summary
      expect(output).to include("482 tests")
      expect(output).to include("3841 factory creates")
    end

    it "lists top candidates with rank, structure, frequency, and score" do
      output = reporter.summary
      expect(output).to include("1. team > [project, user] (2 tests, score: 6)")
    end

    it "includes json_path line when json_path is provided" do
      output = reporter.summary(json_path: "tmp/foundries/recording.json")
      expect(output).to include("[Foundries] Full report: tmp/foundries/recording.json")
    end

    it "omits json_path line when json_path is not provided" do
      output = reporter.summary
      expect(output).not_to include("Full report:")
    end

    it "prints no-candidates message when there are none" do
      empty_reporter = described_class.new(results: {}, total_creates: 0, total_tests: 0)
      output = empty_reporter.summary
      expect(output).to include("[Foundries] No preset candidates found.")
    end

    it "limits output to MAX_STDOUT_CANDIDATES" do
      # Build 12 distinct structures so we get 12 candidates
      many_results = {}
      12.times do |i|
        children = [node(:"factory_#{i}", children: [node(:child)])]
        many_results["test #{i}a"] = root(*children)
        many_results["test #{i}b"] = root(*children)
      end

      big_reporter = described_class.new(
        results: many_results, total_creates: 100, total_tests: 24
      )
      output = big_reporter.summary
      numbered_lines = output.lines.select { |l| l.match?(/^\s+\d+\./) }
      expect(numbered_lines.size).to be <= 10
    end

    it "starts with Recording complete header" do
      output = reporter.summary
      expect(output).to include("[Foundries] Recording complete.")
    end

    it "includes Top preset candidates header when candidates exist" do
      output = reporter.summary
      expect(output).to include("[Foundries] Top preset candidates:")
    end
  end

  describe ".merge_files" do
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

    it "merges multiple JSON files with correct totals and keys" do
      Dir.mktmpdir do |dir|
        path1 = write_worker_json(dir, "worker1.json",
          total_creates: 10,
          per_test: {
            "test A" => {
              factories_created: 1,
              tree: [{factory: "team", traits: [], children: [{factory: "user", traits: [], children: []}]}]
            }
          })

        path2 = write_worker_json(dir, "worker2.json",
          total_creates: 20,
          per_test: {
            "test B" => {
              factories_created: 1,
              tree: [{factory: "team", traits: [], children: [{factory: "project", traits: [], children: []}]}]
            }
          })

        output_path = File.join(dir, "merged.json")
        described_class.merge_files([path1, path2], output_path: output_path)

        data = JSON.parse(File.read(output_path))
        expect(data["total_tests"]).to eq(2)
        expect(data["total_factory_creates"]).to eq(30)
        expect(data["per_test"].keys).to contain_exactly("test A", "test B")
        expect(data["candidates"]).to be_an(Array)
      end
    end

    it "returns a summary string with correct counts" do
      Dir.mktmpdir do |dir|
        path1 = write_worker_json(dir, "worker1.json",
          total_creates: 5,
          per_test: {
            "test A" => {
              factories_created: 1,
              tree: [{factory: "team", traits: [], children: []}]
            }
          })

        output_path = File.join(dir, "merged.json")
        summary = described_class.merge_files([path1], output_path: output_path)

        expect(summary).to include("1 tests")
        expect(summary).to include("5 factory creates")
        expect(summary).to include("[Foundries] Full report:")
      end
    end

    it "re-aggregates to find patterns across workers" do
      Dir.mktmpdir do |dir|
        shared_tree = [{factory: "team", traits: [], children: [{factory: "user", traits: [], children: []}]}]

        path1 = write_worker_json(dir, "worker1.json",
          total_creates: 2,
          per_test: {
            "test A" => {factories_created: 1, tree: shared_tree}
          })

        path2 = write_worker_json(dir, "worker2.json",
          total_creates: 2,
          per_test: {
            "test B" => {factories_created: 1, tree: shared_tree}
          })

        output_path = File.join(dir, "merged.json")
        described_class.merge_files([path1, path2], output_path: output_path)

        data = JSON.parse(File.read(output_path))
        candidate = data["candidates"].find { |c| c["structure"] == "team > [user]" }
        expect(candidate).not_to be_nil
        expect(candidate["frequency"]).to eq(2)
      end
    end
  end
end
