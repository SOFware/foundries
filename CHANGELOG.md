# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.6] - 2026-08-25

### Fixed

- Snapshot files are read and written in binary, so captured data with non-ASCII bytes round-trips (6a7d3a3)
- Restoring a snapshot no longer rewinds a sequence below its current value (df66836)

## [0.1.5] - 2026-08-12

### Changed

- Development dependencies are locked (1129826)

### Fixed

- Snapshot no longer caches a partial tree when a preset writes to a table that already held rows (2e9f863)
- Lint under standard 1.56.0 (52be9eb)
- Releases write a SHA512 checksum again (813a2ae)
