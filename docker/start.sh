#!/bin/sh
set -eu

# Create persistent storage directories
chown -R nonroot:nonroot /data
mkdir -p /data/holochain/etc /data/holochain/var /data/logs /data/log-sender
touch /data/logs/startup.log

# Log all environment variables to the startup log
printenv > /data/logs/startup.log

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

# Ensure /tmp is writable and executable for nonroot
chmod 1777 /tmp

# Start supervisord as nonroot
gosu nonroot supervisord -c /etc/supervisor/conf.d/supervisord.conf &

# Wait for Holochain conductor to start
echo "Waiting for Holochain conductor to start..."
while ! pgrep -x "holochain" > /dev/null; do
    sleep 1
done
echo "Holochain conductor started."

# Define the path for the log-sender config file
LOG_SENDER_CONFIG_FILE="/etc/log-sender/config.json"

# Check if the log-sender config file exists
if [ ! -f "$LOG_SENDER_CONFIG_FILE" ]; then
  # Log the value of UNYT_PUB_KEY before initializing log-sender
  echo "UNYT_PUB_KEY is: $UNYT_PUB_KEY" >> /data/logs/startup.log

  # Prompt the user for their unyt-pub-key
  echo "Please enter your Unyt pub key:"
  read unyt_pub_key

  # Initialize log-sender
  log-sender init \
    --config-file "$LOG_SENDER_CONFIG_FILE" \
    --endpoint "https://log-collector.holo.host" \
    --unyt-pub-key "$unyt_pub_key" \
    --report-interval-seconds 300 \
    --conductor-config-path /etc/holochain/conductor-config.yaml
fi

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."

# Bring supervisord to the foreground
fg