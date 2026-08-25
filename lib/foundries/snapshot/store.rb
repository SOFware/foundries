# frozen_string_literal: true

require "fileutils"

module Foundries
  module Snapshot
    class Store
      def initialize(preset_name, adapter: Snapshot.adapter,
        storage_path: Snapshot.storage_path,
        source_paths: Snapshot.source_paths)
        @preset_name = preset_name.to_s
        @adapter = adapter
        @storage_path = storage_path
        @fingerprint = Fingerprint.new(
          adapter.instance_variable_get(:@connection),
          source_paths: source_paths
        )
      end

      def cached?
        cache_dir.exist? &&
          cache_dir.join(".fingerprint").exist? &&
          cache_dir.join(".fingerprint").read.strip == @fingerprint.current
      end

      # Record which tables are empty before the preset block runs.
      # Only these tables will be captured after the block completes.
      #
      # The already-populated tables are counted too, so #capture can tell
      # whether the preset wrote into one of them. A preset that only updates
      # existing rows leaves the count unchanged and slips past this check;
      # presets insert, so the count is a good enough signal.
      def record_empty_tables
        @capturable_tables = []
        @preexisting_counts = {}

        @adapter.table_names.each do |table|
          if @adapter.empty?(table)
            @capturable_tables << table
          else
            @preexisting_counts[table] = @adapter.count(table)
          end
        end
      end

      def capture
        spoiled = spoiled_tables
        unless spoiled.empty?
          warn "[Foundries] Not caching preset :#{@preset_name} — it wrote to " \
            "#{spoiled.join(", ")}, which already held rows when it ran. " \
            "Only tables the preset fills from empty can be snapshotted, so " \
            "caching this would restore an incomplete tree."
          return
        end

        tables = @capturable_tables || @adapter.table_names

        tmp_dir = Pathname.new("#{cache_dir}.#{$$}.tmp")
        tmp_dir.mkpath

        tables.each do |table|
          tmp_dir.join("#{table}.dat").open("wb") do |f|
            @adapter.capture(table, f)
          end
        end

        tmp_dir.join(".fingerprint").write(@fingerprint.current)

        # Atomic swap
        FileUtils.rm_rf(cache_dir) if cache_dir.exist?
        FileUtils.mv(tmp_dir, cache_dir)
      end

      def restore
        @adapter.disable_referential_integrity do
          cache_dir.glob("*.dat").each do |file|
            next unless file.size > 0

            table = file.basename(".dat").to_s
            file.open("rb") do |f|
              @adapter.restore(table, f)
            end
            @adapter.reset_sequence(table)
          end
        end
      end

      private

      # Pre-populated tables whose row count moved while the preset ran. Their
      # new rows can't be told apart from the ones that were already there, so
      # the snapshot would silently omit them.
      def spoiled_tables
        return [] unless @preexisting_counts

        @preexisting_counts.filter_map do |table, count|
          table unless @adapter.count(table) == count
        end
      end

      def cache_dir
        @cache_dir ||= Pathname.new(@storage_path).join(@preset_name)
      end
    end
  end
end
