data "terraform_remote_state" "infra" {
  backend = "azurerm"

  config = {
    resource_group_name  = "tranzr-move-rg"
    storage_account_name = "tranzrmovessa"
    container_name       = "tranzr-infra-tfstate"
    key                  = "infra.tfstate"
  }
}


# https://medium.com/@vvimal44/set-up-k3s-with-cilium-as-core-networking-0ea110210592
# https://www.reddit.com/r/MaksIT/comments/1op8mtm/almalinux_10_singlenode_k3s_install_script_with/
# https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/

# Cilium CNI - must be installed early, right after CCM
# https://docs.cilium.io/en/stable/installation/k8s-install-helm/
resource "helm_release" "cilium" {
  name       = local.ciliumSettings.name
  repository = local.ciliumSettings.repository
  chart      = local.ciliumSettings.name
  version    = local.ciliumSettings.chart_version
  namespace  = local.ciliumSettings.namespace

  create_namespace = true

  # wait = true

  set = [{
    name  = "ipam.operator.clusterPoolIPv4PodCIDRList[0]"
    value = local.ciliumSettings.podCIDR
  },
  {
    name  = "ipam.mode"
    value = "cluster-pool"
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
  }
  ]
  depends_on = [data.terraform_remote_state.infra]
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

  # values = [yamlencode({
  #   secret = { 
  #     name = kubernetes_secret_v1.hcloud_token_secret.metadata[0].name 
  #     key = "hcloud-token"
  #   }
  # })]
  depends_on = [helm_release.cilium, kubernetes_secret_v1.hcloud_token_secret]
}


# CSI driver + secret
resource "helm_release" "hcloud_csi" {
  name       = "hcloud-csi"
  repository = local.hetznerCloudSettings.repository
  chart      = "hcloud-csi"
  namespace  = local.hetznerCloudSettings.namespace
  version = local.hetznerCloudSettings.hcloud_csi_version
  
  depends_on = [helm_release.cilium, helm_release.hcloud_ccm]
}

# Is this needed?
resource "kubernetes_secret_v1" "hcloud_csi_token_secret" {
  metadata { 
    name = "hcloud-csi-token-secret"
    namespace = local.hetznerCloudSettings.namespace
    }

  data     = { hcloud-token = var.hcloud_token }
  type     = "Opaque"
  depends_on = [helm_release.cilium, helm_release.hcloud_ccm, helm_release.hcloud_csi]
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

  wait = true

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

  wait = true
  # wait             = false
  # timeout          = 300
  # wait_for_jobs    = false
  # atomic           = false

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]

  depends_on = [helm_release.hcloud_ccm]
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

