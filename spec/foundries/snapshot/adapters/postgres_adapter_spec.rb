# frozen_string_literal: true

require "spec_helper"

RSpec.describe Foundries::Snapshot::Adapters::PostgresAdapter do
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:adapter) { described_class.new(connection) }

  describe "#reset_sequence" do
    it "returns early without touching the sequence when the table has no primary key" do
      allow(connection).to receive(:primary_key).with("widgets").and_return(nil)
      allow(connection).to receive(:execute)

      adapter.reset_sequence("widgets")

      expect(connection).not_to have_received(:execute)
    end

    it "returns early without touching the sequence when the pk has no sequence (UUID pk)" do
      allow(connection).to receive(:primary_key).with("widgets").and_return("id")
      allow(connection).to receive(:quote) { |value| "'#{value}'" }
      allow(connection).to receive(:select_value)
        .with("SELECT pg_get_serial_sequence('widgets', 'id')")
        .and_return(nil)
      allow(connection).to receive(:execute)

      adapter.reset_sequence("widgets")

      expect(connection).not_to have_received(:execute)
    end

    it "never issues a setval that could lower the sequence below its current value" do
      allow(connection).to receive(:primary_key).with("organizations").and_return("id")
      allow(connection).to receive(:quote) { |value| "'#{value}'" }
      allow(connection).to receive(:quote_column_name).with("id").and_return('"id"')
      allow(connection).to receive(:quote_table_name).with("organizations").and_return('"organizations"')
      allow(connection).to receive(:select_value)
        .with("SELECT pg_get_serial_sequence('organizations', 'id')")
        .and_return("organizations_id_seq")

      executed_sql = nil
      allow(connection).to receive(:execute) { |sql| executed_sql = sql }

      adapter.reset_sequence("organizations")

      # setval is not transactional and rows can exist that were committed
      # outside the restoring transaction, so the new value must be derived
      # from GREATEST(restored max id, current sequence value) — never a
      # bare literal that could rewind the sequence.
      expect(executed_sql).to include("GREATEST")
      expect(executed_sql).to include("last_value")
      expect(executed_sql).to include("organizations_id_seq")
      expect(executed_sql).not_to match(/setval\(\s*'organizations_id_seq',\s*\d/)
    end
  end
end
