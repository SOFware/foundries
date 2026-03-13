# frozen_string_literal: true

require "spec_helper"

# --- Test blueprints ---

class TeamBlueprint < Foundries::Blueprint
  handles :team
  factory :team
  collection :teams
  parent :none
  permitted_attrs %i[name]

  def team(name, attrs = {}, &block)
    @attrs = attrs.merge(name: name)
    object = find(name) || create_object
    update_state_for_block(object, &block) if block
    object
  ensure
    reset_attrs
  end

  private

  def create_object
    create(:team, attrs).tap { |record| collection << record }
  end

  def attrs
    permitted_attrs @attrs
  end
end

class UserBlueprint < Foundries::Blueprint
  handles :user, :admin
  factory :user
  collection :users
  parent :team
  parent_key :team_id
  permitted_attrs %i[name email role]

  def admin(name, attrs = {}, &block)
    user(name, attrs.merge(role: "admin"), &block)
  end

  def user(name, attrs = {}, &block)
    @attrs = attrs.merge(name: name)
    object = find(name) || create_object
    update_state_for_block(object, &block) if block
    object
  ensure
    reset_attrs
  end

  private

  def create_object
    create(:user, attrs).tap { |record| collection << record }
  end

  def attrs
    @attrs[parent_key] = parent_id
    permitted_attrs @attrs
  end
end

class ProjectBlueprint < Foundries::Blueprint
  handles :project
  factory :project
  collection :projects
  parent :team
  parent_key :team_id
  ancestor :team
  permitted_attrs %i[name status]

  def project(name, attrs = {}, &block)
    @attrs = attrs.merge(name: name)
    object = find(name) || create_object
    update_state_for_block(object, &block) if block
    object
  ensure
    reset_attrs
  end

  private

  def create_object
    create(:project, attrs).tap { |record| collection << record }
  end

  def attrs
    @attrs[parent_key] = parent_id
    permitted_attrs @attrs
  end
end

class TaskBlueprint < Foundries::Blueprint
  handles :task
  factory :task
  collection :tasks
  parent :project
  parent_key :project_id
  ancestor :project
  permitted_attrs %i[name priority user_id]

  def task(name, attrs = {}, &block)
    @attrs = attrs.merge(name: name)
    object = find(name) || create_object
    update_state_for_block(object, &block) if block
    object
  ensure
    reset_attrs
  end

  private

  def create_object
    create(:task, attrs).tap { |record| collection << record }
  end

  def attrs
    @attrs[parent_key] = parent_id
    permitted_attrs @attrs
  end
end

# A blueprint that never calls `parent` at all (no parent declaration)
class ParentlessBlueprint < Foundries::Blueprint
  handles :parentless_team
  factory :team
  collection :teams
  permitted_attrs %i[name]

  def parentless_team(name, attrs = {})
    @attrs = attrs.merge(name: name)
    object = find(name) || create_object
    object
  ensure
    reset_attrs
  end

  private

  def create_object
    create(:team, attrs).tap { |record| collection << record }
  end

  def attrs
    permitted_attrs @attrs
  end
end

# --- Test foundry ---

class TestFoundry < Foundries::Base
  blueprint TeamBlueprint
  blueprint UserBlueprint
  blueprint ProjectBlueprint
  blueprint TaskBlueprint
end

# --- Specs ---

RSpec.describe Foundries::Base do
  describe "blueprint registration" do
    it "registers blueprints" do
      expect(TestFoundry.blueprint_registry.keys).to contain_exactly(
        TeamBlueprint, UserBlueprint, ProjectBlueprint, TaskBlueprint
      )
    end

    it "tracks collection accessors" do
      expect(TestFoundry.collection_accessors).to contain_exactly(
        "teams_collection", "users_collection", "projects_collection", "tasks_collection"
      )
    end
  end

  describe "building records" do
    it "creates a simple record" do
      foundry = TestFoundry.new do
        team "Engineering"
      end

      eng = foundry.team("Engineering")
      expect(eng).to be_a(Team)
      expect(eng.name).to eq "Engineering"
      expect(Team.count).to eq 1
    end

    it "finds existing records instead of duplicating" do
      foundry = TestFoundry.new do
        team "Engineering"
        team "Engineering"
      end

      expect(Team.count).to eq 1
      expect(foundry.teams_collection.size).to eq 1
    end

    it "creates nested records with parent context" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice"
          user "Bob"
        end
      end

      eng = foundry.team("Engineering")
      alice = foundry.user("Alice")
      bob = foundry.user("Bob")

      expect(alice.team).to eq eng
      expect(bob.team).to eq eng
      expect(eng.users.count).to eq 2
    end

    it "builds a full tree" do
      foundry = TestFoundry.new do
        team "Engineering" do
          user "Alice"
          admin "Bob"

          project "API" do
            task "Auth", priority: "high"
            task "Caching"
          end

          project "Frontend" do
            task "Dashboard"
          end
        end
      end

      eng = foundry.team("Engineering")
      alice = foundry.user("Alice")
      bob = foundry.user("Bob")
      api = foundry.project("API")

      aggregate_failures do
        expect(Team.count).to eq 1
        expect(User.count).to eq 2
        expect(Project.count).to eq 2
        expect(Task.count).to eq 3

        expect(alice.team).to eq eng
        expect(bob.role).to eq "admin"

        expect(api.team).to eq eng
        expect(api.tasks.pluck(:name)).to contain_exactly("Auth", "Caching")

        auth = Task.find_by(name: "Auth")
        expect(auth.priority).to eq "high"
        expect(auth.project).to eq api
      end
    end
  end

  describe "#reopen" do
    it "adds more records to an existing foundry" do
      foundry = TestFoundry.new do
        team "Engineering"
      end

      foundry.reopen do
        team "Design"
      end

      expect(Team.count).to eq 2
      expect(foundry.teams_collection.size).to eq 2
    end
  end

  describe "collection tracking" do
    it "tracks all created records across blueprints" do
      foundry = TestFoundry.new do
        team "A" do
          user "Alice"
          project "P1" do
            task "T1"
          end
        end
        team "B" do
          user "Bob"
        end
      end

      expect(foundry.teams_collection.size).to eq 2
      expect(foundry.users_collection.size).to eq 2
      expect(foundry.projects_collection.size).to eq 1
      expect(foundry.tasks_collection.size).to eq 1
    end
  end

  describe "state isolation" do
    it "scopes parent context to nested blocks" do
      foundry = TestFoundry.new do
        team "A" do
          user "Alice"
        end
        team "B" do
          user "Bob"
        end
      end

      alice = foundry.user("Alice")
      bob = foundry.user("Bob")
      team_a = foundry.team("A")
      team_b = foundry.team("B")

      expect(alice.team).to eq team_a
      expect(bob.team).to eq team_b
    end
  end

  describe "preset" do
    before do
      TestFoundry.preset :dev_team do
        team "Dev" do
          user "Lead"
          project "Main" do
            task "Setup"
          end
        end
      end
    end

    it "creates a named factory method on the class" do
      foundry = TestFoundry.dev_team

      expect(foundry).to be_a(TestFoundry)
      expect(Team.find_by(name: "Dev")).to be_present
      expect(User.find_by(name: "Lead")).to be_present
      expect(Project.find_by(name: "Main")).to be_present
      expect(Task.find_by(name: "Setup")).to be_present
    end
  end

  describe "aliases" do
    let(:aliased_foundry_class) do
      Class.new(Foundries::Base) do
        blueprint TeamBlueprint
        blueprint UserBlueprint
        aliases member: :user
      end
    end

    it "delegates aliased methods to the target" do
      foundry = aliased_foundry_class.new do
        team "Engineering" do
          member "Alice"
        end
      end

      alice = foundry.user("Alice")
      expect(alice).to be_a(User)
      expect(alice.name).to eq "Alice"
    end

    it "registers aliases on the class" do
      expect(aliased_foundry_class.aliases).to eq(member: :user)
    end
  end

  describe "inherited registries" do
    let(:parent_foundry_class) do
      Class.new(Foundries::Base) do
        blueprint TeamBlueprint
        blueprint UserBlueprint
        aliases member: :user
        collection :widgets
      end
    end

    let(:child_foundry_class) { Class.new(parent_foundry_class) }

    it "inherits blueprint registry from parent" do
      expect(child_foundry_class.blueprint_registry.keys).to contain_exactly(
        TeamBlueprint, UserBlueprint
      )
    end

    it "inherits extra collections from parent" do
      expect(child_foundry_class.extra_collections).to include("widgets")
    end

    it "inherits aliases from parent" do
      expect(child_foundry_class.aliases).to eq(member: :user)
    end

    it "does not share registry references with parent" do
      child_foundry_class.blueprint ProjectBlueprint

      expect(child_foundry_class.blueprint_registry.keys).to include(ProjectBlueprint)
      expect(parent_foundry_class.blueprint_registry.keys).not_to include(ProjectBlueprint)
    end

    it "can build records using inherited blueprints" do
      foundry = child_foundry_class.new do
        team "Inherited" do
          user "Alice"
        end
      end

      expect(foundry.team("Inherited")).to be_a(Team)
      expect(foundry.user("Alice").team.name).to eq "Inherited"
    end
  end

  describe "#ancestors_for" do
    it "builds a full hierarchy from a path string" do
      foundry = TestFoundry.new do
        ancestors_for :task, "Engineering/API" do
          task "Auth"
        end
      end

      eng = foundry.team("Engineering")
      api = foundry.project("API")
      auth = foundry.task("Auth")

      aggregate_failures do
        expect(eng).to be_a(Team)
        expect(api.team).to eq eng
        expect(auth.project).to eq api
      end
    end

    it "builds from a path array" do
      foundry = TestFoundry.new do
        ancestors_for :task, path_arr: %w[Dev Frontend] do
          task "Layout"
        end
      end

      dev = foundry.team("Dev")
      frontend = foundry.project("Frontend")
      layout = foundry.task("Layout")

      expect(frontend.team).to eq dev
      expect(layout.project).to eq frontend
    end

    it "handles a single-level path (terminal case)" do
      foundry = TestFoundry.new do
        ancestors_for :project, "Sales" do
          project "CRM"
        end
      end

      sales = foundry.team("Sales")
      crm = foundry.project("CRM")

      expect(crm.team).to eq sales
    end
  end

  describe "#blueprint_for" do
    it "finds the blueprint instance by method name" do
      foundry = TestFoundry.new {}
      bp = foundry.blueprint_for(:task)
      expect(bp).to be_a(TaskBlueprint)
    end

    it "raises for unknown method" do
      foundry = TestFoundry.new {}
      expect { foundry.blueprint_for(:unknown) }.to raise_error(/No blueprint/)
    end
  end

  describe "parentless blueprint" do
    let(:parentless_foundry_class) do
      Class.new(Foundries::Base) do
        blueprint ParentlessBlueprint
      end
    end

    it "can use find without error when no parent is declared" do
      foundry = parentless_foundry_class.new do
        parentless_team "Alpha"
        parentless_team "Alpha" # triggers find path
      end

      expect(Team.where(name: "Alpha").count).to eq 1
      expect(foundry.teams_collection.size).to eq 1
    end
  end
end
