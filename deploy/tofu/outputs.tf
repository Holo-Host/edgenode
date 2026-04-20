output "edgenode_ips" {
  description = "Public IPv4 addresses of edgenode VMs (index matches linker-<n>.<domain>)"
  value       = [for s in hcloud_server.edgenode : s.ipv4_address]
}

output "harvester_ip" {
  description = "Public IPv4 address of the harvester VM"
  value       = hcloud_server.harvester.ipv4_address
}

output "edgenode_linker_urls" {
  description = "Public HTTPS URLs for each edgenode's h2hc-linker endpoint"
  value       = [for i in range(var.edgenode_count) : "https://linker-${i}.${var.domain}"]
}

output "log_collector_url" {
  description = "Log-collector Worker URL"
  value       = "https://${var.project_name}-log-collector.${var.cloudflare_workers_subdomain}.workers.dev"
}

output "sessions_kv_namespace_id" {
  description = "SESSIONS KV namespace ID (pass to joining service wrangler deploy)"
  value       = cloudflare_workers_kv_namespace.sessions.id
}

output "volume_ids" {
  description = "Persistent volume IDs — keep these safe, they hold Holochain data"
  value = {
    edgenode  = [for v in hcloud_volume.edgenode : v.id]
    harvester = hcloud_volume.harvester.id
  }
}
