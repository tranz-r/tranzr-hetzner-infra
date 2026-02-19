
module "kube-hetzner" {
  providers = {
    hcloud = hcloud
  }

  source       = "kube-hetzner/kube-hetzner/hcloud"
  hcloud_token = var.hcloud_token

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = file(var.ssh_private_key_path)

  network_region = "eu-central"

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

  autoscaler_nodepools = [
    {
      name        = "autoscaled-agents"
      server_type = var.agent_type
      location    = var.location
      min_nodes   = 1
      max_nodes   = 3
    }
  ]

  system_upgrade_use_drain = true

  cluster_name = "tranzrmoves"

  initial_k3s_channel = "v1.35.1+k3s1"

  cni_plugin            = "cilium"
  cilium_version        = "1.19.1"
  cilium_routing_mode   = "native"
  cilium_hubble_enabled = true
  disable_kube_proxy    = true

  ingress_controller = "nginx"

  hetzner_ccm_use_helm = true
  hetzner_ccm_version  = "1.28.0"

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

  automatically_upgrade_k3s = true
  automatically_upgrade_os  = true

  dns_servers = [
    "1.1.1.1",
    "8.8.8.8",
    "2606:4700:4700::1111",
  ]
}
