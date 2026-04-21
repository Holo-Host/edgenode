provider "hcloud" {
  token = var.hcloud_token
}

locals {
  # Deterministic log-collector URL — used in cloud-init before the resource
  # exists; the depends_on on hcloud_server.edgenode ensures ordering.
  log_collector_url = "https://${var.project_name}-log-collector.${var.cloudflare_workers_subdomain}.workers.dev"
}

# ── SSH key ─────────────────────────────────────────────────────────────────

resource "hcloud_ssh_key" "operator" {
  name       = "${var.project_name}-operator"
  public_key = var.ssh_public_key
}

# ── Firewalls ────────────────────────────────────────────────────────────────

resource "hcloud_firewall" "edgenode" {
  name = "${var.project_name}-edgenode"

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # HTTP (Let's Encrypt ACME challenge)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # HTTPS (Caddy / h2hc-linker)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall" "harvester" {
  name = "${var.project_name}-harvester"

  # SSH only — harvester conductor admin port (4444) is accessed via SSH tunnel
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ── Persistent volumes ───────────────────────────────────────────────────────
# Volumes are managed independently of VMs. A VM can be replaced (e.g. for an
# image update) while its volume and all Holochain data remain intact.

resource "hcloud_volume" "edgenode" {
  count    = var.edgenode_count
  name     = "${var.project_name}-edgenode-${count.index}"
  size     = var.edgenode_volume_size
  location = var.hetzner_location
  format   = "ext4"
}

resource "hcloud_volume" "harvester" {
  name     = "${var.project_name}-harvester"
  size     = var.harvester_volume_size
  location = var.hetzner_location
  format   = "ext4"
}

# ── Edgenode VMs ─────────────────────────────────────────────────────────────

resource "hcloud_server" "edgenode" {
  count        = var.edgenode_count
  name         = "${var.project_name}-edgenode-${count.index}"
  server_type  = var.edgenode_server_type
  image        = "ubuntu-24.04"
  location     = var.hetzner_location
  ssh_keys     = [hcloud_ssh_key.operator.id]
  firewall_ids = [hcloud_firewall.edgenode.id]

  user_data = templatefile("${path.module}/../cloud-init/edgenode.yml.tpl", {
    volume_id               = hcloud_volume.edgenode[count.index].id
    caddy_domain            = "linker-${count.index}.${var.domain}"
    linker_bootstrap_url    = var.linker_bootstrap_url
    linker_admin_secret     = var.linker_admin_secret
    log_sender_endpoint     = local.log_collector_url
    log_sender_unyt_pub_key = var.log_sender_unyt_pub_key
    lair_password           = var.lair_password
    edgenode_image          = var.edgenode_image
  })

  # Ensure log-collector is deployed before VMs boot and attempt to send logs
  depends_on = [cloudflare_workers_deployment.log_collector]
}

resource "hcloud_volume_attachment" "edgenode" {
  count     = var.edgenode_count
  volume_id = hcloud_volume.edgenode[count.index].id
  server_id = hcloud_server.edgenode[count.index].id
  automount = false
}

# ── Harvester VM ─────────────────────────────────────────────────────────────

resource "hcloud_server" "harvester" {
  name         = "${var.project_name}-harvester"
  server_type  = var.harvester_server_type
  image        = "ubuntu-24.04"
  location     = var.hetzner_location
  ssh_keys     = [hcloud_ssh_key.operator.id]
  firewall_ids = [hcloud_firewall.harvester.id]

  user_data = templatefile("${path.module}/../cloud-init/harvester.yml.tpl", {
    volume_id               = hcloud_volume.harvester.id
    harvester_lair_password = var.harvester_lair_password
    collector_url           = local.log_collector_url
    admin_secret            = var.log_collector_admin_secret
    harvester_image         = var.harvester_image
  })
}

resource "hcloud_volume_attachment" "harvester" {
  volume_id = hcloud_volume.harvester.id
  server_id = hcloud_server.harvester.id
  automount = false
}
