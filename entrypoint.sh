#!/bin/sh
set -eu

# Verified WSL2 detection (case-insensitive match on /proc/version)
if grep -qi microsoft /proc/version; then
  echo "WSL2 environment confirmed - starting TURN server"
  : "${TURN_SECRET:=$(openssl rand -hex 16)}"
  sed "s|\${TURN_SECRET}|$TURN_SECRET|g" /etc/turnserver.conf.template > /etc/turnserver.conf
  turnserver -v &
  until nc -z localhost 3478; do sleep 0.1; done
fi

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."
exec tail -f /dev/null