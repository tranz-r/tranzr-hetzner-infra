
# Secret for CCM
resource "kubernetes_secret" "hcloud_ccm" {
  metadata { 
    name = "hcloud"
    namespace = local.hetznerCloudSettings.namespace 
    }

  data     = { 
    token = var.hcloud_token 
    }

  type     = "Opaque"
}

resource "helm_release" "hcloud_ccm" {
  name       = "hcloud-ccm"
  repository = local.hetznerCloudSettings.repository
  chart      = "hcloud-cloud-controller-manager"
  namespace  = local.hetznerCloudSettings.namespace
  version = local.hetznerCloudSettings.ccm_version

  values = [yamlencode({
    secret = { name = kubernetes_secret.hcloud_ccm.metadata[0].name }
  })]
  depends_on = [kubernetes_secret.hcloud_ccm]
}

# CSI driver + secret
resource "helm_release" "hcloud_csi" {
  name       = "hcloud-csi"
  repository = local.hetznerCloudSettings.repository
  chart      = "hcloud-csi"
  namespace  = local.hetznerCloudSettings.namespace
  version = local.hetznerCloudSettings.hcloud_csi_version
}

resource "kubernetes_secret" "hcloud_csi" {
  metadata { 
    name = "hcloud-csi"
    namespace = local.hetznerCloudSettings.namespace
  }
  data     = { token = var.hcloud_token }
  type     = "Opaque"
  depends_on = [helm_release.hcloud_csi]
}

# Default StorageClass
resource "kubernetes_storage_class_v1" "hcloud_volumes" {
  metadata {
    name = "hcloud-volumes"
    annotations = { 
      "storageclass.kubernetes.io/is-default-class" = "true" 
      }
  }
  storage_provisioner    = "csi.hetzner.cloud"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = { 
    type = "network-ssd" 
    }
  depends_on = [helm_release.hcloud_csi]
}


resource "helm_release" "ingress_nginx" {
  name       = local.ingressNginxSettings.name
  repository = local.ingressNginxSettings.repository
  chart      = local.ingressNginxSettings.name
  version    = local.ingressNginxSettings.chart_version

  namespace        = local.ingressNginxSettings.namespace
  create_namespace = true
  values           = [file("${path.module}/values/ingress-nginx/values.yaml")]
  depends_on       = [helm_release.hcloud_ccm]
}


resource "helm_release" "cert_manager" {
  name             = local.certManagerSettings.name
  namespace        = local.certManagerSettings.namespace
  create_namespace = true

  repository = local.certManagerSettings.repository
  chart      = local.certManagerSettings.name
  version   = local.certManagerSettings.chart_version

  values = [ 
    file("${path.module}/values/cert-manager/values.yaml") 
    ]

  wait    = true
  timeout = 300

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

resource "null_resource" "wait_for_cert_manager_crds" {
  depends_on = [helm_release.cert_manager]

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
      echo "Waiting for cert-manager CRDs to become available..."
      for i in {1..30}; do
        if kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
          echo "cert-manager CRDs ready."
          exit 0
        fi
        echo "CRDs not ready yet, waiting..."
        sleep 20
      done
      echo "Timeout waiting for cert-manager CRDs"
      exit 1
    EOT
  }
}

resource "kubernetes_secret_v1" "tranzr_cloudflare_token_secret" {
  depends_on = [ kubernetes_secret.hcloud_ccm ]

  metadata {
    name = "tranzr-cloudflare-token-secret"
    namespace = "${local.certManagerSettings.namespace}"
  }

  data = {
    cloudflare-token = var.tranzrCloudflareApiTokenKey
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "tranzr-letsencrypt-staging" {

  manifest = {
    apiVersion = local.clusterIssuerSettings.apiVersion
    kind       = local.clusterIssuerSettings.kind
    metadata = {
      name = local.clusterIssuerSettings.tranzrNameStaging
    }
    spec = {
      acme = {
        server  = local.clusterIssuerSettings.stagingServer
        email   = local.clusterIssuerSettings.email
        privateKeySecretRef = {
          name = local.clusterIssuerSettings.tranzrNameStaging
        }
        solvers = [{
          dns01 = {
            cloudflare = {
              email = local.clusterIssuerSettings.email
              apiTokenSecretRef = {
                name = "tranzr-cloudflare-token-secret"
                key  = "cloudflare-token"
              }
            }
          }
          selector = {
            dnsZones = [var.tranzrDnsZones]
          }
        }]
      }
    }
  }

  depends_on = [kubernetes_secret_v1.tranzr_cloudflare_token_secret, null_resource.wait_for_cert_manager_crds]
}

resource "kubernetes_manifest" "tranzr-letsencrypt-production" {

  manifest = {
    apiVersion = local.clusterIssuerSettings.apiVersion
    kind       = local.clusterIssuerSettings.kind
    metadata = {
      name = local.clusterIssuerSettings.tranzrNameProduction
    }
    spec = {
      acme = {
        server  = local.clusterIssuerSettings.productionServer
        email   = local.clusterIssuerSettings.email
        privateKeySecretRef = {
          name = local.clusterIssuerSettings.tranzrNameProduction
        }
        solvers = [{
          dns01 = {
            cloudflare = {
              email = local.clusterIssuerSettings.email
              apiTokenSecretRef = {
                name = "tranzr-cloudflare-token-secret"
                key  = "cloudflare-token"
              }
            }
          }
          selector = {
            dnsZones = [var.tranzrDnsZones]
          }
        }]
      }
    }
  }

  depends_on = [kubernetes_secret_v1.tranzr_cloudflare_token_secret, null_resource.wait_for_cert_manager_crds]
}

resource "kubernetes_secret_v1" "azure_secret_sp_secret" {
  metadata {
    name      = "azure-secret-sp-secret"
  }

  data = {
    clientId     = var.azureServicePrincipalClientId
    clientSecret = var.azureServicePrincipalClientSecret
  }

  type = "Opaque"
}

resource "helm_release" "external_secrets_operator" {
  name             = local.externalSecretsSettings.name
  namespace        = local.externalSecretsSettings.namespace
  create_namespace = true

  repository = local.externalSecretsSettings.repository
  chart      = local.externalSecretsSettings.name
  version    = local.externalSecretsSettings.chart_version

  set = [{
    name  = "installCRDs"
    value = "true"
  }]

  wait = true
}

resource "null_resource" "wait_for_external_secrets_operator_crds" {
  depends_on = [helm_release.external_secrets_operator]

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
      echo "Waiting for external-secrets-operator CRDs to become available..."
      for i in {1..30}; do
        if kubectl get crd clustersecretstores.external-secrets.io >/dev/null 2>&1; then
          echo "external-secrets-operator CRDs ready."
          exit 0
        fi
        echo "CRDs not ready yet, waiting..."
        sleep 20
      done
      echo "Timeout waiting for external-secrets-operator CRDs"
      exit 1
    EOT
  }
}

resource "kubernetes_manifest" "azure_kv_cluster_store" {

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "azure-kv-cluster-store"
    }
    spec = {
      provider = {
        azurekv = {
          tenantId = var.azureServicePrincipalTenantId
          vaultUrl = var.azureKeyVaultUrl
          authSecretRef = {
            # points to the secret that contains
            # the azure service principal credentials
            clientId = {
              name = kubernetes_secret_v1.azure_secret_sp_secret.metadata[0].name
              key = "clientId"
            }
            clientSecret = {
              name = kubernetes_secret_v1.azure_secret_sp_secret.metadata[0].name
              key = "clientSecret"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret_v1.azure_secret_sp_secret, null_resource.wait_for_external_secrets_operator_crds]
}

resource "helm_release" "cloudnative-pg-operator" {
  name             = local.cloudNativePGSettings.name
  repository       = local.cloudNativePGSettings.repository
  chart            = local.cloudNativePGSettings.name
  version          = local.cloudNativePGSettings.chart_version
  namespace        = local.cloudNativePGSettings.namespace
  create_namespace = true

  wait = true
}

resource "terraform_data" "gateway_api_crds" {
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
      kubectl apply --server-side \
        -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
EOT
  }

  depends_on = [helm_release.hcloud_ccm]
}

resource "null_resource" "wait_for_gateway_api_crds" {
  depends_on = [terraform_data.gateway_api_crds]

  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting for Gateway API CRDs to become available..."
      for i in {1..30}; do
        if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
          echo "Gateway API CRDs ready."
          exit 0
        fi
        echo "CRDs not ready yet, waiting..."
        sleep 20
      done
      echo "Timeout waiting for Gateway API CRDs"
      exit 1
    EOT
  }
}

resource "helm_release" "nginx_gateway_fabric" {
  name       = local.nginxGatewayFabricSettings.name
  repository = local.nginxGatewayFabricSettings.repository
  chart      = local.nginxGatewayFabricSettings.name
  version    = local.nginxGatewayFabricSettings.chart_version

  namespace        = local.nginxGatewayFabricSettings.namespace
  create_namespace = true
  # values           = [file("${path.module}/values/nginx-gateway-fabric/values.yaml")]
  depends_on       = [null_resource.wait_for_gateway_api_crds]
}



