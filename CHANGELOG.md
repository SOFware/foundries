# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.1] - 2026-03-06

### Added

- Blueprint base class with collection tracking, parent scoping, and factory_bot integration (0002336)
- Snapshot caching system with Postgres and SQLite adapters for test suite acceleration (0002336)
- Source file content hashing in snapshot fingerprint for automatic cache invalidation (cfb348d)

### Changed

- Snapshot caching is opt-in via ARMATURE_CACHE=1 environment variable (0002336)
- Similarity detection only warns on identical structure, not containment (a5bdf25)

### Fixed

- Parentless blueprints no longer raise NameError when find calls same_parent? (cfb348d)
- Snapshot-cached presets no longer produce false similarity warnings (a5bdf25)

## [0.1.0] - 2026-02-25
