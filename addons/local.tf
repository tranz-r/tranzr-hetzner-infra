locals {
  hetznerCloudSettings = {
    namespace     = "kube-system"
    ccm_version = "1.28.0"
    hcloud_csi_version = "2.18.0"
    repository    = "https://charts.hetzner.cloud"
  }

  certManagerSettings = {
    name          = "cert-manager"
    namespace     = "cert-manager"
    chart_version = "v1.17.0"
    repository    = "https://charts.jetstack.io"
  }

  cloudNativePGSettings = {
    name          = "cloudnative-pg"
    namespace     = "cnpg-system"
    chart_version = "0.26.1"
    repository    = "https://cloudnative-pg.github.io/charts"
  }

  externalSecretsSettings = {
    name          = "external-secrets"
    namespace     = "external-secrets"
    chart_version = "1.0.0"
    repository    = "https://charts.external-secrets.io"
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
}