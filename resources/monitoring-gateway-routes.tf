# Hetzner has no Ingress controller — external access uses Gateway API (nginx-gateway-fabric).
# Routes attach to the shared tranzr-gateway deployed by tranzr-gitops (wildcard *.tranzr.co.uk).

resource "kubernetes_manifest" "monitoring_https_route" {
  for_each = local.monitoring_gateway_routes

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "monitoring-${each.key}-route"
      namespace = local.monitoring_namespace
    }
    spec = {
      parentRefs = [
        {
          name        = local.monitoring_gateway.name
          namespace   = local.monitoring_gateway.namespace
          sectionName = "https"
        },
      ]
      hostnames = [each.value.hostname]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
          backendRefs = [
            {
              name = each.value.serviceName
              port = each.value.servicePort
            },
          ]
        },
      ]
    }
  }

  depends_on = [
    helm_release.nginx_gateway_fabric,
    helm_release.monitoring_grafana,
    helm_release.kps_monitoring,
  ]
}

resource "kubernetes_manifest" "monitoring_http_redirect_route" {
  for_each = local.monitoring_gateway_routes

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "monitoring-${each.key}-http-redirect"
      namespace = local.monitoring_namespace
    }
    spec = {
      parentRefs = [
        {
          name        = local.monitoring_gateway.name
          namespace   = local.monitoring_gateway.namespace
          sectionName = "http"
        },
      ]
      hostnames = [each.value.hostname]
      rules = [
        {
          filters = [
            {
              type = "RequestRedirect"
              requestRedirect = {
                scheme     = "https"
                statusCode = 308
              }
            },
          ]
        },
      ]
    }
  }

  depends_on = [
    helm_release.nginx_gateway_fabric,
  ]
}
