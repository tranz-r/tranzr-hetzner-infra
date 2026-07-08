locals {
  monitoring_namespace     = kubernetes_namespace_v1.monitoring_system.metadata[0].name
  monitoring_storage_class = "hcloud-volumes"
  monitoring_cluster_label = "tranzrmoves"
  monitoring_issuer        = "tranzr-letsencrypt-production"
  monitoring_prom_label    = "kps-monitoring"

  # Opt-in Prometheus scraping — ServiceMonitors/PodMonitors must carry this label.
  monitoring_prometheus_scrape_label = "prometheus-scrape"
  monitoring_prometheus_scrape_value = "true"

  # Alloy log collection: skip infra namespaces (apps in *-system and app namespaces are kept).
  monitoring_alloy_namespace_denylist = [
    "kube-system",
    "kube-public",
    "kube-node-lease",
    "monitoring-system",
    "cert-manager",
    "external-secrets",
    "cnpg-system",
    "nginx-gateway",
    "dapr-system",
  ]

  monitoring_loki_push_url               = "http://monitoring-loki-gateway.${local.monitoring_namespace}.svc.cluster.local/loki/api/v1/push"
  monitoring_prometheus_remote_write_url = "http://kps-monitoring-prometheus.${local.monitoring_namespace}.svc.cluster.local:9090/api/v1/write"
  monitoring_tempo_otlp_endpoint         = "http://monitoring-tempo.${local.monitoring_namespace}.svc.cluster.local:4317"

  # Shared Gateway API gateway from tranzr-gitops (gatewayApi.gateway).
  monitoring_gateway = {
    name      = "tranzr-gateway"
    namespace = "tranzr-moves-system"
  }

  monitoring_gateway_routes = {
    grafana = {
      hostname    = "grafana.tranzzer.com"
      serviceName = "monitoring-grafana"
      servicePort = 80
    }
    prometheus = {
      hostname    = "prometheus.tranzzer.com"
      serviceName = "kps-monitoring-prometheus"
      servicePort = 9090
    }
    alertmanager = {
      hostname    = "alertmanager.tranzzer.com"
      serviceName = "kps-monitoring-alertmanager"
      servicePort = 9093
    }
  }
}
