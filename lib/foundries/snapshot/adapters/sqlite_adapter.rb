# frozen_string_literal: true

module Foundries
  module Snapshot
    module Adapters
      class SqliteAdapter
        def initialize(connection)
          @connection = connection
        end

        def table_names
          @connection.tables - %w[schema_migrations ar_internal_metadata]
        end

        def empty?(table_name)
          count(table_name) == 0
        end

        def count(table_name)
          @connection.select_value("SELECT COUNT(*) FROM #{quoted(table_name)}")
        end

        def capture(table_name, io)
          rows = @connection.select_all("SELECT * FROM #{quoted(table_name)}")
          rows.each do |row|
            values = row.values.map { |v| @connection.quote(v) }.join(", ")
            columns = row.keys.map { |k| @connection.quote_column_name(k) }.join(", ")
            io.puts "INSERT INTO #{quoted(table_name)} (#{columns}) VALUES (#{values});"
          end
        end

        def restore(table_name, io)
          io.each_line do |line|
            @connection.execute(line.strip) unless line.strip.empty?
          end
        end

        def disable_referential_integrity
          @connection.execute("PRAGMA defer_foreign_keys = ON")
          yield
        ensure
          @connection.execute("PRAGMA defer_foreign_keys = OFF")
        end

        def reset_sequence(table_name)
          # SQLite auto-increments handle this naturally
        end

        private

        def quoted(table_name)
          @connection.quote_table_name(table_name)
        end
      end
    end
  end
end
