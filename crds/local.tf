locals {
  cloudNativePGSettings = {
    name          = "cloudnative-pg"
    namespace     = "cnpg-system"
    chart_version = "0.27.0"
    repository    = "https://cloudnative-pg.github.io/charts"
  }

  externalSecretsSettings = {
    name          = "external-secrets"
    namespace     = "external-secrets"
    chart_version = "2.0.0"
    repository    = "https://charts.external-secrets.io"
  }
}
