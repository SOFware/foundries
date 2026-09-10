# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Foundries::Snapshot, ".with_lock" do
  it "excludes another process and releases the lock after an exception" do
    Dir.mktmpdir("foundries-lock") do |path|
      locked = proc do
        reader, writer = IO.pipe
        pid = fork do
          reader.close
          File.open(File.join(path, "example.lock"), File::RDWR) do |file|
            writer.write(file.flock(File::LOCK_EX | File::LOCK_NB) ? "available" : "locked")
          end
          writer.close
          exit! 0
        end
        writer.close
        result = reader.read
        reader.close
        Process.wait(pid)
        result
      end

      expect do
        described_class.with_lock(:example, storage_path: path) do
          expect(locked.call).to eq("locked")
          raise "failed capture"
        end
      end.to raise_error("failed capture")
      expect(locked.call).to eq("available")
    end
  end
end
