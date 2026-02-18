data "terraform_remote_state" "infra" {
  backend = "azurerm"

  config = {
    resource_group_name  = "tranzr-move-rg"
    storage_account_name = "tranzrmovessa"
    container_name       = "tranzr-infra-tfstate"
    key                  = "infra.tfstate"
  }
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
      echo "Gateway API CRDs applied."
    EOT
  }

  depends_on = [data.terraform_remote_state.infra]
}


# https://medium.com/@vvimal44/set-up-k3s-with-cilium-as-core-networking-0ea110210592
# https://www.reddit.com/r/MaksIT/comments/1op8mtm/almalinux_10_singlenode_k3s_install_script_with/
# https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/

# Cilium CNI - must be installed early, right after CCM
# https://docs.cilium.io/en/stable/installation/k8s-install-helm/

# https://blogs.learningdevops.com/the-complete-guide-to-setting-up-cilium-on-k3s-with-kubernetes-gateway-api-8f78adcddb4d
resource "helm_release" "cilium" {
  name       = local.ciliumSettings.name
  repository = local.ciliumSettings.repository
  chart      = local.ciliumSettings.name
  version    = local.ciliumSettings.chart_version
  namespace  = local.ciliumSettings.namespace

  create_namespace = true
  wait             = true
  timeout          = 1200 # 20 min so Cilium can come up before CCM/CSI; avoids state/release mismatch on slow clusters

  set = [{
    name  = "ipam.operator.clusterPoolIPv4PodCIDRList[0]"
    value = local.ciliumSettings.podCIDR
  },
  {
    name  = "operator.replicas"
    value = 1
  },
  {
    name  = "kubeProxyReplacement"
    value = "true"
  },
  {
    name = "k8sServiceHost"
    value = data.terraform_remote_state.infra.outputs.master_private_ip
  },
  {
    name = "k8sServicePort"
    value = "6443"
  },
  {
    name = "gatewayAPI.enabled"
    value = "true"
  },
  {
    name = "debug.enabled"
    value = "true"
  },
  {
    name = "l2Announce.enabled"
    value = "true"
  },
  {
    name = "externalIPs.enabled"
    value = "true"
  },
  # https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#external-access-to-clusterip-services
  # {
  #   name = "bpf.lbExternalClusterIP"
  #   value = "true"
  # },
  # k3s reads CNI from its own dirs; Cilium default is /etc/cni/net.d → nodes stay NotReady without this
  # {
  #   name  = "cni.confPath"
  #   value = "/var/lib/rancher/k3s/agent/etc/cni/net.d"
  # },
  # {
  #   name  = "cni.binPath"
  #   value = "/var/lib/rancher/k3s/data/current/bin"
  # }
  ]
  depends_on = [data.terraform_remote_state.infra, terraform_data.gateway_api_crds]
}


# Secret for CCM
resource "kubernetes_secret_v1" "hcloud_token_secret" {
  metadata { 
    name = "hcloud"
    namespace = local.hetznerCloudSettings.namespace 
    }

  data     = {
    token = var.hcloud_token
    network = data.terraform_remote_state.infra.outputs.network_id
  }

  type     = "Opaque"
}

resource "helm_release" "hcloud_ccm" {
  name       = "hcloud-ccm"
  repository = local.hetznerCloudSettings.repository
  chart      = "hcloud-cloud-controller-manager"
  namespace  = local.hetznerCloudSettings.namespace
  version = local.hetznerCloudSettings.ccm_version

  set = [
    {
      name  = "networking.enabled"
      value = "true"
    },
    {
      name  = "networking.clusterCIDR"
      value = data.terraform_remote_state.infra.outputs.network_subnet_cidr
    }
  ]

  depends_on = [helm_release.cilium, kubernetes_secret_v1.hcloud_token_secret]
}


# CSI driver + secret
# StorageClass "hcloud-volumes" is created by the hcloud-csi Helm chart; do not create it here or you get "already exists"
resource "helm_release" "hcloud_csi" {
  name       = "hcloud-csi"
  repository = local.hetznerCloudSettings.repository
  chart      = "hcloud-csi"
  namespace  = local.hetznerCloudSettings.namespace
  version = local.hetznerCloudSettings.hcloud_csi_version

  wait = true
  wait_for_jobs = true
  timeout = 600
  depends_on = [helm_release.cilium, helm_release.hcloud_ccm]
}

# Is this needed?
# resource "kubernetes_secret_v1" "hcloud_csi_token_secret" {
#   metadata { 
#     name = "hcloud-csi-token-secret"
#     namespace = local.hetznerCloudSettings.namespace
#     }

#   data     = { hcloud-token = var.hcloud_token }
#   type     = "Opaque"
#   depends_on = [helm_release.cilium, helm_release.hcloud_ccm, helm_release.hcloud_csi]
# }


resource "helm_release" "ingress_nginx" {
  name       = local.ingressNginxSettings.name
  repository = local.ingressNginxSettings.repository
  chart      = local.ingressNginxSettings.name
  version    = local.ingressNginxSettings.chart_version

  wait = true

  namespace        = local.ingressNginxSettings.namespace
  create_namespace = true
  values           = [file("${path.module}/values/ingress-nginx/values.yaml")]
  depends_on       = [helm_release.hcloud_ccm]
}


# Allow API server -> cert-manager webhook so startupapicheck and webhook validation don't time out.
# Cilium can drop this traffic unless explicitly allowed (kube-apiserver entity).
# Use provisioner to wait for Cilium CRDs to be available before applying the policy.
resource "terraform_data" "cilium_allow_apiserver_to_cert_manager_webhook" {
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
      
      # Wait for CiliumClusterwideNetworkPolicy CRD to be available (up to 5 minutes)
      echo "Waiting for CiliumClusterwideNetworkPolicy CRD to be available..."
      for i in {1..60}; do
        if kubectl get crd ciliumclusterwidenetworkpolicies.cilium.io >/dev/null 2>&1; then
          echo "CiliumClusterwideNetworkPolicy CRD found."
          break
        fi
        if [ $i -eq 60 ]; then
          echo "Timeout waiting for CiliumClusterwideNetworkPolicy CRD"
          exit 1
        fi
        echo "Attempt $i/60: CRD not ready yet, waiting 5 seconds..."
        sleep 5
      done
      
      # Apply the Cilium policy manifest
      kubectl apply -f ${path.module}/manifests/cilium-allow-apiserver-to-cert-manager-webhook.yaml
      echo "Cilium policy applied successfully."
    EOT
  }

  depends_on = [helm_release.cilium]
  
  # Trigger re-run if the manifest file changes
  input = filemd5("${path.module}/manifests/cilium-allow-apiserver-to-cert-manager-webhook.yaml")
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

  wait           = true
  timeout        = 900 # allow startupapicheck job to complete (job --wait=10m; 15 min covers one full attempt + buffer)
  wait_for_jobs  = true

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]

  depends_on = [helm_release.hcloud_ccm, terraform_data.cilium_allow_apiserver_to_cert_manager_webhook]
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
  depends_on = [helm_release.hcloud_ccm]
}


resource "helm_release" "cloudnative-pg-operator" {
  name             = local.cloudNativePGSettings.name
  repository       = local.cloudNativePGSettings.repository
  chart            = local.cloudNativePGSettings.name
  version          = local.cloudNativePGSettings.chart_version
  namespace        = local.cloudNativePGSettings.namespace
  create_namespace = true

  wait = true
  depends_on = [helm_release.hcloud_ccm]
}

