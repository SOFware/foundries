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

  describe "#find with parent scoping" do
    it "scopes database fallback by parent_key and parent_id" do
      team_a = create(:team, name: "A")
      team_b = create(:team, name: "B")
      _user_a = create(:user, name: "Shared", team: team_a)
      user_b = create(:user, name: "Shared", team: team_b)

      foundry = TestFoundry.new do
        team "B" do
          user "Shared" # should find the one scoped to team B
        end
      end

      expect(foundry.user("Shared")).to eq user_b
    end

    it "finds from collection before hitting the database" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice"
          user "Alice" # second call should find from collection
        end
      end

      expect(User.where(name: "Alice").count).to eq 1
      expect(foundry.users_collection.size).to eq 1
    end
  end

  describe "#collection_find_by with kwargs" do
    it "supports keyword arguments" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice", role: "admin"
          user "Bob", role: "member"
        end
      end

      blueprint = foundry.instance_variable_get(:@user_blueprint)
      result = blueprint.send(:collection_find_by, "user", {role: "admin"})
      expect(result.name).to eq "Alice"
    end

    it "supports hash argument" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice", role: "admin"
          user "Bob", role: "member"
        end
      end

      blueprint = foundry.instance_variable_get(:@user_blueprint)
      result = blueprint.send(:collection_find_by, "user", {role: "member"})
      expect(result.name).to eq "Bob"
    end
  end

  describe "#find_or_create" do
    it "finds existing record from parent association when parent is present" do
      team = create(:team, name: "Engineering")
      existing_user = create(:user, name: "Alice", team: team)

      foundry = TestFoundry.new do
        team "Engineering" do
          user "Bob"
        end
      end

      blueprint = foundry.instance_variable_get(:@user_blueprint)
      foundry.current.team = foundry.team("Engineering")

      result = blueprint.find_or_create("Alice")
      expect(result).to eq existing_user
    end

    it "falls back to ascending_find when parent is not present" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice"
        end
      end

      blueprint = foundry.instance_variable_get(:@user_blueprint)
      # Clear parent from current state
      foundry.current.team = nil

      result = blueprint.find_or_create("Alice")
      expect(result.name).to eq "Alice"
    end
  end

  describe "#parent_present?" do
    it "returns true when parent method is :none" do
      foundry = TestFoundry.new
      blueprint = foundry.instance_variable_get(:@team_blueprint)
      expect(blueprint.parent_present?).to be true
    end

    it "returns truthy when parent exists in current state" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice"
        end
      end

      blueprint = foundry.instance_variable_get(:@user_blueprint)
      foundry.current.team = foundry.team("Engineering")
      expect(blueprint.parent_present?).to be_truthy
    end

    it "returns falsy when parent is not set" do
      foundry = TestFoundry.new
      blueprint = foundry.instance_variable_get(:@user_blueprint)
      expect(blueprint.parent_present?).to be_falsy
    end
  end

  describe "#ascending_find" do
    it "falls back to collection find when no ancestors match" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice"
        end
      end

      blueprint = foundry.instance_variable_get(:@user_blueprint)
      result = blueprint.ascending_find("Alice")
      expect(result.name).to eq "Alice"
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
