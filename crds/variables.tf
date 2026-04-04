
variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig file"
}

variable "nginx_gateway_api_version" {
  description = "Nginx Gateway API standard bundle tag (must match release URL and CRD bundle-version annotation)"
  type        = string
  default     = "2.5.0"
}
