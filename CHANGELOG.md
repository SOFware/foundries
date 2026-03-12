# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.3] - Unreleased

## [0.1.2] - 2026-03-12

### Added

- aliases DSL on Base for shorthand method names (377632f)
- lookup_order DSL on Blueprint for ancestor traversal (377632f)
- find_or_create pattern on Blueprint (377632f)
- Tests for inherited registries, parent-scoped find, collection_find_by kwargs, find_or_create, ascending_find, and parent_present? (2d92945)

### Changed

- Collections initialize before blueprints (377632f)
- Fix find parent scoping and collection_find_by kwargs handling (3ebfc3e)
