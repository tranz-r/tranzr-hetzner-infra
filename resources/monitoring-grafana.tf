resource "helm_release" "monitoring_grafana" {
  name       = "monitoring-grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "10.5.15"
  namespace  = local.monitoring_namespace
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      replicas = 1
      admin = {
        existingSecret = "tranzr-monitoring-credentials"
        userKey        = "grafana-admin-user"
        passwordKey    = "grafana-admin-password"
      }
      persistence = {
        enabled          = true
        type             = "pvc"
        storageClassName = local.monitoring_storage_class
        accessModes      = ["ReadWriteOnce"]
        size             = "10Gi"
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
      ingress = {
        enabled = false
      }
      sidecar = {
        dashboards = {
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "ALL"
        }
        datasources = {
          enabled = false
        }
      }
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Prometheus"
              type      = "prometheus"
              uid       = "prometheus"
              access    = "proxy"
              isDefault = true
              url       = "http://kps-monitoring-prometheus.${local.monitoring_namespace}.svc.cluster.local:9090"
            },
            {
              name   = "Loki"
              type   = "loki"
              uid    = "loki"
              access = "proxy"
              url    = "http://monitoring-loki-gateway.${local.monitoring_namespace}.svc.cluster.local"
              jsonData = {
                httpHeaderName1 = "X-Scope-OrgID"
              }
              secureJsonData = {
                httpHeaderValue1 = "fake"
              }
            },
            {
              name   = "Tempo"
              type   = "tempo"
              uid    = "tempo"
              access = "proxy"
              url    = "http://monitoring-tempo.${local.monitoring_namespace}.svc.cluster.local:3200"
              jsonData = {
                httpMethod = "GET"
                tracesToLogs = {
                  datasourceUid   = "loki"
                  filterByTraceID = true
                  filterBySpanID  = false
                }
                serviceMap = {
                  datasourceUid = "prometheus"
                }
                nodeGraph = {
                  enabled = true
                }
              }
            },
          ]
        }
      }
    }),
  ]

  depends_on = [
    kubernetes_manifest.monitoring_grafana_credentials_external_secret,
    helm_release.kps_monitoring,
  ]
}
