# Foundries

Declarative trees of related records using factory_bot.

Foundries composes factory_bot factories into **blueprints** that know how to create, find, and relate records. You register blueprints with a **base** class, then build entire object graphs with a nested DSL:

```ruby
TestFoundry.new do
  team "Engineering" do
    user "Alice"
    admin "Bob"

    project "API" do
      task "Auth", priority: "high"
      task "Caching"
    end
  end
end
```

Each method call creates a record (or finds an existing one), and nesting establishes parent-child context automatically. No manual foreign key wiring.

## Installation

```ruby
gem "foundries"
```

## Usage

### Blueprints

A blueprint wraps a single factory_bot factory and declares how it participates in the tree:

```ruby
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
```

#### Blueprint DSL

| Method | Purpose |
|--------|---------|
| `handles :method_name` | Methods this blueprint exposes on the foundry |
| `factory :name` | Which factory_bot factory to use (inferred from class name if omitted) |
| `collection :name` | Collection name for tracking created records |
| `parent :name` | How to find the parent record (`:none`, `:self`, or a method on `current`) |
| `parent_key :foreign_key` | Foreign key column linking to the parent |
| `permitted_attrs %i[...]` | Attributes allowed through to factory_bot |
| `nested_attrs key => [...]` | For `accepts_nested_attributes_for` |

#### Finding records

Blueprints automatically prevent duplicates. `find(name)` checks the in-memory collection first, then falls back to the database. `find_by(criteria)` works with arbitrary attributes.

#### Parent context

When a block is passed to a blueprint method, `update_state_for_block` saves the current context, sets the new record as `current.resource`, executes the block, then restores the previous context. Child blueprints read their parent from `current`:

```ruby
class UserBlueprint < Foundries::Blueprint
  handles :user
  parent :team         # reads current.team
  parent_key :team_id  # sets team_id on created records
  # ...
end
```

### Base (the foundry)

Register blueprints and optional extra collections:

```ruby
class TestFoundry < Foundries::Base
  blueprint TeamBlueprint
  blueprint UserBlueprint
  blueprint ProjectBlueprint
  blueprint TaskBlueprint

  collection :tags  # extra collection not from a blueprint
end
```

The base class:

- Instantiates each blueprint and delegates its `handles` methods
- Initializes a `Set` for each collection (e.g. `teams_collection`)
- Tracks `current` state so nested blocks know their parent context
- Deduplicates records via each blueprint's `find` logic

### Presets

Presets are named class methods that build a preconfigured foundry:

```ruby
class TestFoundry < Foundries::Base
  # ...

  preset :dev_team do
    team "Engineering" do
      user "Alice"
      project "Main" do
        task "Setup"
      end
    end
  end
end

# In a test:
let(:foundry) { TestFoundry.dev_team }
```

### Reopening

Add more records to an existing foundry:

```ruby
foundry = TestFoundry.dev_team
foundry.reopen do
  team "Design" do
    user "Carol"
  end
end
```

### Building from existing objects

Start from records already in the database:

```ruby
foundry = TestFoundry.new
foundry.from(existing_team) do
  user "New hire"
end
```

### Lifecycle hooks

Override `setup` and `teardown` in your base subclass for pre/post processing:

```ruby
class TestFoundry < Foundries::Base
  private

  def setup
    @pending_rules = []
  end

  def teardown
    process_pending_rules
  end
end
```

## Snapshot Caching

When using ActiveRecord, Foundries can snapshot preset data to disk and restore it instead of re-running factories. This is useful for speeding up test suites where the same preset is called many times.

Enable with an environment variable:

```
FOUNDRIES_CACHE=1 bundle exec rspec
```

Or configure directly:

```ruby
Foundries::Snapshot.enabled = true
Foundries::Snapshot.storage_path = "tmp/foundries"  # default
Foundries::Snapshot.source_paths = [
  "lib/blueprints/**/*.rb",
  "lib/test_foundry.rb"
]
```

Snapshots are invalidated automatically when the schema version changes or when source files listed in `source_paths` are modified. Data is captured using database-native copy operations (PostgreSQL `COPY`, SQLite `INSERT`) and restored with referential integrity checks temporarily disabled.

## Similarity Detection

Foundries can detect when presets have overlapping structure, highlighting consolidation opportunities. When enabled, it records the normalized blueprint call tree of each preset and compares against previously seen presets.

Enable with an environment variable:

```
FOUNDRIES_SIMILARITY=1 bundle exec rspec
```

Or configure directly:

```ruby
Foundries::Similarity.enabled = true
```

When two presets share identical structure or one is structurally contained within another, a warning is printed to stderr:

```
[Foundries] Preset :basic and :extended have identical structure (team > [project > [task], user])
[Foundries] Preset :simple is structurally contained within :complex
```

Each unique pair is warned once per process. The detection normalizes trees by deduplicating sibling nodes (keeping the richest subtree), collapsing pass-through chains, and sorting alphabetically. This means presets that build the same *shape* of data are detected regardless of the specific names or attribute values used.

## Factory Usage Recording

If you're migrating an existing test suite to Foundries, the recording feature can help you discover which factory call patterns appear most often — and would make good preset candidates.

Add to your `spec_helper.rb`:

```ruby
require "foundries/recording"
```

Then run your suite with the environment variable:

```
FOUNDRIES_RECORD=1 bundle exec rspec
```

After the suite finishes, a summary is printed to stdout:

```
[Foundries] Recording complete. 482 tests, 3841 factory creates.
[Foundries] Top preset candidates:
  1. team > [project > [task], user] (34 tests, score: 102)
  2. team > [user] (28 tests, score: 56)
  3. team > [project > [task > [comment]], user] (12 tests, score: 60)
[Foundries] Full report: tmp/foundries/recording.json
```

The full JSON report at `tmp/foundries/recording.json` includes per-test breakdowns and all candidates with the test names that use each pattern.

### Parallel tests

Recording works with [parallel_tests](https://github.com/grosser/parallel_tests). Each worker writes its own file, then a rake task merges the results:

```
FOUNDRIES_RECORD=1 bundle exec parallel_rspec
rake foundries:recording:merge
```

To use the rake task, add to your `Rakefile`:

```ruby
require "foundries/recording/rake_task"
Foundries::Recording::RakeTask.install
```

## Requirements

- Ruby >= 4.0
- factory_bot >= 6.0
- ActiveRecord (optional, for snapshot caching)

## License

MIT

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rake` to run the tests.

To install this gem onto your local machine, run bundle exec rake install.

This project is managed with [Reissue](https://github.com/SOFware/reissue).

Releases are automated via the [shared release workflow](https://github.com/SOFware/reissue/blob/main/.github/workflows/SHARED_WORKFLOW_README.md). Trigger a release by running the "Release gem to RubyGems.org" workflow from the Actions tab.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/SOFware/foundries.
