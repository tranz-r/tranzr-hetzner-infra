# Namespace stays TF-managed here (same pattern as redis). Operator is installed in crds/
# so RabbitmqCluster CRDs exist before this stack plans/applies.

resource "kubernetes_namespace_v1" "rabbitmq_system" {
  metadata {
    name = "rabbitmq-system"
  }
}

resource "null_resource" "wait_for_rabbitmq_cluster_operator_crds" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
    command = <<EOT
      echo "Using kubeconfig: ${var.kubeconfig_path}"
      if [ ! -f "${var.kubeconfig_path}" ]; then
        echo "Error: kubeconfig file not found at ${var.kubeconfig_path}"
        exit 1
      fi
      echo "Waiting for rabbitmq-cluster-operator CRDs to become available..."
      for i in {1..30}; do
        if kubectl get crd rabbitmqclusters.rabbitmq.com >/dev/null 2>&1; then
          echo "rabbitmq-cluster-operator CRDs ready."
          exit 0
        fi
        echo "CRDs not ready yet, waiting..."
        sleep 20
      done
      echo "Timeout waiting for rabbitmq-cluster-operator CRDs"
      exit 1
    EOT
  }
}

# Operator-shaped secret: username, password, default_user.conf, .erlang.cookie
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
        template = {
          engineVersion = "v2"
          data = {
            username            = "admin"
            password            = "{{ .password }}"
            ".erlang.cookie"    = "{{ .erlangcookie }}"
            "default_user.conf" = "default_user = admin\ndefault_pass = {{ .password }}\n"
          }
        }
      }
      data = [
        {
          secretKey = "password"
          remoteRef = {
            key = "platform-rabbitmq-password"
          }
        },
        {
          secretKey = "erlangcookie"
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

resource "kubernetes_manifest" "rabbitmq_cluster" {
  manifest = {
    apiVersion = "rabbitmq.com/v1beta1"
    kind       = "RabbitmqCluster"
    metadata = {
      name      = "rabbitmq"
      namespace = kubernetes_namespace_v1.rabbitmq_system.metadata[0].name
    }
    spec = {
      replicas = 3
      # Required when operator chart leaves ENABLE_WEBHOOKS=false.
      image = "docker.io/library/rabbitmq:4.3.4-management-alpine"
      persistence = {
        storage          = "5Gi"
        storageClassName = "hcloud-volumes"
      }
      resources = {
        requests = {
          cpu    = "250m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
      secretBackend = {
        externalSecret = {
          name = "rabbitmq-credentials"
        }
      }
      # https://www.rabbitmq.com/docs/vhosts#node-wide-default-queue-type-node-wide-dqt
      rabbitmq = {
        additionalConfig = <<-EOT
          default_queue_type = quorum
          quorum_queue.property_equivalence.relaxed_checks_on_redeclaration = true
        EOT
      }
    }
  }

  depends_on = [
    null_resource.wait_for_rabbitmq_cluster_operator_crds,
    kubernetes_manifest.rabbitmq_credentials_external_secret,
  ]
}
