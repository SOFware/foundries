# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "snapshot/fingerprint"
require_relative "snapshot/adapter"
require_relative "snapshot/adapters/postgres_adapter"
require_relative "snapshot/adapters/sqlite_adapter"
require_relative "snapshot/store"

module Foundries
  module Snapshot
    class << self
      attr_writer :storage_path, :connection, :enabled, :source_paths

      # Keep the lock outside the replaceable cache directory. Readers and
      # publishers must hold it for the entire filesystem operation.
      def with_lock(name, storage_path: self.storage_path)
        FileUtils.mkdir_p(storage_path)
        lock_path = File.join(storage_path, "#{name}.lock")
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN)
        end
      end

      def storage_path
        @storage_path || "tmp/foundries"
      end

      def connection
        @connection || ActiveRecord::Base.connection
      end

      def source_paths
        @source_paths || []
      end

      def enabled?
        return @enabled unless @enabled.nil?
        ENV["FOUNDRIES_CACHE"] == "1"
      end

      def adapter
        @adapter ||= Adapter.for(connection)
      end

      def reset!
        @adapter = nil
        @source_paths = nil
      end
    end
  end
end
