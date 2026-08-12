# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.5] - 2026-08-12

### Changed

- Development dependencies are locked (1129826)

### Fixed

- Snapshot no longer caches a partial tree when a preset writes to a table that already held rows (2e9f863)
- Lint under standard 1.56.0 (52be9eb)
- Releases write a SHA512 checksum again (813a2ae)

## [0.1.4] - 2026-03-16

### Added

- Recording module to analyze FactoryBot usage and suggest preset candidates (a294324)
- parallel_tests support for Recording with per-worker output and merge rake task (8e59deb)

### Changed

- README now covers Recording feature and parallel_tests support (69fa45b)
