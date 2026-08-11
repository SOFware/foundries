# frozen_string_literal: true

module Foundries
  module Snapshot
    module Adapters
      class PostgresAdapter
        def initialize(connection)
          @connection = connection
        end

        def table_names
          @connection.tables - %w[schema_migrations ar_internal_metadata]
        end

        def empty?(table_name)
          @connection.select_value("SELECT NOT EXISTS (SELECT 1 FROM #{quoted(table_name)})")
        end

        def count(table_name)
          @connection.select_value("SELECT COUNT(*) FROM #{quoted(table_name)}")
        end

        def capture(table_name, io)
          raw = @connection.raw_connection
          raw.copy_data("COPY #{quoted(table_name)} TO STDOUT") do
            while (row = raw.get_copy_data)
              io.write(row)
            end
          end
        end

        def restore(table_name, io)
          raw = @connection.raw_connection
          raw.copy_data("COPY #{quoted(table_name)} FROM STDIN") do
            io.each_line do |line|
              raw.put_copy_data(line)
            end
          end
        end

        def disable_referential_integrity
          @connection.execute("SET session_replication_role = replica")
          yield
        ensure
          @connection.execute("SET session_replication_role = DEFAULT")
        end

        def reset_sequence(table_name)
          pk = @connection.primary_key(table_name)
          return unless pk

          # Check for sequence first — UUID PKs have no sequence
          seq = @connection.select_value(
            "SELECT pg_get_serial_sequence(#{@connection.quote(table_name)}, #{@connection.quote(pk)})"
          )
          return unless seq

          max_id = @connection.select_value(
            "SELECT COALESCE(MAX(#{@connection.quote_column_name(pk)}), 0) FROM #{quoted(table_name)}"
          )
          @connection.execute("SELECT setval(#{@connection.quote(seq)}, #{max_id})")
        end

        private

        def quoted(table_name)
          @connection.quote_table_name(table_name)
        end
      end
    end
  end
end
