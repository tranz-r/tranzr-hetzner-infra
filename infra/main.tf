resource "hcloud_ssh_key" "me" {
  name       = "${var.cluster_name}-ssh"
  public_key = var.ssh_public_key
}

resource "hcloud_network" "net" {
  name     = "${var.cluster_name}-net"
  ip_range = "10.20.0.0/16"
}

resource "hcloud_network_subnet" "subnet" {
  network_id   = hcloud_network.net.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = "10.20.0.0/24"
}

resource "hcloud_firewall" "k8s" {
  name = "${var.cluster_name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "Kubernetes API server - required for Terraform/kubectl access"
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "1-65535"
    source_ips = ["10.20.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "1-65535"
    source_ips = ["10.20.0.0/16"]
  }
}

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

locals {
  master_hostname   = "${var.cluster_name}-control-plane"
  worker_hostnames  = [for i in range(var.workers) : "${var.cluster_name}-worker-${i + 1}"]
  master_private_ip = "10.20.0.2" # static so we can put it in k3s --tls-san (Cilium connects to this IP)
}

data "template_file" "master_cloudinit" {
  template = file("${path.module}/cloudinit/master.yaml.tmpl")
  vars = {
    k3s_token          = random_password.k3s_token.result
    k3s_channel        = var.k3s_channel
    node_name          = local.master_hostname
    master_private_ip  = local.master_private_ip
  }
}

resource "hcloud_server" "master" {
  name         = local.master_hostname
  image        = var.image
  server_type  = var.master_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.me.id]
  firewall_ids = [hcloud_firewall.k8s.id]

  network {
    network_id = hcloud_network.net.id
    ip         = local.master_private_ip
    alias_ips  = []
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  user_data = data.template_file.master_cloudinit.rendered

  lifecycle {
    # create_before_destroy = true
  }
}

resource "hcloud_server" "worker" {
  count        = var.workers
  name         = local.worker_hostnames[count.index]
  image        = var.image
  server_type  = var.worker_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.me.id]
  firewall_ids = [hcloud_firewall.k8s.id]

  lifecycle {
    create_before_destroy = true
  }

  network {
    network_id = hcloud_network.net.id
    alias_ips = []
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  user_data = templatefile("${path.module}/cloudinit/worker.yaml.tmpl", {
    k3s_token   = random_password.k3s_token.result
    master_ip   = [for n in hcloud_server.master.network : n.ip][0]
    k3s_channel = var.k3s_channel
    labels      = join(",", var.worker_labels)
    node_name   = local.worker_hostnames[count.index]
  })
  depends_on = [hcloud_server.master]
}
