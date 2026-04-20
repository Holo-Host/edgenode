# Staging deployment — non-secret configuration
# Secrets are passed via TF_VAR_* environment variables (see deploy/.env.example)

project_name          = "edgenode-staging"
hetzner_location      = "nbg1"
domain                = "staging.example.com"   # replace with your domain

edgenode_count        = 2
edgenode_server_type  = "cx22"
harvester_server_type = "cx22"

edgenode_image   = "ghcr.io/holo-host/edgenode:latest"
harvester_image  = "ghcr.io/holo-host/edgenode-harvester:latest"

edgenode_volume_size  = 10
harvester_volume_size = 10

invite_codes = "test-invite-123"
