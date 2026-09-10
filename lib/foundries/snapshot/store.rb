# frozen_string_literal: true

require "fileutils"
require "tmpdir"

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
        with_lock { valid_cache? }
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

        FileUtils.mkdir_p(@storage_path)
        tmp_dir = Pathname.new(Dir.mktmpdir("#{@preset_name}.", @storage_path))

        tables.each do |table|
          tmp_dir.join("#{table}.dat").open("wb") do |f|
            @adapter.capture(table, f)
          end
        end

        tmp_dir.join(".tables").write(tables.join("\n"))
        tmp_dir.join(".fingerprint").write(@fingerprint.current)

        with_lock do
          FileUtils.rm_rf(cache_dir)
          FileUtils.mv(tmp_dir, cache_dir)
        end
      ensure
        FileUtils.rm_rf(tmp_dir) if tmp_dir
      end

      def restore
        with_lock do
          raise "Invalid or incomplete snapshot: #{@preset_name}" unless valid_cache?

          @adapter.disable_referential_integrity do
            captured_tables.each do |table|
              file = cache_dir.join("#{table}.dat")
              next unless file.size > 0

              file.open("rb") { |io| @adapter.restore(table, io) }
              @adapter.reset_sequence(table)
            end
          end
        end
      end

      private

      def with_lock(&block)
        Snapshot.with_lock(@preset_name, storage_path: @storage_path, &block)
      end

      def captured_tables
        cache_dir.join(".tables").read.lines.map(&:chomp)
      end

      def valid_cache?
        stamp = cache_dir.join(".fingerprint")
        stamp.file? && stamp.read.strip == @fingerprint.current &&
          cache_dir.join(".tables").file? &&
          captured_tables.all? { |table| cache_dir.join("#{table}.dat").file? }
      end

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
