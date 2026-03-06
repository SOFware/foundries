# frozen_string_literal: true

require "spec_helper"
require "foundries/similarity/structure_tree"
require "foundries/similarity/comparator"

RSpec.describe Foundries::Similarity::Comparator do
  def tree(name, children: [])
    Foundries::Similarity::StructureTree.new(name, children: children)
  end

  describe ".compare" do
    it "detects identical structures" do
      structure = tree("__root__", children: [
        tree("team", children: [tree("user")])
      ])
      registry = {"MyFoundry.basic" => structure}

      warnings = described_class.compare("MyFoundry.extended", structure, registry)

      expect(warnings.size).to eq 1
      expect(warnings.first[:message]).to include("identical structure")
      expect(warnings.first[:message]).to include(":extended")
      expect(warnings.first[:message]).to include(":basic")
      expect(warnings.first[:pair]).to contain_exactly("MyFoundry.basic", "MyFoundry.extended")
    end

    it "does not warn on containment when existing contains new" do
      small = tree("__root__", children: [tree("team")])
      large = tree("__root__", children: [
        tree("team", children: [tree("user")])
      ])
      registry = {"MyFoundry.complex" => large}

      warnings = described_class.compare("MyFoundry.simple", small, registry)

      expect(warnings).to be_empty
    end

    it "does not warn on containment when new contains existing" do
      small = tree("__root__", children: [tree("team")])
      large = tree("__root__", children: [
        tree("team", children: [tree("user")])
      ])
      registry = {"MyFoundry.simple" => small}

      warnings = described_class.compare("MyFoundry.complex", large, registry)

      expect(warnings).to be_empty
    end

    it "returns empty array when no similarity" do
      tree_a = tree("__root__", children: [tree("team")])
      tree_b = tree("__root__", children: [tree("user")])
      registry = {"MyFoundry.a" => tree_a}

      warnings = described_class.compare("MyFoundry.b", tree_b, registry)

      expect(warnings).to be_empty
    end

    it "skips self-comparison" do
      structure = tree("__root__", children: [tree("team")])
      registry = {"MyFoundry.same" => structure}

      warnings = described_class.compare("MyFoundry.same", structure, registry)

      expect(warnings).to be_empty
    end
  end
end
