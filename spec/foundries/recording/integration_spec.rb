# frozen_string_literal: true

require "spec_helper"
require "foundries/recording"
require "tmpdir"

RSpec.describe "Recording integration" do
  let(:collector) { Foundries::Recording::Collector.new }

  it "captures factory creates, finds patterns, and produces a report" do
    # Simulate three tests with overlapping patterns
    collector.start_test("test 1: user edits task")
    team = create(:team)
    user = create(:user, team: team)
    project = create(:project, team: team)
    create(:task, project: project, user: user)
    collector.stop_test("test 1: user edits task")

    collector.start_test("test 2: user views task")
    team2 = create(:team)
    user2 = create(:user, team: team2)
    project2 = create(:project, team: team2)
    create(:task, project: project2, user: user2)
    collector.stop_test("test 2: user views task")

    collector.start_test("test 3: team listing")
    create(:team)
    create(:user)
    collector.stop_test("test 3: team listing")

    # Build the reporter from collected data
    reporter = Foundries::Recording::Reporter.new(
      results: collector.results,
      total_creates: collector.total_creates,
      total_tests: collector.results.size
    )

    # 1. Reporter candidates is not empty
    expect(reporter.candidates).not_to be_empty

    # 2. The top candidate has frequency >= 2
    top = reporter.candidates.first
    expect(top[:frequency]).to be >= 2

    # 3. Summary string includes "3 tests" and "factory creates"
    summary = reporter.summary
    expect(summary).to include("3 tests")
    expect(summary).to include("factory creates")

    # 4. JSON file is writable and parseable with correct structure
    Dir.mktmpdir do |dir|
      json_path = File.join(dir, "recording.json")
      reporter.write_json(json_path)

      data = JSON.parse(File.read(json_path))
      expect(data).to have_key("total_tests")
      expect(data).to have_key("total_factory_creates")
      expect(data).to have_key("candidates")
      expect(data).to have_key("per_test")

      # 5. per_test has 3 entries
      expect(data["per_test"].size).to eq(3)
    end
  end
end
