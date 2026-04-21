# ── Provider credentials ────────────────────────────────────────────────────

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Workers Scripts: Edit, Workers KV Storage: Edit, DNS: Edit, Account Settings: Read)"
  type        = string
  sensitive   = true
}

variable "cloudflare_workers_subdomain" {
  description = "Cloudflare Workers subdomain (e.g. 'myaccount' for myaccount.workers.dev)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS A record management"
  type        = string
}

# ── SSH ─────────────────────────────────────────────────────────────────────

variable "ssh_public_key" {
  description = "Contents of the SSH public key to install on Hetzner VMs"
  type        = string
}

# ── Deployment config ───────────────────────────────────────────────────────

variable "project_name" {
  description = "Short name prefixed on all Hetzner and Cloudflare resources"
  type        = string
  default     = "edgenode"
}

variable "hetzner_location" {
  description = "Hetzner datacenter location (nbg1, fsn1, hel1, ash, hil)"
  type        = string
  default     = "nbg1"
}

variable "domain" {
  description = "Base domain for this deployment (e.g. staging.mewsfeed.app). DNS A records are created as linker-<n>.<domain>."
  type        = string
}

variable "edgenode_count" {
  description = "Number of edgenode VMs to provision"
  type        = number
  default     = 2
}

variable "edgenode_server_type" {
  description = "Hetzner server type for edgenode VMs"
  type        = string
  default     = "cx22"
}

variable "harvester_server_type" {
  description = "Hetzner server type for the harvester VM"
  type        = string
  default     = "cx22"
}

variable "edgenode_image" {
  description = "Docker image for edgenode containers (conductor + h2hc-linker + caddy + log-sender)"
  type        = string
  default     = "ghcr.io/holo-host/edgenode:latest"
}

variable "harvester_image" {
  description = "Docker image for the harvester container (conductor + log-harvester)"
  type        = string
  default     = "ghcr.io/holo-host/edgenode-harvester:latest"
}

variable "edgenode_volume_size" {
  description = "Size in GB of the persistent data volume for each edgenode VM"
  type        = number
  default     = 10
}

variable "harvester_volume_size" {
  description = "Size in GB of the persistent data volume for the harvester VM"
  type        = number
  default     = 10
}

# ── Application secrets ─────────────────────────────────────────────────────

variable "linker_bootstrap_url" {
  description = "Kitsune2 bootstrap server URL for h2hc-linker (H2HC_LINKER_BOOTSTRAP_URL)"
  type        = string
}

variable "linker_admin_secret" {
  description = "Shared secret between h2hc-linker and the joining service (optional auth layer)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "invite_codes" {
  description = "Comma-separated invite codes for HWC browser nodes"
  type        = string
  default     = "test-invite-123"
}

variable "lair_password" {
  description = "Lair keystore password for edgenode conductors"
  type        = string
  sensitive   = true
}

variable "harvester_lair_password" {
  description = "Lair keystore password for the harvester conductor"
  type        = string
  sensitive   = true
}

variable "log_sender_unyt_pub_key" {
  description = "Unyt agent public key (uhCAk...) used by log-sender for billing attribution"
  type        = string
}

variable "log_collector_admin_secret" {
  description = "Admin secret for the log-collector Worker"
  type        = string
  sensitive   = true
}
