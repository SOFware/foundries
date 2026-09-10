# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.7] - 2026-09-10

### Added

- Foundries::Snapshot.with_lock for application-owned snapshot caches (fe91e06)

### Fixed

- Serialize snapshot publication and restoration across workers (fe91e06)
- Reject incomplete snapshots before restoring rows (fe91e06)
- Clean staging directories after failed snapshot captures (fe91e06)
- Restore parent context when a nested blueprint block raises (7fd6e4b)

## [0.1.6] - 2026-08-25

### Fixed

- Snapshot files are read and written in binary, so captured data with non-ASCII bytes round-trips (6a7d3a3)
- Restoring a snapshot no longer rewinds a sequence below its current value (df66836)
