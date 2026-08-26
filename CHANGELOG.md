# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.7] - Unreleased

## [0.1.6] - 2026-08-25

### Fixed

- Snapshot files are read and written in binary, so captured data with non-ASCII bytes round-trips (6a7d3a3)
- Restoring a snapshot no longer rewinds a sequence below its current value (df66836)
