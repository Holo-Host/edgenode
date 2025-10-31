#!/bin/bash

# Set up environment variables for log_tool tests
# Only set if not already set (allow tests to override)
export UNYT_PUB_KEY="${UNYT_PUB_KEY:-uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO}"
export LOG_SENDER_UNYT_PUB_KEY="${LOG_SENDER_UNYT_PUB_KEY:-uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO}"
export LOG_SENDER_REPORT_INTERVAL_SECONDS="${LOG_SENDER_REPORT_INTERVAL_SECONDS:-60}"
export LOG_SENDER_LOG_PATH="${LOG_SENDER_LOG_PATH:-/data/logs}"
export LOG_SENDER_ENDPOINT="${LOG_SENDER_ENDPOINT:-http://log-collector:8787}"
export RUST_LOG="${RUST_LOG:-info}"

# Execute the command passed as arguments
exec "$@"
