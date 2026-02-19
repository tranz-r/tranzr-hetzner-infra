variable "ssh_public_key" { 
  type = string
  sensitive = true
  description = "SSH public key"
}

variable "ssh_private_key_path" { 
  type        = string
  default     = ""
  sensitive   = true
  description = "Path to SSH private key file (used when ssh_private_key is not set). In CI, use an absolute path, e.g. $HOME/.ssh/id_ed25519."
}

variable "ssh_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "SSH private key content. If set, used instead of ssh_private_key_path (avoids file() so it works in CI without a writable path)."
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

variable "location" {
  type        = string
  default     = "nbg1"
  description = "Hetzner Cloud location"
}

variable "microos_x86_snapshot_id" {
  type        = string
  default     = ""
  description = "Hetzner image ID for MicroOS x86. Set after building with Packer (hcloud-microos-snapshots.pkr.hcl); otherwise the module looks for an image with selector microos-snapshot=yes."
}

variable "microos_arm_snapshot_id" {
  type        = string
  default     = ""
  description = "Hetzner image ID for MicroOS ARM. Set after building with Packer; leave empty if not using ARM nodes."
}