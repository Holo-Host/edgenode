# Production deployment — non-secret configuration
# Secrets are passed via TF_VAR_* environment variables (see deploy/.env.example)

project_name          = "edgenode-production"
hetzner_location      = "nbg1"
domain                = "production.example.com"   # replace with your domain

edgenode_count        = 2   # scale up for larger communities
edgenode_server_type  = "cx22"
harvester_server_type = "cx22"

edgenode_image   = "ghcr.io/holo-host/edgenode:latest"
harvester_image  = "ghcr.io/holo-host/edgenode-harvester:latest"

edgenode_volume_size  = 20
harvester_volume_size = 20

invite_codes = ""   # set via TF_VAR_invite_codes from .env.production
