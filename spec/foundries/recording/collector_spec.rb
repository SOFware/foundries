# frozen_string_literal: true

require "spec_helper"
require "foundries/recording/node"
require "foundries/recording/collector"

RSpec.describe Foundries::Recording::Collector do
  include FactoryBot::Syntax::Methods

  subject(:collector) { described_class.new }

  describe "#start_test and #stop_test" do
    it "records a basic create call" do
      collector.start_test(:test_1)
      create(:team)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      expect(root.factory).to eq(:__root__)
      expect(root.children.size).to eq(1)
      expect(root.children.first.factory).to eq(:team)
    end

    it "records multiple create calls in one test" do
      collector.start_test(:test_1)
      create(:team)
      create(:user)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      expect(root.children.size).to eq(2)
      expect(root.children.map(&:factory)).to contain_exactly(:team, :user)
    end

    it "does not record build calls" do
      collector.start_test(:test_1)
      build(:team)
      create(:user)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      expect(root.children.size).to eq(1)
      expect(root.children.first.factory).to eq(:user)
    end

    it "captures traits" do
      collector.start_test(:test_1)
      create(:user, :admin)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      user_node = root.children.first
      expect(user_node.factory).to eq(:user)
      expect(user_node.traits).to eq([:admin])
    end

    it "records multiple tests independently" do
      collector.start_test(:test_1)
      create(:team)
      collector.stop_test(:test_1)

      collector.start_test(:test_2)
      create(:user)
      create(:project)
      collector.stop_test(:test_2)

      expect(collector.results[:test_1].children.size).to eq(1)
      expect(collector.results[:test_1].children.first.factory).to eq(:team)

      expect(collector.results[:test_2].children.size).to eq(2)
      expect(collector.results[:test_2].children.map(&:factory)).to contain_exactly(:user, :project)
    end
  end

  describe "#total_creates" do
    it "returns 0 when nothing has been recorded" do
      expect(collector.total_creates).to eq(0)
    end

    it "counts all create calls across tests" do
      collector.start_test(:test_1)
      create(:team)
      create(:user)
      collector.stop_test(:test_1)

      collector.start_test(:test_2)
      create(:project)
      collector.stop_test(:test_2)

      expect(collector.total_creates).to eq(3)
    end

    it "does not count build calls" do
      collector.start_test(:test_1)
      build(:team)
      create(:user)
      collector.stop_test(:test_1)

      expect(collector.total_creates).to eq(1)
    end
  end

  describe "nesting" do
    before(:all) do
      # Define factories with associations to test nesting
      FactoryBot.define do
        factory :user_with_team, class: "User" do
          sequence(:name) { |n| "User #{n}" }
          sequence(:email) { |n| "user_wt#{n}@example.com" }
          role { "member" }
          team
        end

        factory :task_with_deps, class: "Task" do
          sequence(:name) { |n| "Task #{n}" }
          priority { "normal" }
          association :project
          association :user
        end
      end
    end

    it "captures nested creates from associations as children" do
      collector.start_test(:test_1)
      create(:user_with_team)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      expect(root.children.size).to eq(1)

      user_node = root.children.first
      expect(user_node.factory).to eq(:user_with_team)
      expect(user_node.children.size).to eq(1)
      expect(user_node.children.first.factory).to eq(:team)
    end

    it "captures multiple levels of nesting" do
      collector.start_test(:test_1)
      create(:task_with_deps)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      task_node = root.children.first
      expect(task_node.factory).to eq(:task_with_deps)
      expect(task_node.children.map(&:factory)).to contain_exactly(:project, :user)
    end

    it "counts nested creates in total_creates" do
      collector.start_test(:test_1)
      create(:user_with_team)
      collector.stop_test(:test_1)

      # user_with_team creates: user + team = 2
      expect(collector.total_creates).to eq(2)
    end
  end

  describe "#results" do
    it "returns an empty hash when nothing has been recorded" do
      expect(collector.results).to eq({})
    end

    it "returns frozen Node objects" do
      collector.start_test(:test_1)
      create(:team)
      collector.stop_test(:test_1)

      root = collector.results[:test_1]
      expect(root).to be_a(Foundries::Recording::Node)
      expect(root).to be_frozen
    end
  end
end
