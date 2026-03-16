# frozen_string_literal: true

require "spec_helper"
require "foundries/recording/node"

RSpec.describe Foundries::Recording::Node do
  def node(factory, traits: [], children: [])
    described_class.new(factory: factory, traits: traits, children: children)
  end

  describe "#factory" do
    it "returns the factory name as a symbol" do
      n = node(:user)
      expect(n.factory).to eq(:user)
    end

    it "coerces string factory names to symbols" do
      n = node("user")
      expect(n.factory).to eq(:user)
    end
  end

  describe "#traits" do
    it "defaults to an empty array" do
      n = node(:user)
      expect(n.traits).to eq([])
    end

    it "sorts traits alphabetically" do
      n = node(:user, traits: [:admin, :active])
      expect(n.traits).to eq([:active, :admin])
    end

    it "coerces string traits to symbols" do
      n = node(:user, traits: ["admin", "active"])
      expect(n.traits).to eq([:active, :admin])
    end
  end

  describe "#children" do
    it "defaults to an empty array" do
      n = node(:user)
      expect(n.children).to eq([])
    end

    it "accepts child nodes" do
      child = node(:project)
      parent = node(:team, children: [child])
      expect(parent.children).to eq([child])
    end
  end

  describe "#signature" do
    it "returns the factory name for a simple node" do
      expect(node(:user).signature).to eq("user")
    end

    it "includes sorted traits in brackets" do
      n = node(:user, traits: [:admin])
      expect(n.signature).to eq("user[:admin]")
    end

    it "includes multiple traits" do
      n = node(:user, traits: [:banned, :admin])
      expect(n.signature).to eq("user[:admin, :banned]")
    end

    it "includes children sorted alphabetically by signature" do
      children = [node(:user), node(:project)]
      parent = node(:team, children: children)
      expect(parent.signature).to eq("team > [project, user]")
    end

    it "handles traits and children together" do
      children = [node(:user)]
      parent = node(:team, traits: [:active], children: children)
      expect(parent.signature).to eq("team[:active] > [user]")
    end

    it "handles deeply nested children" do
      grandchild = node(:task)
      child = node(:project, children: [grandchild])
      parent = node(:team, children: [child])
      expect(parent.signature).to eq("team > [project > [task]]")
    end
  end

  describe "#normalize" do
    it "returns a new node with children sorted by signature" do
      children = [node(:user), node(:project)]
      parent = node(:team, children: children)
      normalized = parent.normalize
      expect(normalized.children.map(&:factory)).to eq([:project, :user])
    end

    it "deduplicates children keeping the one with the most descendants" do
      small_user = node(:user)
      big_user = node(:user, children: [node(:task)])
      parent = node(:team, children: [small_user, big_user])
      normalized = parent.normalize
      expect(normalized.children.size).to eq(1)
      expect(normalized.children.first.tree_size).to eq(2)
    end

    it "normalizes recursively" do
      grandchildren = [node(:task), node(:comment)]
      child = node(:project, children: grandchildren)
      parent = node(:team, children: [child])
      normalized = parent.normalize
      expect(normalized.children.first.children.map(&:factory)).to eq([:comment, :task])
    end

    it "does not mutate the original node" do
      children = [node(:user), node(:project)]
      parent = node(:team, children: children)
      parent.normalize
      expect(parent.children.map(&:factory)).to eq([:user, :project])
    end
  end

  describe "#tree_size" do
    it "returns 1 for a leaf node" do
      expect(node(:user).tree_size).to eq(1)
    end

    it "counts all descendants" do
      grandchild = node(:task)
      child = node(:project, children: [grandchild])
      parent = node(:team, children: [child, node(:user)])
      expect(parent.tree_size).to eq(4)
    end
  end

  describe "#to_h" do
    it "serializes a simple node" do
      expect(node(:user).to_h).to eq({
        factory: "user",
        traits: [],
        children: []
      })
    end

    it "serializes traits and children" do
      child = node(:project)
      parent = node(:team, traits: [:active], children: [child])
      expect(parent.to_h).to eq({
        factory: "team",
        traits: ["active"],
        children: [{ factory: "project", traits: [], children: [] }]
      })
    end
  end

  describe "#==" do
    it "considers nodes with the same signature equal" do
      a = node(:user, traits: [:admin])
      b = node(:user, traits: [:admin])
      expect(a).to eq(b)
    end

    it "considers nodes with different signatures not equal" do
      a = node(:user, traits: [:admin])
      b = node(:user)
      expect(a).not_to eq(b)
    end

    it "considers nodes with same factory but different children not equal" do
      a = node(:team, children: [node(:user)])
      b = node(:team)
      expect(a).not_to eq(b)
    end
  end

  describe "#eql?" do
    it "behaves like ==" do
      a = node(:user, traits: [:admin])
      b = node(:user, traits: [:admin])
      expect(a).to eql(b)
    end
  end

  describe "#hash" do
    it "is the same for nodes with the same signature" do
      a = node(:user, traits: [:admin])
      b = node(:user, traits: [:admin])
      expect(a.hash).to eq(b.hash)
    end

    it "works correctly in a Set" do
      require "set"
      a = node(:user, traits: [:admin])
      b = node(:user, traits: [:admin])
      set = Set.new([a, b])
      expect(set.size).to eq(1)
    end
  end

  describe "#to_s" do
    it "delegates to signature" do
      n = node(:user, traits: [:admin])
      expect(n.to_s).to eq(n.signature)
    end
  end

  describe "immutability" do
    it "freezes the node on creation" do
      n = node(:user, traits: [:admin], children: [node(:task)])
      expect(n).to be_frozen
    end
  end
end
