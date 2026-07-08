resource "helm_release" "monitoring_alloy" {
  name       = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = "1.5.1"
  namespace  = local.monitoring_namespace
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      alloy = {
        configMap = {
          create = false
          name   = "monitoring-alloy"
          key    = "config.alloy"
        }
        extraPorts = [
          {
            name       = "otlp-grpc"
            port       = 4317
            targetPort = 4317
            protocol   = "TCP"
          },
          {
            name       = "otlp-http"
            port       = 4318
            targetPort = 4318
            protocol   = "TCP"
          },
        ]
      }
      controller = {
        type = "daemonset"
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "1Gi" }
      }
      serviceMonitor = {
        enabled = false
      }
    }),
  ]

  depends_on = [
    kubernetes_manifest.monitoring_alloy_config,
    helm_release.kps_monitoring,
    helm_release.monitoring_loki,
    helm_release.monitoring_tempo,
  ]
}
