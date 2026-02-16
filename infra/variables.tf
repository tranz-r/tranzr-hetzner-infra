
variable "hcloud_token" { 
  type = string
  sensitive = true
  description = "Hetzner Cloud API token"
}

variable "ssh_public_key" { 
  type = string
  sensitive = true
  description = "SSH public key"
}

variable "ssh_private_key_path" { 
  type = string
  sensitive = true
  description = "SSH private key path"
}

variable "network_zone"       { 
  type = string  
  default = "eu-central"
  description = "Hetzner Cloud network zone"
}

variable "location"       { 
  type = string  
  default = "nbg1"
  description = "Hetzner Cloud location"
}

variable "image"        { 
  type = string  
  default = "ubuntu-24.04" 
  description = "Hetzner Cloud image"
}

variable "worker_type"  { 
  type = string  
  default = "cx43" 
  description = "Hetzner Cloud server type"
}

variable "workers"      { 
  type = number  
  default = 1 
  description = "Number of workers"
}

variable "cluster_name" { 
  type = string  
  default = "tranzr" 
  description = "Cluster name"
}

variable "master_type"  { 
  type = string  
  default = "cx33" 
  description = "Hetzner Cloud master type"
}

variable "k3s_channel"  { 
  type = string  
  default = "stable" 
  description = "K3s channel"
}

variable "worker_labels" {
  type    = list(string)
  description = "Worker labels"
  default = ["role=apps"]
}
