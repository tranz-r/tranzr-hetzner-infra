resource "helm_release" "kps_monitoring" {
  name       = "kps-monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "80.11.0"
  namespace  = local.monitoring_namespace
  timeout    = 900
  wait       = true

  values = [
    yamlencode({
      fullnameOverride = "kps-monitoring"
      grafana = {
        enabled               = false
        forceDeployDashboards = true
      }

      # Cluster infra scraping disabled — app metrics via OTLP remote_write and opt-in ServiceMonitors.
      kubeApiServer         = { enabled = false }
      kubelet               = { enabled = false }
      kubeControllerManager = { enabled = false }
      kubeScheduler         = { enabled = false }
      kubeProxy             = { enabled = false }
      kubeEtcd              = { enabled = false }
      coreDns               = { enabled = false }
      kubeStateMetrics      = { enabled = false }
      nodeExporter          = { enabled = false }

      defaultRules = {
        create = true
        rules = {
          alertmanager                      = true
          prometheus                        = true
          prometheusOperator                = true
          general                           = true
          configReloaders                   = true
          kubePrometheusGeneral             = true
          kubelet                           = false
          kubeApiserverAvailability         = false
          kubeApiserverBurnrate             = false
          kubeApiserverHistogram            = false
          kubeApiserverSlos                 = false
          kubeControllerManager             = false
          kubeProxy                         = false
          kubeSchedulerAlerting             = false
          kubeSchedulerRecording            = false
          kubeStateMetrics                  = false
          kubernetesApps                    = false
          kubernetesResources               = false
          kubernetesStorage                 = false
          kubernetesSystem                  = false
          k8sContainerCpuUsageSecondsTotal  = false
          k8sContainerMemoryCache           = false
          k8sContainerMemoryRss             = false
          k8sContainerMemorySwap            = false
          k8sContainerResource              = false
          k8sContainerMemoryWorkingSetBytes = false
          k8sPodOwner                       = false
          node                              = false
          nodeExporterAlerting              = false
          nodeExporterRecording             = false
          network                           = false
          etcd                              = false
        }
      }

      prometheus = {
        serviceMonitor = { selfMonitor = false }
        prometheusSpec = {
          replicas                                = 1
          retention                               = "7d"
          retentionSize                           = "45GiB"
          scrapeInterval                          = "60s"
          evaluationInterval                      = "60s"
          enableRemoteWriteReceiver               = true
          serviceMonitorSelectorNilUsesHelmValues = false
          serviceMonitorSelector = {
            matchLabels = {
              (local.monitoring_prometheus_scrape_label) = local.monitoring_prometheus_scrape_value
            }
          }
          podMonitorSelectorNilUsesHelmValues = false
          podMonitorSelector = {
            matchLabels = {
              (local.monitoring_prometheus_scrape_label) = local.monitoring_prometheus_scrape_value
            }
          }
          ruleSelectorNilUsesHelmValues = false
          ruleSelector = {
            matchLabels = {
              release = local.monitoring_prom_label
            }
          }
          resources = {
            requests = { cpu = "200m", memory = "1Gi" }
            limits   = { cpu = "2000m", memory = "4Gi" }
          }
          containers = [
            {
              name = "prometheus"
              startupProbe = {
                failureThreshold = 120
                periodSeconds    = 15
                timeoutSeconds   = 5
                httpGet = {
                  path   = "/-/ready"
                  port   = "http-web"
                  scheme = "HTTP"
                }
              }
            },
          ]
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = local.monitoring_storage_class
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = "80Gi" }
                }
              }
            }
          }
        }
        ingress = {
          enabled = false
        }
      }

      alertmanager = {
        serviceMonitor = { selfMonitor = false }
        alertmanagerSpec = {
          replicas  = 1
          retention = "120h"
          resources = {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
        ingress = {
          enabled = false
        }
      }

      prometheusOperator = {
        serviceMonitor = { selfMonitor = false }
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
    }),
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring_system,
    null_resource.wait_for_cert_manager_crds,
    kubernetes_manifest.azure_kv_cluster_store,
  ]
}
