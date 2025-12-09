#!/bin/sh
set -eu

# Create persistent storage directories
mkdir -p /data/holochain/etc /data/holochain/var /data/logs /data/log-sender
touch /data/logs/startup.log

# Fix ownership for copied files in nonroot home
chown -R nonroot:nonroot /home/nonroot
echo "Chowned /home/nonroot contents for copied files" | tee -a /data/logs/startup.log || echo "Warning: Failed to log chown" >&2

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

# Background process supervisor for log-sender
# Ensures log-sender service is running if configured, providing robust supervision
monitor_log_sender() {
  while true; do
    if [ -f /etc/log-sender/config.json ]; then
      # Check if already running (e.g. started by happ_tool or previous iteration)
      if ! pgrep -f "log-sender service" > /dev/null; then
        echo "Starting log-sender service (supervised)..." >> /data/logs/startup.log
        # Run in foreground of this subshell, logging output
        # If it crashes, the loop will catch it after it exits
        if gosu nonroot sh -c "log-sender service --config-file /etc/log-sender/config.json >> /data/logs/log-sender.log 2>&1"; then
           echo "log-sender service exited gracefully." >> /data/logs/startup.log
        else
           echo "log-sender service crashed. Restarting in 5s..." >> /data/logs/startup.log
           sleep 5
        fi
      fi
    fi
    sleep 10
  done
}

# Start the monitor in background
monitor_log_sender &

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."

if [ "${CONDUCTOR_MODE:-}" = "false" ]; then
  exec tini -s -- tail -f /dev/null
else
#  exec tini -s -- tail -f /dev/null
  exec tini -s -v -- gosu nonroot sh -c 'echo "Starting conductor as nonroot" >> /data/logs/startup.log && yes | holochain --piped --config-path /etc/holochain/conductor-config.yaml' 2>&1 | tee -a /data/logs/holochain.log
fi
