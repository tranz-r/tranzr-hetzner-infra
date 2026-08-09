resource "terraform_data" "nginx_gateway_api_crds" {
  triggers_replace = [var.nginx_gateway_api_version]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }

    command = <<-EOT
      set -euo pipefail
      test -f "$KUBECONFIG"
      kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v${var.nginx_gateway_api_version}" | kubectl apply --server-side -f -
    EOT
  }
}


resource "terraform_data" "upgrade_nginx_gateway_api_crds" {
  triggers_replace = [var.nginx_gateway_api_version]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }

    command = <<-EOT
    set -euo pipefail
    test -f "$KUBECONFIG"
    kubectl apply --server-side --force-conflicts -f \
      "https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v${var.nginx_gateway_api_version}/deploy/crds.yaml"
  EOT
  }

  depends_on = [terraform_data.nginx_gateway_api_crds]
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


resource "helm_release" "cloudnative-pg-operator" {
  name             = local.cloudNativePGSettings.name
  repository       = local.cloudNativePGSettings.repository
  chart            = local.cloudNativePGSettings.name
  version          = local.cloudNativePGSettings.chart_version
  namespace        = local.cloudNativePGSettings.namespace
  create_namespace = true

  wait = true
}

# Installs RabbitmqCluster CRDs + controllers before resources/ applies RabbitmqCluster CRs.
# Namespace is also owned by resources/ (kubernetes_namespace_v1); create_namespace is safe if it already exists.
resource "helm_release" "rabbitmq_cluster_operator" {
  name             = local.rabbitmqClusterOperatorSettings.name
  repository       = local.rabbitmqClusterOperatorSettings.repository
  chart            = local.rabbitmqClusterOperatorSettings.chart
  version          = local.rabbitmqClusterOperatorSettings.chart_version
  namespace        = local.rabbitmqClusterOperatorSettings.namespace
  create_namespace = true

  wait    = true
  timeout = 300
}

