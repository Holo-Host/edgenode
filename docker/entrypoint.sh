#!/bin/sh
set -eu

# Create persistent storage directories
mkdir -p /data/holochain/etc /data/holochain/var /data/logs
touch /data/logs/startup.log
chown -R nonroot:nonroot /data

# Fix ownership for copied files in nonroot home
chown -R nonroot:nonroot /home/nonroot
echo "Chowned /home/nonroot contents for copied files" | tee -a /data/logs/startup.log || echo "Warning: Failed to log chown" >&2

# Ensure parent directories exist for symlinks
mkdir -p /var/local/lib

# Create symlinks for persistent storage
ln -sf /data/holochain/etc /etc/holochain
ln -sf /data/holochain/var /var/local/lib/holochain
mkdir -p /data/holochain/var/ks /data/holochain/tmp /data/holochain/var/tmp
chown -R nonroot:nonroot /data/holochain
chmod 700 /data/holochain/var/ks
chmod 755 /data/holochain/tmp /data/holochain/var/tmp

# Conductor mode activation
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

# Start background logrotate every 24 hours
while true; do
  logrotate /etc/logrotate.d/holochain.conf
  sleep 86400
done &

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."

if [ "${CONDUCTOR_MODE:-}" = "false" ]; then
  exec tini -s -- tail -f /dev/null
else
  exec tini -s -- gosu nonroot sh -c 'echo "Starting conductor as nonroot" >> /data/logs/startup.log && yes | holochain --piped --config-path /etc/holochain/conductor-config.yaml' 2>&1 | tee -a /data/logs/holochain.log
fi