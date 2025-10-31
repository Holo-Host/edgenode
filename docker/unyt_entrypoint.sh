#!/bin/sh
set -eu

# Ensure /tmp is writable and executable for nonroot
chmod 1777 /tmp

# Ensure setup_test_env.sh is executable
if [ -f /tmp/setup_test_env.sh ]; then
  chmod +x /tmp/setup_test_env.sh
fi

# Execute the original entrypoint
exec /usr/local/bin/entrypoint.sh
