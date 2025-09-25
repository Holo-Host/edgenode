#!/bin/sh
set -eu

# Create persistent storage directories
mkdir -p /data/holochain/etc /data/holochain/var /data/logs
chown -R nonroot:nonroot /data

# Ensure parent directories exist for symlinks
mkdir -p /var/local/lib

# Create symlinks for persistent storage
ln -sf /data/holochain/etc /etc/holochain
ln -sf /data/holochain/var /var/local/lib/holochain
chown -R nonroot:nonroot /data/holochain

# Conductor mode activation
if [ "$CONDUCTOR_MODE" = "true" ]; then
  mkdir -p /etc/holochain
  # Copy conductor config template
  cp /usr/local/share/holochain/conductor-config.template.yaml /etc/holochain/conductor-config.yaml
  
  # Validate admin port configuration
  if ! grep -q "port: 4444" /etc/holochain/conductor-config.yaml; then
    echo "ERROR: Conductor config must use admin port 4444" >&2
    exit 1
  fi
  
  # Validate keystore configuration for lair_server_in_proc
  if ! grep -q "keystore:" /etc/holochain/conductor-config.yaml || ! grep -q "type: lair_server_in_proc" /etc/holochain/conductor-config.yaml; then
    echo "ERROR: Conductor config must have keystore with type: lair_server_in_proc" >&2
    exit 1
  fi
fi

# Start background logrotate every 24 hours
while true; do
  logrotate /etc/logrotate.d/holochain.conf
  sleep 86400
done &

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."

if [ "$CONDUCTOR_MODE" = "true" ]; then
  exec tini -- gosu nonroot holochain --config-path /etc/holochain/conductor-config.yaml > /data/logs/holochain.log 2>&1
else
  exec tini -- tail -f /dev/null
fi