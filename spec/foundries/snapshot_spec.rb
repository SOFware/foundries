# frozen_string_literal: true

require "spec_helper"

RSpec.describe Foundries::Snapshot do
  after { described_class.connection = nil }

  describe ".adapter" do
    def connection_with_tables(tables)
      double("connection", adapter_name: "PostgreSQL", tables:)
    end

    it "wraps the connection current at each call" do
      described_class.connection = connection_with_tables(%w[teams])
      described_class.adapter

      described_class.connection = connection_with_tables(%w[users])

      expect(described_class.adapter.table_names).to eq(%w[users])
    end
  end
end
