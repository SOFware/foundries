# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Foundries::Snapshot::Store do
  let(:storage_path) { Dir.mktmpdir("foundries_test") }
  let(:connection) { ActiveRecord::Base.connection }
  let(:adapter) { Foundries::Snapshot::Adapters::SqliteAdapter.new(connection) }

  before do
    connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR NOT NULL)
    SQL
    connection.execute("DELETE FROM schema_migrations")
    connection.execute(
      "INSERT INTO schema_migrations (version) VALUES ('20240101000000')"
    )
  end

  after do
    FileUtils.rm_rf(storage_path)
  end

  describe "#cached?" do
    it "returns false when no cache exists" do
      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      expect(store).not_to be_cached
    end

    it "returns true after capture" do
      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      create(:team, name: "Cached")
      store.capture

      expect(store).to be_cached
    end

    it "returns false when fingerprint changes" do
      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      create(:team, name: "Cached")
      store.capture

      connection.execute(
        "INSERT INTO schema_migrations (version) VALUES ('20240202000000')"
      )

      fresh_store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      expect(fresh_store).not_to be_cached
    end
  end

  describe "#capture and #restore" do
    it "captures and restores table data" do
      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)

      team = create(:team, name: "Engineering")
      create(:user, name: "Alice", team: team)
      create(:user, name: "Bob", team: team)

      store.capture

      # Delete all records
      connection.execute("DELETE FROM users")
      connection.execute("DELETE FROM teams")
      expect(Team.count).to eq 0
      expect(User.count).to eq 0

      # Restore
      store.restore

      expect(Team.count).to eq 1
      expect(User.count).to eq 2
      expect(Team.find_by(name: "Engineering")).to be_present
      expect(User.pluck(:name)).to contain_exactly("Alice", "Bob")
    end

    it "handles empty tables gracefully" do
      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)

      store.capture
      expect(store).to be_cached

      store.restore # should not raise
    end
  end

  describe "atomic write" do
    it "creates cache in the named directory" do
      store = described_class.new(:my_preset, adapter: adapter, storage_path: storage_path)
      create(:team, name: "Test")
      store.capture

      cache_dir = Pathname.new(storage_path).join("my_preset")
      expect(cache_dir).to be_directory
      expect(cache_dir.join("teams.dat")).to exist
      expect(cache_dir.join(".fingerprint")).to exist
    end
  end

  describe "#capture with a table that was not empty beforehand" do
    it "refuses to write a snapshot when the preset adds to a pre-populated table" do
      create(:team, name: "Pre-existing")

      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      store.record_empty_tables

      # The preset adds to `teams` (already populated) and to `users` (empty).
      team = create(:team, name: "From preset")
      create(:user, name: "Alice", team: team)

      expect { store.capture }.to output.to_stderr

      expect(store).not_to be_cached
      expect(Pathname.new(storage_path).join("test_preset")).not_to exist
    end

    it "warns naming the preset and the tables it could not capture" do
      create(:team, name: "Pre-existing")

      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      store.record_empty_tables
      create(:team, name: "From preset")

      expect { store.capture }.to output(/test_preset.*teams/m).to_stderr
    end

    it "captures normally when the pre-populated table is left untouched" do
      create(:team, name: "Pre-existing")

      store = described_class.new(:test_preset, adapter: adapter, storage_path: storage_path)
      store.record_empty_tables

      team = Team.first
      create(:user, name: "Alice", team: team)

      store.capture

      expect(store).to be_cached
      cache_dir = Pathname.new(storage_path).join("test_preset")
      expect(cache_dir.join("users.dat")).to exist
      expect(cache_dir.join("teams.dat")).not_to exist
    end
  end

  describe "source_paths invalidation" do
    let(:source_dir) { Dir.mktmpdir("foundries_source") }
    let(:source_file) { File.join(source_dir, "foundry.rb") }

    after { FileUtils.rm_rf(source_dir) }

    it "invalidates cache when source file content changes" do
      File.write(source_file, "class MyFoundry; end")

      store = described_class.new(:test_preset, adapter: adapter,
        storage_path: storage_path, source_paths: [source_file])
      create(:team, name: "Cached")
      store.capture
      expect(store).to be_cached

      File.write(source_file, "class MyFoundry; def changed; end; end")

      fresh_store = described_class.new(:test_preset, adapter: adapter,
        storage_path: storage_path, source_paths: [source_file])
      expect(fresh_store).not_to be_cached
    end
  end
end
