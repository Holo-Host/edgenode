terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ── KV namespace (joining service) ─────────────────────────────────────────

resource "cloudflare_workers_kv_namespace" "sessions" {
  account_id = var.cloudflare_account_id
  title      = "spike-sessions"
}

# ── D1 database (log-collector) ────────────────────────────────────────────
# Tests: does the provider support D1 bindings on cloudflare_worker_script?

resource "cloudflare_d1_database" "log_collector" {
  account_id = var.cloudflare_account_id
  name       = "spike-log-collector-db"
}

# ── Joining service Worker ─────────────────────────────────────────────────
# Tests:
#   - Does cloudflare_worker_script accept an esbuild-bundled ES module?
#   - Do KV namespace bindings wire up correctly?

resource "cloudflare_worker_script" "joining" {
  account_id = var.cloudflare_account_id
  name       = "spike-joining"
  content    = file("${path.module}/../dist/joining.js")
  module     = true

  kv_namespace_binding {
    name         = "SESSIONS"
    namespace_id = cloudflare_workers_kv_namespace.sessions.id
  }

  # Minimal CONFIG_JSON so the Worker initialises without erroring
  plain_text_binding {
    name = "CONFIG_JSON"
    text = jsonencode({
      happ = {
        id              = "spike"
        name            = "Spike"
        happ_bundle_url = "https://example.com/spike.happ"
      }
      auth_methods = ["invite_code"]
      invite_codes = ["spike-test"]
      session      = { store = "cloudflare-kv" }
    })
  }
}

# ── Log-collector Worker ───────────────────────────────────────────────────
# Tests:
#   - Does cloudflare_worker_script accept an esbuild-bundled ES module?
#   - Do D1 database bindings wire up correctly?

resource "cloudflare_worker_script" "log_collector" {
  account_id = var.cloudflare_account_id
  name       = "spike-log-collector"
  content    = file("${path.module}/../dist/log-collector.js")
  module     = true

  d1_database_binding {
    name        = "DB"
    database_id = cloudflare_d1_database.log_collector.id
  }

  secret_text_binding {
    name = "ADMIN_SECRET"
    text = "spike-admin-secret"
  }
}
