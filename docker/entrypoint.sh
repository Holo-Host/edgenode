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

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."
exec tail -f /dev/null