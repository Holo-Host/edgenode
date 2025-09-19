#!/bin/sh
set -eu

# Create persistent storage directories
mkdir -p /data/holochain/etc /data/holochain/var
chown -R nonroot:nonroot /data

# Ensure parent directories exist for symlinks
mkdir -p /var/local/lib

# Create symlinks for persistent storage
ln -sf /data/holochain/etc /etc/holochain
ln -sf /data/holochain/var /var/local/lib/holochain

# Conductor mode activation
if [ "$CONDUCTOR_MODE" = "true" ]; then
  # Copy conductor config template
  cp /docker/conductor-config.template.yaml /etc/holochain/conductor-config.yaml
  
  # Validate admin port configuration
  if ! grep -q "port: 4444" /etc/holochain/conductor-config.yaml; then
    echo "ERROR: Conductor config must use admin port 4444" >&2
    exit 1
  fi
  
  # Validate empty lair_root configuration
  if ! grep -q "lair_root: \"\"" /etc/holochain/conductor-config.yaml && \
     ! grep -q "lair_root: ''" /etc/holochain/conductor-config.yaml && \
     ! grep -q "lair_root: " /etc/holochain/conductor-config.yaml | grep -v "lair_root: "; then
    echo "ERROR: Conductor config must have empty lair_root" >&2
    exit 1
  fi
fi

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."
exec tail -f /dev/null