
output "master_public_ip" {
  value = hcloud_primary_ip.master.ip_address
}

output "master_private_ip" {
  value = local.master_private_ip
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
