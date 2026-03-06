# frozen_string_literal: true

require "spec_helper"
require_relative "base_spec"

RSpec.describe Foundries::Similarity do
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe "integration" do
    let(:foundry_class) do
      Class.new(Foundries::Base) do
        blueprint TeamBlueprint
        blueprint UserBlueprint
        blueprint ProjectBlueprint
        blueprint TaskBlueprint

        def self.name
          "TestFoundry"
        end
      end
    end

    context "when enabled" do
      before { described_class.enabled = true }

      it "warns when two presets have identical structure" do
        foundry_class.preset(:basic) do
          team "A" do
            user "Alice"
          end
        end

        foundry_class.preset(:duplicate) do
          team "B" do
            user "Bob"
          end
        end

        expect { foundry_class.basic }.not_to output.to_stderr
        expect { foundry_class.duplicate }.to output(/identical structure/).to_stderr
      end

      it "does not warn on containment" do
        foundry_class.preset(:full) do
          team "A" do
            user "Alice"
            project "P1" do
              task "T1"
            end
          end
        end

        foundry_class.preset(:partial) do
          team "B" do
            user "Bob"
          end
        end

        foundry_class.full
        expect { foundry_class.partial }.not_to output.to_stderr
      end

      it "produces no warning when structures differ" do
        foundry_class.preset(:teams_only) do
          team "A"
        end

        foundry_class.preset(:users_only) do
          user "Alice"
        end

        foundry_class.teams_only
        expect { foundry_class.users_only }.not_to output.to_stderr
      end
    end

    context "when disabled" do
      before { described_class.enabled = false }

      it "produces no warnings" do
        foundry_class.preset(:basic) do
          team "A" do
            user "Alice"
          end
        end

        foundry_class.preset(:duplicate) do
          team "B" do
            user "Bob"
          end
        end

        foundry_class.basic
        expect { foundry_class.duplicate }.not_to output.to_stderr
      end
    end
  end
end
