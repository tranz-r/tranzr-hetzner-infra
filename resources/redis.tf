resource "kubernetes_namespace_v1" "redis_system" {
  metadata {
    name = "redis-system"
  }
}

resource "kubernetes_manifest" "redis_credentials_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "redis-credentials"
      namespace = kubernetes_namespace_v1.redis_system.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "azure-kv-cluster-store"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "redis-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "redis-password"
          remoteRef = {
            key = "platform-redis-password"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_namespace_v1.redis_system,
    kubernetes_manifest.azure_kv_cluster_store,
  ]
}

resource "helm_release" "redis" {
  name       = "redis"
  repository = "oci://registry-1.docker.io/cloudpirates"
  chart      = "redis"
  version    = "0.28.0"
  namespace  = kubernetes_namespace_v1.redis_system.metadata[0].name

  values = [
    yamlencode({
      architecture = "standalone"
      auth = {
        enabled                   = true
        existingSecret            = "redis-credentials"
        existingSecretPasswordKey = "redis-password"
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
    kubernetes_namespace_v1.redis_system,
    kubernetes_manifest.redis_credentials_external_secret,
  ]
}
