variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Workers, KV, D1, Pages: Edit)"
  type        = string
  sensitive   = true
}

variable "cloudflare_workers_subdomain" {
  description = "Cloudflare Workers subdomain (e.g. 'myaccount' for myaccount.workers.dev)"
  type        = string
}
