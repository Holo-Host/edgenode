#cloud-config
#
# Harvester VM initialisation — rendered by OpenTofu templatefile().
# Template variables ($${...}) are substituted by OpenTofu before the
# cloud-init payload is passed to the Hetzner API.
#
# After this cloud-init completes, run deploy/scripts/bootstrap-harvester.sh
# to generate the agent key, whitelist it in the joining service, and install
# the Unyt hApp. The conductor starts here but the hApp is not yet installed.

packages:
  - docker.io

write_files:
  - path: /usr/local/bin/harvester-init.sh
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

      # Pull and start harvester container
      # The Holochain conductor starts but the Unyt hApp is not yet installed.
      # Run deploy/scripts/bootstrap-harvester.sh after this completes.
      docker pull ${harvester_image}
      docker run -d \
        --name harvester \
        --restart unless-stopped \
        -v "$MOUNT:/data" \
        -p 4444:4444 \
        -p 4445:4445 \
        -e LAIR_PASSWORD="${harvester_lair_password}" \
        -e COLLECTOR_URL="${collector_url}" \
        -e ADMIN_SECRET="${admin_secret}" \
        ${harvester_image}

      echo "Harvester container started. Run bootstrap-harvester.sh to complete setup."

runcmd:
  - /usr/local/bin/harvester-init.sh
