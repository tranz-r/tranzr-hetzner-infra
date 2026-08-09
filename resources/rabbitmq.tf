# Standalone CloudPirates rabbitmq Helm release removed (cutover to RabbitmqCluster).
resource "kubernetes_namespace_v1" "rabbitmq_system" {
  metadata {
    name = "rabbitmq-system"
  }
}

resource "kubernetes_manifest" "rabbitmq_credentials_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "rabbitmq-credentials"
      namespace = kubernetes_namespace_v1.rabbitmq_system.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "azure-kv-cluster-store"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "rabbitmq-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "password"
          remoteRef = {
            key = "platform-rabbitmq-password"
          }
        },
        {
          secretKey = "erlang-cookie"
          remoteRef = {
            key = "platform-rabbitmq-erlang-cookie"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_namespace_v1.rabbitmq_system,
    kubernetes_manifest.azure_kv_cluster_store,
  ]
}
