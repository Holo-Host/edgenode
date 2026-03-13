#!/bin/sh
set -eu

# Create persistent storage directories
mkdir -p /data/holochain/etc /data/holochain/var /data/logs /data/log-sender
touch /data/logs/startup.log

# Fix ownership for copied files in nonroot home
chown -R nonroot:nonroot /home/nonroot
echo "Chowned /home/nonroot contents" >> /data/logs/startup.log 2>/dev/null || true

# Ensure parent directories exist for symlinks
mkdir -p /var/local/lib

# Create symlinks for persistent storage
ln -sfn /data/holochain/etc /etc/holochain
ln -sfn /data/log-sender /etc/log-sender
ln -sfn /data/holochain/var /var/local/lib/holochain
mkdir -p /data/holochain/var/ks /data/holochain/tmp /data/holochain/var/tmp
chown -R nonroot:nonroot /data
chown -R nonroot:nonroot /data/holochain
chmod 700 /data/holochain/var/ks
chmod 755 /data/holochain/tmp /data/holochain/var/tmp

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

echo "Setup complete." >> /data/logs/startup.log
