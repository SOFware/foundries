# frozen_string_literal: true

require "spec_helper"
require "foundries/recording"

RSpec.describe Foundries::Recording do
  before { described_class.reset! }
  after { described_class.reset! }

  describe ".enabled?" do
    it "returns false by default when env is not set" do
      allow(ENV).to receive(:[]).with("FOUNDRIES_RECORD").and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it "returns true when FOUNDRIES_RECORD is '1'" do
      allow(ENV).to receive(:[]).with("FOUNDRIES_RECORD").and_return("1")
      expect(described_class.enabled?).to be true
    end

    it "returns false when FOUNDRIES_RECORD is '0'" do
      allow(ENV).to receive(:[]).with("FOUNDRIES_RECORD").and_return("0")
      expect(described_class.enabled?).to be false
    end

    it "respects the explicit setter over env" do
      allow(ENV).to receive(:[]).with("FOUNDRIES_RECORD").and_return("1")
      described_class.enabled = false
      expect(described_class.enabled?).to be false
    end

    it "respects true override when env is not set" do
      allow(ENV).to receive(:[]).with("FOUNDRIES_RECORD").and_return(nil)
      described_class.enabled = true
      expect(described_class.enabled?).to be true
    end
  end

  describe ".collector" do
    it "returns a Collector instance" do
      expect(described_class.collector).to be_a(Foundries::Recording::Collector)
    end

    it "returns the same instance on repeated calls" do
      expect(described_class.collector).to be(described_class.collector)
    end
  end

  describe ".output_path" do
    it "defaults to tmp/foundries/recording.json" do
      expect(described_class.output_path).to eq("tmp/foundries/recording.json")
    end

    it "is settable" do
      described_class.output_path = "custom/path.json"
      expect(described_class.output_path).to eq("custom/path.json")
    end
  end

  describe ".reset!" do
    it "clears the collector" do
      original = described_class.collector
      described_class.reset!
      expect(described_class.collector).not_to be(original)
    end

    it "clears enabled override" do
      described_class.enabled = true
      described_class.reset!
      allow(ENV).to receive(:[]).with("FOUNDRIES_RECORD").and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it "resets output_path to default" do
      described_class.output_path = "custom/path.json"
      described_class.reset!
      expect(described_class.output_path).to eq("tmp/foundries/recording.json")
    end
  end

  describe ".report!" do
    let(:tmp_dir) { "tmp/foundries_test_#{Process.pid}" }
    let(:output_path) { "#{tmp_dir}/recording.json" }

    before do
      described_class.output_path = output_path
      # Simulate a test with some factory creates
      described_class.collector.start_test("example test")
      described_class.collector.stop_test("example test")
    end

    after do
      FileUtils.rm_rf(tmp_dir)
    end

    it "writes a JSON file to output_path" do
      described_class.report!
      expect(File.exist?(output_path)).to be true
      data = JSON.parse(File.read(output_path))
      expect(data).to have_key("total_tests")
      expect(data["total_tests"]).to eq(1)
    end

    it "prints summary to $stdout" do
      output = StringIO.new
      begin
        $stdout = output
        described_class.report!
      ensure
        $stdout = STDOUT
      end
      expect(output.string).to include("[Foundries] Recording complete.")
    end
  end
end
