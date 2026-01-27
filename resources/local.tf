locals {

  certManagerSettings = {
    name          = "cert-manager"
    namespace     = "cert-manager"
    chart_version = "v1.19.2"
    repository    = "https://charts.jetstack.io"
  }

  clusterIssuerSettings = {
    nameStaging          = "letsencrypt-staging"
    nameProduction       = "letsencrypt-production"
    tranzrNameStaging          = "tranzr-letsencrypt-staging"
    tranzrNameProduction       = "tranzr-letsencrypt-production"
    stagingServer        = "https://acme-staging-v02.api.letsencrypt.org/directory"
    productionServer     = "https://acme-v02.api.letsencrypt.org/directory"
    namespace     = "cert-manager"
    apiVersion    = "cert-manager.io/v1"
    kind          = "ClusterIssuer"
    issuerRef     = "letsencrypt"
    email = var.letsencryptEmail
  }

  nginxGatewayFabricSettings = {
    name          = "ngf"
    namespace     = "nginx-gateway"
    chart_version = "2.3.0"
    repository    = "oci://ghcr.io/nginx/charts"
    chart         = "nginx-gateway-fabric"
  }
}