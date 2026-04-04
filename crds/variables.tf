
variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig file"
}

variable "gateway_api_version" {
  description = "Gateway API standard bundle tag (must match release URL and CRD bundle-version annotation)"
  type        = string
  default     = "v1.5.1"
}
