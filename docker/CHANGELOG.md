# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-alpha1] - 2026-03-13

### Added
- s6-overlay v3.2.0.2 process supervisor replacing tini; conductor, log-sender, and logrotate-cron run as supervised longrun services
- `@theweave/wdocker` CLI included in the container image for Weave hApp management
- Iroh networking support for Holochain >= 0.6.1 via `happ_config_file` and new conductor config template
- Multi-arch builds (amd64/arm64) with arch-specific binary downloads for log-sender and s6-overlay

### Changed
- Consolidated to a single `edgenode` image based on Holochain 0.6.1-rc.3 with log-sender v0.1.5
- Bumped `happ_config_file` to v0.3.0 with iroh as default networking and `priceSheetHash` field
- Updated kando webhapp fixture to v0.17.1 for HC 0.6.1 compatibility
- Expanded quickstart documentation into a step-by-step walkthrough

### Fixed
- Added `log-sender.log` to logrotate config to prevent unbounded log growth
- Stop log-sender service before `register-dna` to avoid file lock panic
- Added required `signal_url` and `relay_url` fields to HC 0.6.1 conductor config
- `happ_tool` now handles `--help` flag and missing arguments gracefully
- Rewrote integration data pipeline tests to match actual log-sender behaviour
