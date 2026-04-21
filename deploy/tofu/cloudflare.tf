terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.0"
    }
  }
  # State: local for staging PoC.
  # For team use, migrate to Hetzner Object Storage (S3-compatible):
  #   backend "s3" {
  #     bucket   = "tofu-state"
  #     key      = "edgenode/staging.tfstate"
  #     region   = "us-east-1"          # required but ignored by Hetzner
  #     endpoint = "https://fsn1.your-objectstorage.com"
  #     ...
  #   }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ── KV namespace: SESSIONS (joining service) ────────────────────────────────

resource "cloudflare_workers_kv_namespace" "sessions" {
  account_id = var.cloudflare_account_id
  title      = "${var.project_name}-sessions"
}

# ── Log-collector Worker ────────────────────────────────────────────────────
# The joining service Worker is NOT deployed here — it uses wrangler deploy
# due to @holo-host/lair's libsodium WASM dependency (see DESIGN.md Appendix A).
# The log-collector has no WASM dependencies and deploys cleanly via OpenTofu.
#
# The bundle at ../dist/log-collector.js is built by scripts/staging-apply.sh
# (or production-apply.sh) before tofu apply runs.

resource "cloudflare_worker" "log_collector" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-log-collector"
  subdomain  = { enabled = true }
}

resource "cloudflare_worker_version" "log_collector" {
  account_id         = var.cloudflare_account_id
  worker_id          = cloudflare_worker.log_collector.id
  compatibility_date = "2024-10-01"
  main_module        = "log-collector.js"

  modules = [{
    name         = "log-collector.js"
    content_type = "application/javascript+module"
    content_file = "${path.module}/../dist/log-collector.js"
  }]

  bindings = [
    {
      type = "kv_namespace"
      name = "LOGS"
      namespace_id = cloudflare_workers_kv_namespace.sessions.id
    },
    {
      type = "secret_text"
      name = "ADMIN_SECRET"
      text = var.log_collector_admin_secret
    }
  ]
}

resource "cloudflare_workers_deployment" "log_collector" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker.log_collector.name
  strategy    = "percentage"
  versions = [{
    percentage = 100
    version_id = cloudflare_worker_version.log_collector.id
  }]
}

# ── DNS A records ───────────────────────────────────────────────────────────
# One record per edgenode: linker-<n>.<domain> → VM public IP.
# Proxied = false: Caddy terminates TLS directly; Cloudflare proxy would
# intercept port 443 and break Let's Encrypt HTTP challenge on port 80.

resource "cloudflare_dns_record" "edgenode" {
  count   = var.edgenode_count
  zone_id = var.cloudflare_zone_id
  name    = "linker-${count.index}.${var.domain}"
  type    = "A"
  content = hcloud_server.edgenode[count.index].ipv4_address
  ttl     = 60
  proxied = false
}
