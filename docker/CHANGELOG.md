# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `edgenode-harvester` container variant (`Dockerfile.harvester`) — bundles `log-harvester` (unytco/log-harvester) instead of `log-sender` for Unyt invoice aggregation
- `s6-overlay-harvester/` service tree: self-contained s6 services for the harvester variant (`conductor`, `log-harvester`, `logrotate-cron`, `setup`)
- `log-harvester` s6 longrun service: waits for conductor, installs `unyt.happ`, attaches app websocket on port 4445, initializes/refreshes harvester config, runs harvester loop
- `unyt.happ` baked into the harvester image from latest `unytco/unyt-sandbox` release; pinnable via `UNYT_HAPP_VERSION` build arg
- `Dockerfile.log-collector` — Dockerfile for the `unytco/log-collector` Cloudflare Worker service; applies D1 schema on startup and passes `ADMIN_SECRET` via wrangler `--var`
- `run_harvester_tests.sh` — dedicated test runner for the harvester variant; auto-clones `log-harvester-src` if not present, starts all three services, waits for readiness
- Harvester BATS test suite: `harvester_startup.bats`, `harvester_process.bats`, `harvester_integration.bats`, `harvester_e2e.bats`
- `LOG_HARVESTER_QUICKSTART.md` quickstart guide for the harvester variant
- CI `build-and-push-harvester-image` job in release workflow publishing `ghcr.io/holo-host/edgenode-harvester`
- CI PR checks now build and test both `edgenode` and `edgenode-harvester` images with GHA layer caching

### Changed
- `run_tests_multi.sh` runs each `.bats` file individually with a log-collector health-check between files, preventing wrangler crash cascades from affecting subsequent test files
- `docker-compose.yml`: log-collector service gets `restart: unless-stopped` so Docker auto-recovers after wrangler dev crashes under concurrent D1 load
- Upgraded both images to Holochain 0.7.0. New template `conductor-config-0.7.0.template.yaml` drops `signal_url` (0.7 is iroh-only and rejects unknown fields) and points `relay_url` at the bootstrap host, which serves the iroh relay in 0.7
- `happ_tool` and the harvester s6 script now use `hc client call -p <port>` / `hc client zome-call*`; `hc sandbox call` no longer exists in hc 0.7
- Test fixtures switched from kando v0.17.1 / volla relay to ziptest v0.6.0-dev.0 (0.7-built); `multi_install.bats` re-enabled using ziptest's `create_thing` as an init zome call
- Harvester builds log-harvester from its `feat/adapt-to-holo-hosting-agreement` branch: `LANE_DEFINITION_IDS` is now required, the app websocket is attached by the s6 script, and the harvester agent key is logged at startup via `whoami`
- `unyt.happ` in the harvester image pinned to v0.104.0 instead of `releases/latest`
- `@theweave/wdocker` bumped to 0.16.0-dev.4 (Holochain 0.7 client)
- `happ_config_file` 0.4.0: iroh-only templates, `--webrtc` removed
- `log-sender` bumped to v0.1.6, which meters the `dht-*.db` files of Holochain 0.7's flat `databases/` layout and no longer aborts report shipping when the db-size check fails

### Breaking
- No data migration from 0.6.x. Existing `/data` volumes must be reset before starting a 0.7 image (keystore may be kept) — see [Upgrading to Holochain 0.7](../deploy/DEPLOYMENT.md#upgrading-to-holochain-07)
- hApps built for Holochain 0.6 cannot be installed; the DNA hash scheme changed and 0.7 networks do not interoperate with 0.6 networks
- Harvester deployments must set `LANE_DEFINITION_IDS`

### Known limitations
- h2hc-linker v0.1.2 is built against Holochain 0.6 crates; the linker service is not expected to work against the 0.7 conductor until h2hc-linker v0.2.0 is released and the image is rebuilt with `LINKER_VERSION=0.2.0`.

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
