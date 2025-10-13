# Testing Strategy

This document outlines the testing strategy for the `edgenode` Docker images.

## Framework

The testing framework is built using [Bats](https://github.com/bats-core/bats-core), a TAP-compliant testing framework for Bash. It provides a simple way to write tests for shell scripts and command-line applications.

## Test Matrix

The testing strategy is designed to be able to test multiple Docker images. The `run_tests.sh` script accepts a Docker image name as an argument. If no argument is provided, it will default to building and testing a local image named `local-edgenode`.

To run the tests against a specific image, use the following command:

```bash
./run_tests.sh <image-name>
```

For example, to test the `holochain/holochain-go-pion` image, you would run:

```bash
./run_tests.sh holochain/holochain-go-pion
```

## Test Cases

The test cases are located in the `tests` directory. Each file in this directory represents a test suite. The following test suites are currently implemented:

- `startup.bats`: Verifies that the Holochain conductor starts successfully.
- `process.bats`: Verifies that the `holochain` process runs as the `nonroot` user.
- `persistence.bats`: Verifies that data written to the `/data` volume persists across container restarts.
- `happ.bats`: Verifies that a sample hApp can be installed successfully.

## Adding New Tests

To add a new test, create a new `.bats` file in the `tests` directory. The `run_tests.sh` script will automatically run any `.bats` files in this directory.

## CI Integration

The `run_tests.sh` script is designed to be easily integrated into a CI/CD pipeline. It will exit with a non-zero status code if any of the tests fail. The structured output from Bats will make it easy to diagnose failures in the CI logs.