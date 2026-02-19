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

variable "hcloud_token"    { 
  type = string 
  description = "Hetzner Cloud API token"
  sensitive = true
}

variable "control_plane_type"  { 
  type = string  
  # default = "cx33" 
  default = "cpx32" 
  description = "Hetzner Cloud control plane type"
}

variable "agent_type"  { 
  type = string  
  default = "cpx32"
  # default = "cx43" 
  description = "Hetzner Cloud agent type"
}

variable "location"       { 
  type = string  
  default = "nbg1"
  description = "Hetzner Cloud location"
}