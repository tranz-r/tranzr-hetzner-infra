resource "helm_release" "monitoring_tempo" {
  name       = "monitoring-tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.24.4"
  namespace  = local.monitoring_namespace
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      fullnameOverride = "monitoring-tempo"
      tempo = {
        retention = "168h"
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { cpu = "2000m", memory = "2Gi" }
        }
      }
      persistence = {
        enabled          = true
        storageClassName = local.monitoring_storage_class
        accessModes      = ["ReadWriteOnce"]
        size             = "30Gi"
      }
      serviceMonitor = {
        enabled = false
      }
    }),
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring_system,
    helm_release.kps_monitoring,
  ]
}
