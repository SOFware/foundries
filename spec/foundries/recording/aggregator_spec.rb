# frozen_string_literal: true

require "spec_helper"
require "foundries/recording/node"
require "foundries/recording/aggregator"

RSpec.describe Foundries::Recording::Aggregator do
  def node(factory, traits: [], children: [])
    Foundries::Recording::Node.new(factory: factory, traits: traits, children: children)
  end

  def root(*children)
    node(:__root__, children: children)
  end

  describe "#candidates" do
    it "returns an empty array when results are empty" do
      aggregator = described_class.new({})
      expect(aggregator.candidates).to eq([])
    end

    it "finds full-tree candidates shared across tests" do
      tree = root(node(:team, children: [node(:user)]))

      results = {
        "test A" => tree,
        "test B" => tree,
        "test C" => tree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      team_candidate = candidates.find { |c| c[:structure] == "team > [user]" }
      expect(team_candidate).not_to be_nil
      expect(team_candidate[:frequency]).to eq(3)
      expect(team_candidate[:tree_size]).to eq(2)
      expect(team_candidate[:score]).to eq(6)
      expect(team_candidate[:tests]).to contain_exactly("test A", "test B", "test C")
    end

    it "filters out trivial trees with tree_size <= 1" do
      tree = root(node(:user))

      results = {
        "test A" => tree,
        "test B" => tree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      # A single :user node has tree_size 1, should be filtered out
      expect(candidates).to be_empty
    end

    it "sorts candidates by score descending" do
      # tree with team > [user] appears in 3 tests, tree_size 2, score 6
      small_tree = root(node(:team, children: [node(:user)]))
      # tree with team > [project, user] appears in 2 tests, tree_size 3, score 6
      big_tree = root(node(:team, children: [node(:project), node(:user)]))
      # For equal scores, just check they are both present

      results = {
        "test A" => small_tree,
        "test B" => small_tree,
        "test C" => small_tree,
        "test D" => big_tree,
        "test E" => big_tree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      scores = candidates.map { |c| c[:score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it "extracts subtree candidates from nested trees" do
      # root > [team > [project > [task], user]]
      # Subtrees: team > [project > [task], user] (full tree candidate)
      #           project > [task] (subtree candidate)
      tree = root(
        node(:team, children: [
          node(:project, children: [node(:task)]),
          node(:user)
        ])
      )

      results = {
        "test A" => tree,
        "test B" => tree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      structures = candidates.map { |c| c[:structure] }
      expect(structures).to include("team > [project > [task], user]")
      expect(structures).to include("project > [task]")
    end

    it "deduplicates by structure string when merging full-tree and subtree candidates" do
      # If a subtree is the same as a full tree from another test, they merge
      subtree = node(:team, children: [node(:user)])
      big_tree = root(subtree, node(:project))
      small_tree = root(node(:team, children: [node(:user)]))

      results = {
        "test A" => big_tree,
        "test B" => small_tree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      team_candidates = candidates.select { |c| c[:structure] == "team > [user]" }
      expect(team_candidates.size).to eq(1)
      # Both tests should be included
      expect(team_candidates.first[:tests]).to contain_exactly("test A", "test B")
    end

    it "normalizes trees before aggregation" do
      # Two trees that differ only in child order should be grouped together
      tree_a = root(node(:team, children: [node(:user), node(:project)]))
      tree_b = root(node(:team, children: [node(:project), node(:user)]))

      results = {
        "test A" => tree_a,
        "test B" => tree_b
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      team_candidate = candidates.find { |c| c[:structure] == "team > [project, user]" }
      expect(team_candidate).not_to be_nil
      expect(team_candidate[:frequency]).to eq(2)
    end

    it "uses root children signatures for full-tree structure display" do
      tree = root(
        node(:team, children: [node(:user)]),
        node(:project)
      )

      results = {"test A" => tree, "test B" => tree}

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      # Full tree candidate should show root's children joined by ", "
      full_tree = candidates.find { |c| c[:structure] == "project, team > [user]" }
      expect(full_tree).not_to be_nil
    end

    it "uses subtree signature directly for subtree candidates" do
      tree = root(node(:team, children: [node(:project), node(:user)]))

      results = {"test A" => tree, "test B" => tree}

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      team_candidate = candidates.find { |c| c[:structure] == "team > [project, user]" }
      expect(team_candidate).not_to be_nil
    end

    it "handles traits in signatures" do
      tree = root(node(:user, traits: [:admin], children: [node(:task)]))

      results = {
        "test A" => tree,
        "test B" => tree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      admin_candidate = candidates.find { |c| c[:structure] == "user[:admin] > [task]" }
      expect(admin_candidate).not_to be_nil
      expect(admin_candidate[:frequency]).to eq(2)
    end

    it "counts frequency correctly across different tests" do
      tree_with_subtree = root(
        node(:team, children: [
          node(:project, children: [node(:task)])
        ])
      )
      tree_with_same_subtree = root(
        node(:team, children: [
          node(:project, children: [node(:task)]),
          node(:user)
        ])
      )

      results = {
        "test A" => tree_with_subtree,
        "test B" => tree_with_same_subtree,
        "test C" => tree_with_subtree
      }

      aggregator = described_class.new(results)
      candidates = aggregator.candidates

      # project > [task] appears as subtree in all 3 tests
      proj_candidate = candidates.find { |c| c[:structure] == "project > [task]" }
      expect(proj_candidate).not_to be_nil
      expect(proj_candidate[:frequency]).to eq(3)
      expect(proj_candidate[:tree_size]).to eq(2)
      expect(proj_candidate[:score]).to eq(6)
    end
  end
end
