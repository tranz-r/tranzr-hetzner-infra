
module "kube-hetzner" {
  providers = {
    hcloud = hcloud
  }

  source       = "kube-hetzner/kube-hetzner/hcloud"
  version      = "3.2.1"
  hcloud_token = var.hcloud_token

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key != "" ? var.ssh_private_key : file(var.ssh_private_key_path)

  network_region = "eu-central"

  extra_firewall_rules = [
    {
      description     = "Allow outbound PostgreSQL"
      direction       = "out"
      protocol        = "tcp"
      port            = "5432"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
    },
    {
      description     = "Allow outbound PgBouncer"
      direction       = "out"
      protocol        = "tcp"
      port            = "6543"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
    },
    {
      description     = "Allow outbound SMTP for Azure Communication Services"
      direction       = "out"
      protocol        = "tcp"
      port            = "587"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
    }
  ]

  control_plane_nodepools = [
    {
      name        = "control-plane-nbg1"
      server_type = var.control_plane_type
      location    = var.location
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  agent_nodepools = [
    {
      name        = "agents"
      server_type = var.agent_type
      location    = var.location
      labels      = []
      taints      = []
      count       = 2
    }
  ]

  # Cost-focused autoscaler: scale from 0, cap burst at 3; baseline is 2 static agents.
  # Node group / label: hcloud/node-group=tranzrmoves-ca-nbg1
  # Before apply: delete leftover servers from older pool names (e.g. autoscaled-agents).
  autoscaler_nodepools = [
    {
      name        = "ca-nbg1"
      server_type = var.agent_type
      location    = var.location
      min_nodes   = 0 # no idle autoscaled nodes (baseline stays on static "agents")
      max_nodes   = 3 # hard cost ceiling; not a target size
    }
  ]

  # Softer than 5m so CA is less likely to fight SUC drains on Saturday upgrades.
  cluster_autoscaler_extra_args = [
    "--scale-down-utilization-threshold=0.6",
    "--scale-down-unneeded-time=15m",
    "--scale-down-delay-after-add=15m",
    "--skip-nodes-with-local-storage=false",
  ]

  system_upgrade_use_drain = true

  cluster_name = "tranzrmoves"

  # Track current k3s stable (includes minor bumps when upstream promotes them).
  k3s_channel = "stable"

  cni_plugin            = "cilium"
  cilium_version        = "1.19.1"
  cilium_routing_mode   = "native"
  cilium_hubble_enabled = true
  enable_kube_proxy     = false

  ingress_controller = "none"

  hetzner_ccm_version = "1.31.0"

  hetzner_csi_version = "2.18.0"

  enable_cert_manager  = true
  cert_manager_version = "v1.19.3"
  cert_manager_values  = <<EOT
crds:
  enabled: true
extraArgs:
  # - --dns01-recursive-nameservers=1.1.1.1:53,9.9.9.9:53
  # - --dns01-recursive-nameservers-only
  - --enable-gateway-api
  EOT 

  automatically_upgrade_kubernetes = true
  automatically_upgrade_os         = false
  enable_kured                     = false

  system_upgrade_schedule_window = {
    days      = ["saturday"]
    startTime = "02:00"
    endTime   = "05:00"
    timeZone  = "Europe/London"
  }

  dns_servers = [
    "1.1.1.1",
    "8.8.8.8",
    "2606:4700:4700::1111",
  ]
}
