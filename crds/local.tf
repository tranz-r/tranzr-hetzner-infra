locals {
  cloudNativePGSettings = {
    name          = "cloudnative-pg"
    namespace     = "cnpg-system"
    chart_version = "0.28.0"
    repository    = "https://cloudnative-pg.github.io/charts"
  }

  externalSecretsSettings = {
    name          = "external-secrets"
    namespace     = "external-secrets"
    chart_version = "2.2.0"
    repository    = "https://charts.external-secrets.io"
  }

  rabbitmqClusterOperatorSettings = {
    name          = "rabbitmq-cluster-operator"
    namespace     = "rabbitmq-system"
    chart_version = "0.5.5"
    repository    = "oci://registry-1.docker.io/cloudpirates"
    chart         = "rabbitmq-cluster-operator"
  }
}
