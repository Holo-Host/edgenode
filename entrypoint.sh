#!/bin/sh

# Display Holochain and hc version information
echo "=== Holochain Version Information ==="
holochain --version
hc --version
echo "======================================"

# Keep the container running for interactive access
echo "Container is running. Use 'docker exec -it <container_name> /bin/sh' to access interactive shell."
exec tail -f /dev/null