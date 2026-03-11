# Testing Strategy

This document outlines the testing strategy for the `edgenode` Docker image.

## Framework

The testing framework is built using [Bats](https://github.com/bats-core/bats-core), a TAP-compliant testing framework for Bash.

## Running Tests

To run tests against the local build:

```bash
./run_tests_multi.sh
```

To run tests against a specific image:

```bash
./run_tests_multi.sh ghcr.io/holo-host/edgenode:v1.2.3
```

## Test Cases

The test cases are in the `tests/` directory:

- `startup.bats`: Verifies the Holochain conductor starts successfully.
- `process.bats`: Verifies `holochain` runs as the `nonroot` user.
- `persistence.bats`: Verifies data written to `/data` persists across container restarts.
- `happ.bats`: Verifies a hApp can be installed via `install_happ`.
- `webhapp.bats`: Verifies a `.webhapp` file can be downloaded, extracted, and installed.
- `multi_install.bats`: Multi-happ installation tests.
- `log_tool.bats`: Verifies `log-sender` init, service, and config behaviour.
- `log_sender_e2e.bats`: End-to-end log-sender → log-collector pipeline tests.
- `log_sender_debug.bats`: Debug log-sender service with test JSONL data.
- `integration_data_pipeline.bats`: Integration tests for the full data pipeline.

## Adding New Tests

Create a new `.bats` file in the `tests/` directory. It will be picked up automatically by `run_tests_multi.sh`.

## CI Integration

`run_tests_multi.sh` exits with a non-zero status if any test fails. Tests run against the amd64 build before the multi-platform push in the release workflow.
