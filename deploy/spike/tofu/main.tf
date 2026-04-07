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

resource "cloudflare_d1_database" "log_collector" {
  account_id = var.cloudflare_account_id
  name       = "spike-log-collector-db"
}

# ── Joining service Worker ─────────────────────────────────────────────────
# Tests:
#   - Does the current cloudflare_worker + cloudflare_worker_version model
#     accept an esbuild-bundled ES module via content_file?
#   - Do KV namespace bindings wire up via the unified bindings array?

resource "cloudflare_worker" "joining" {
  account_id = var.cloudflare_account_id
  name       = "spike-joining"
}

resource "cloudflare_worker_version" "joining" {
  account_id         = var.cloudflare_account_id
  worker_id          = cloudflare_worker.joining.id
  compatibility_date = "2024-12-01"
  main_module        = "joining.js"

  modules = [{
    name         = "joining.js"
    content_type = "application/javascript+module"
    content_file = "${path.module}/../dist/joining.js"
  }]

  bindings = [
    {
      type         = "kv_namespace"
      name         = "SESSIONS"
      namespace_id = cloudflare_workers_kv_namespace.sessions.id
    },
    {
      type = "plain_text"
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
  ]
}

resource "cloudflare_workers_deployment" "joining" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker.joining.name
  strategy    = "percentage"
  versions = [{
    percentage = 100
    version_id = cloudflare_worker_version.joining.id
  }]
}

# ── Log-collector Worker ───────────────────────────────────────────────────
# Tests:
#   - Does content_file work for a larger bundle (1.2mb uncompressed)?
#   - Do D1 database bindings wire up via the unified bindings array?

resource "cloudflare_worker" "log_collector" {
  account_id = var.cloudflare_account_id
  name       = "spike-log-collector"
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
      type = "d1"
      name = "DB"
      id   = cloudflare_d1_database.log_collector.id
    },
    {
      type = "secret_text"
      name = "ADMIN_SECRET"
      text = "spike-admin-secret"
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
