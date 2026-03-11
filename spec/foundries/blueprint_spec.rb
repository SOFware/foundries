# frozen_string_literal: true

require "spec_helper"

RSpec.describe Foundries::Blueprint do
  describe "class-level DSL" do
    it "registers handled methods" do
      klass = Class.new(Foundries::Blueprint) do
        handles :foo, :bar
      end

      expect(klass.handled_methods).to eq [:foo, :bar]
    end

    it "infers factory name from class name" do
      # Create a named class to test inference
      stub_const("UserBlueprint", Class.new(Foundries::Blueprint))
      expect(UserBlueprint.factory_name).to eq :user
    end

    it "allows explicit factory name" do
      klass = Class.new(Foundries::Blueprint) do
        factory :special_user
      end

      expect(klass.factory_name).to eq :special_user
    end

    it "stores collection name" do
      klass = Class.new(Foundries::Blueprint) do
        collection :users
      end

      expect(klass.collection_name).to eq :users
    end

    it "stores parent key" do
      klass = Class.new(Foundries::Blueprint) do
        parent_key :team_id
      end

      expect(klass.parent_key).to eq :team_id
    end
  end

  describe "default parent" do
    let(:klass) { Class.new(Foundries::Blueprint) }
    let(:foundry) { double("foundry") }
    let(:instance) { klass.new(foundry) }

    it "returns nil when no parent is declared" do
      expect(instance.parent).to be_nil
    end

    it "same_parent? returns true when no parent is declared" do
      record = double("record")
      expect(instance.same_parent?(record)).to be true
    end
  end

  describe "lookup_order" do
    it "defaults to empty array" do
      klass = Class.new(Foundries::Blueprint)
      expect(klass.lookup_order).to eq []
    end

    it "stores declared lookup order" do
      klass = Class.new(Foundries::Blueprint) do
        lookup_order %i[phase cohort]
      end
      expect(klass.lookup_order).to eq %i[phase cohort]
    end
  end
end
