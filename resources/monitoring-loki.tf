resource "helm_release" "monitoring_loki" {
  name       = "monitoring-loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.49.0"
  namespace  = local.monitoring_namespace
  timeout    = 900
  wait       = true

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"
      singleBinary = {
        replicas = 1
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { cpu = "2000m", memory = "2Gi" }
        }
        persistence = {
          enabled      = true
          storageClass = local.monitoring_storage_class
          accessModes  = ["ReadWriteOnce"]
          size         = "50Gi"
        }
      }
      write        = { replicas = 0 }
      read         = { replicas = 0 }
      backend      = { replicas = 0 }
      chunksCache  = { enabled = false }
      resultsCache = { enabled = false }
      test         = { enabled = false }
      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        limits_config = {
          retention_period            = "168h"
          ingestion_rate_mb           = 8
          ingestion_burst_size_mb     = 16
          per_stream_rate_limit       = "5MB"
          per_stream_rate_limit_burst = "15MB"
        }
        storage = {
          type = "filesystem"
          filesystem = {
            chunks_directory = "/var/loki/chunks"
            rules_directory  = "/var/loki/rules"
          }
        }
        schemaConfig = {
          configs = [
            {
              from         = "2024-04-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            },
          ]
        }
      }
    }),
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring_system,
    helm_release.kps_monitoring,
  ]
}
