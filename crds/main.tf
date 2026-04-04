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
      kubectl kustomize "https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${var.nginx_gateway_api_version}/deploy/crds.yaml" | kubectl apply --server-side -f -
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

