resource "kubernetes_namespace_v1" "monitoring_system" {
  metadata {
    name = "monitoring-system"
  }
}

resource "kubernetes_manifest" "monitoring_grafana_credentials_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "monitoring-credentials"
      namespace = local.monitoring_namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "azure-kv-cluster-store"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "tranzr-monitoring-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "grafana-admin-password"
          remoteRef = {
            key = "tranzr-grafana-admin-password"
          }
        },
        {
          secretKey = "grafana-admin-user"
          remoteRef = {
            key = "tranzr-grafana-admin-user"
          }
        },
      ]
    }
  }

  depends_on = [
    kubernetes_namespace_v1.monitoring_system,
    kubernetes_manifest.azure_kv_cluster_store,
  ]
}

resource "kubernetes_manifest" "monitoring_alloy_config" {
  manifest = {
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "monitoring-alloy"
      namespace = local.monitoring_namespace
      labels = {
        "app.kubernetes.io/name"      = "monitoring"
        "app.kubernetes.io/instance"  = "monitoring"
        "app.kubernetes.io/component" = "alloy-config"
      }
    }
    data = {
      "config.alloy" = <<-EOT
        logging {
          level  = "info"
          format = "logfmt"
        }

        discovery.kubernetes "pods" {
          role = "pod"
        }

        discovery.relabel "pod_logs" {
          targets = discovery.kubernetes.pods.targets

          rule {
            source_labels = ["__meta_kubernetes_namespace"]
            regex         = "${join("|", local.monitoring_alloy_namespace_denylist)}"
            action        = "drop"
          }

          rule {
            source_labels = ["__meta_kubernetes_namespace"]
            target_label  = "namespace"
          }

          rule {
            source_labels = ["__meta_kubernetes_pod_name"]
            target_label  = "pod"
          }

          rule {
            source_labels = ["__meta_kubernetes_pod_container_name"]
            target_label  = "container"
          }

          rule {
            source_labels = ["__meta_kubernetes_pod_node_name"]
            target_label  = "node"
          }
        }

        loki.source.kubernetes "pod_logs" {
          targets    = discovery.relabel.pod_logs.output
          forward_to = [loki.process.pod_logs.receiver]
        }

        loki.process "pod_logs" {
          stage.static_labels {
            values = {
              cluster = "${local.monitoring_cluster_label}",
            }
          }
          forward_to = [loki.write.default.receiver]
        }

        loki.write "default" {
          endpoint {
            url = "${local.monitoring_loki_push_url}"
          }
        }

        otelcol.receiver.otlp "default" {
          grpc {
            endpoint = "0.0.0.0:4317"
          }
          http {
            endpoint = "0.0.0.0:4318"
          }

          output {
            traces  = [otelcol.exporter.otlp.tempo.input]
            metrics = [otelcol.exporter.prometheus.default.input]
          }
        }

        otelcol.exporter.otlp "tempo" {
          client {
            endpoint = "${local.monitoring_tempo_otlp_endpoint}"
            tls {
              insecure             = true
              insecure_skip_verify = true
            }
          }
        }

        otelcol.exporter.prometheus "default" {
          forward_to = [prometheus.remote_write.default.receiver]
        }

        prometheus.remote_write "default" {
          endpoint {
            url = "${local.monitoring_prometheus_remote_write_url}"
          }
        }
      EOT
    }
  }

  depends_on = [kubernetes_namespace_v1.monitoring_system]
}
