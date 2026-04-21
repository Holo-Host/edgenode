# Per-deployment configuration — copy to <org>-<env>.tfvars and fill in.
# Secrets are passed via TF_VAR_* environment variables (see deploy/.env.example).
#
# Example:
#   cp deploy/tofu/example.tfvars deploy/tofu/acme-staging.tfvars
#   $EDITOR deploy/tofu/acme-staging.tfvars

project_name          = "<org>-<env>"         # e.g. acme-staging, junto-prod
hetzner_location      = "nbg1"                # nbg1, fsn1, hel1, ash, hil
domain                = "<org>.example.com"   # domain in the org's Cloudflare zone

edgenode_count        = 2
edgenode_server_type  = "cx22"
harvester_server_type = "cx22"

edgenode_image   = "ghcr.io/holo-host/edgenode:latest"
harvester_image  = "ghcr.io/holo-host/edgenode-harvester:latest"

edgenode_volume_size  = 10   # GB — increase for production
harvester_volume_size = 10   # GB — increase for production

invite_codes = "test-invite-123"   # override via TF_VAR_invite_codes for production
