output "joining_worker_url" {
  description = "Joining service Worker URL"
  value       = "https://spike-joining.${var.cloudflare_workers_subdomain}.workers.dev"
}

output "log_collector_worker_url" {
  description = "Log-collector Worker URL"
  value       = "https://spike-log-collector.${var.cloudflare_workers_subdomain}.workers.dev"
}

output "kv_namespace_id" {
  description = "SESSIONS KV namespace ID"
  value       = cloudflare_workers_kv_namespace.sessions.id
}

output "d1_database_id" {
  description = "Log-collector D1 database ID"
  value       = cloudflare_d1_database.log_collector.id
}
