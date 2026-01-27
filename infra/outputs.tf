
output "master_public_ip" {
  value = hcloud_server.master.ipv4_address
}

output "master_private_ip" {
  value = [for n in hcloud_server.master.network : n.ip][0]
}

output "k3s_token" {
  value     = random_password.k3s_token.result
  sensitive = true
}

output "network_id" {
  value = hcloud_network.net.id
}

output "network_subnet_cidr" {
  value = hcloud_network_subnet.subnet.ip_range
}
