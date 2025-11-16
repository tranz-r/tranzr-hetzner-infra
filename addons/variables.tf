
variable "kubeconfig_path" { type = string }
variable "hcloud_token"    { type = string }
variable "email_le"        { type = string } # Let's Encrypt email


variable "tranzrCloudflareApiTokenKey" {
  description = "Tranzr Cloudflare API token key"
  sensitive = true
}

variable "letsencryptEmail" {
  description = "Email address for Let's Encrypt"
}

variable "tranzrDnsZones" {
  description = "Tranzr Cloudflare DNS zones"
}

variable "azureServicePrincipalClientId" {
  description = "Azure service principal client id"
  sensitive = true
}

variable "azureServicePrincipalClientSecret" {
  description = "Azure service principal client secret"
  sensitive = true
}

variable "azureServicePrincipalTenantId" {
  description = "Azure service principal tenant id"
  sensitive = true
}

variable "azureSubscriptionId" {
  description = "Azure subscription id"
  sensitive = true
}

variable "azureKeyVaultUrl" {
  description = "Azure Key Vault URL"
  default = "https://labgrid.vault.azure.net"
}
