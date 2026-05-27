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

resource "helm_release" "rabbitmq" {
  name       = "rabbitmq"
  repository = "oci://registry-1.docker.io/cloudpirates"
  chart      = "rabbitmq"
  version    = "0.21.4"
  namespace  = kubernetes_namespace_v1.rabbitmq_system.metadata[0].name

  values = [
    yamlencode({
      replicaCount = 1
      auth = {
        enabled                 = true
        username                = "admin"
        existingSecret          = "rabbitmq-credentials"
        existingPasswordKey     = "password"
        existingErlangCookieKey = "erlang-cookie"
      }
      persistence = {
        enabled      = true
        storageClass = "hcloud-volumes"
        size         = "5Gi"
      }
      service = {
        type = "ClusterIP"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.rabbitmq_system,
    kubernetes_manifest.rabbitmq_credentials_external_secret,
  ]
}
