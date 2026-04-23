#cloud-config
#
# Edgenode VM initialisation — rendered by OpenTofu templatefile().
# Template variables ($${...}) are substituted by OpenTofu before the
# cloud-init payload is passed to the Hetzner API.
# Shell variables in the init script use $VAR (no braces) to avoid conflicts.

packages:
  - docker.io

write_files:
  - path: /usr/local/bin/edgenode-init.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      set -euo pipefail

      DEVICE="/dev/disk/by-id/scsi-0HC_Volume_${volume_id}"
      MOUNT="/data"

      # Wait for the volume to be attached (tofu attaches it after VM creation)
      echo "Waiting for volume device $DEVICE..."
      for i in $(seq 1 12); do
        [ -b "$DEVICE" ] && break
        [ "$i" -eq 12 ] && { echo "ERROR: Volume $DEVICE not found after 60s"; exit 1; }
        sleep 5
      done

      # Format only if no filesystem exists (new volume)
      mkdir -p "$MOUNT"
      blkid "$DEVICE" > /dev/null 2>&1 || mkfs.ext4 -F "$DEVICE"
      mount "$DEVICE" "$MOUNT" 2>/dev/null || true
      grep -q "$DEVICE" /etc/fstab || \
        echo "$DEVICE $MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab

      # Pull and start edgenode container
      docker pull ${edgenode_image}
      docker run -d \
        --name edgenode \
        --restart unless-stopped \
        -v "$MOUNT:/data" \
        -p 80:80 \
        -p 443:443 \
        -p 4444:4444 \
        -e CADDY_DOMAIN="${caddy_domain}" \
        -e H2HC_LINKER_BOOTSTRAP_URL="${linker_bootstrap_url}" \
        -e H2HC_LINKER_ADMIN_SECRET="${linker_admin_secret}" \
        -e LOG_SENDER_ENDPOINT="${log_sender_endpoint}" \
        -e LOG_SENDER_UNYT_PUB_KEY="${log_sender_unyt_pub_key}" \
        -e LAIR_PASSWORD="${lair_password}" \
        ${edgenode_image}

      echo "edgenode container started."

runcmd:
  - /usr/local/bin/edgenode-init.sh
