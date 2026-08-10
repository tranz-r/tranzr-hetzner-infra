# Hetzner k3s Cluster via Terraform + GitHub Actions

This repository provisions a production-ready k3s cluster on Hetzner Cloud using the [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner) Terraform module, deployed via GitHub Actions with Azure Storage for remote state.

## Architecture

The cluster is provisioned in stages:

1. **infra-kube-hetzner** - Provisions the cluster infrastructure using the kube-hetzner module
2. **crds** - Installs Gateway API CRDs and core operators
3. **resources** - Configures cert-manager ClusterIssuers and Azure Key Vault integration

## Repository Structure

```
hetzner-k3s/
├── infra-kube-hetzner/          # Cluster infrastructure (kube-hetzner module)
│   ├── kube.tf                  # Main module configuration
│   ├── variables.tf              # Input variables
│   ├── providers.tf             # Terraform providers & Azure backend
│   ├── output.tf                # kubeconfig output
│   ├── hcloud-microos-snapshots.pkr.hcl  # Packer template for MicroOS images
│   └── README.md                # Setup instructions for MicroOS images
├── crds/                        # Gateway API CRDs and operators
│   ├── main.tf                  # Gateway API CRDs, external-secrets, CloudNativePG, rabbitmq-cluster-operator
│   ├── variables.tf
│   ├── providers.tf             # Azure backend + Kubernetes providers
│   └── local.tf                 # Local settings
├── resources/                   # cert-manager and Azure Key Vault resources
│   ├── main.tf                  # ClusterIssuers, ClusterSecretStore, Nginx Gateway Fabric
│   ├── redis.tf                 # Platform Redis
│   ├── rabbitmq.tf              # Platform RabbitMQ (ExternalSecret + RabbitmqCluster; operator in crds/)
│   ├── monitoring.tf              # LGTM+P namespace, Grafana secret, Alloy ConfigMap
│   ├── monitoring-gateway-routes.tf # HTTPRoute → tranzr-gateway (no Ingress on Hetzner)
│   ├── monitoring-*.tf            # helm_release: KPS, Grafana, Loki, Tempo, Alloy
│   ├── variables.tf
│   ├── providers.tf             # Azure backend + Kubernetes providers
│   └── local.tf                 # Local settings
└── .github/workflows/
    └── terraform-infra.yml      # CI/CD pipeline
```

## Cluster Configuration

### Infrastructure (infra-kube-hetzner)

- **CNI**: Cilium (native routing, kube-proxy replacement enabled)
- **Control Plane**: 1 node (non-HA)
- **Agent Nodes**: 1 node (fixed)
- **Autoscaler**: 1-3 nodes (dynamic scaling)
- **Ingress**: Nginx Ingress Controller
- **Storage**: Hetzner CSI (hcloud-volumes StorageClass)
- **Cloud Controller**: Hetzner CCM (via Helm)
- **cert-manager**: Enabled with Gateway API support
- **OS**: OpenSUSE MicroOS (immutable, auto-updates enabled)
- **k3s**: Latest channel, auto-upgrades enabled

### Components Installed

**By kube-hetzner module:**
- k3s (latest)
- Cilium CNI (v1.19.1)
- Hetzner CCM (v1.28.0)
- Hetzner CSI (v2.18.0)
- cert-manager (v1.19.3)
- Nginx Ingress Controller
- Metrics Server
- Kured (automatic reboots)

**By crds/ Terraform:**
- Gateway API CRDs
- external-secrets-operator
- CloudNativePG operator
- rabbitmq-cluster-operator (CRDs + controllers in `rabbitmq-system`)

**By resources/ Terraform:**
- cert-manager ClusterIssuers (Let's Encrypt staging & production)
- Azure Key Vault ClusterSecretStore (for external-secrets)
- Nginx Gateway Fabric (v2.3.0)
- Platform Redis (`redis-system`) and RabbitMQ instance (`RabbitmqCluster` in `rabbitmq-system`; operator installed in crds/)
- **LGTM+P monitoring** (`monitoring-system`): remote `helm_release` charts (KPS, Grafana, Loki, Tempo, Alloy) with `yamlencode` values like Redis/RabbitMQ; **app-focused** (no kubelet/kube-state-metrics/node-exporter; OTLP + opt-in `prometheus-scrape: "true"` ServiceMonitors); external URLs via **Gateway API** `HTTPRoute` → shared `tranzr-gateway` in `tranzr-moves` (no Ingress); Alloy OTLP at `monitoring-alloy.monitoring-system:4317`; public Faro ingest at `https://faro.tranzzer.com` (port `12347`)

**AKV prerequisites for monitoring:** `tranzr-grafana-admin-user`, `tranzr-grafana-admin-password`

**AKV prerequisites for platform RabbitMQ:** `platform-rabbitmq-password`, `platform-rabbitmq-erlang-cookie` (operator-shaped secret `rabbitmq-credentials` in `rabbitmq-system`)

### Platform RabbitMQ (operator cluster)

- **Operator:** CloudPirates `rabbitmq-cluster-operator` `0.5.5` in `crds/` (`rabbitmq-system`)
- **Instance:** `RabbitmqCluster` `rabbitmq` in `resources/rabbitmq.tf` — 3 replicas, image `rabbitmq:4.3.4-management-alpine`, storage `hcloud-volumes`, node-wide quorum DQT
- **Client DNS:** `rabbitmq.rabbitmq-system.svc.cluster.local:5672` (apps in tranzr-gitops)
- **Namespace:** still TF-managed in `resources/` (same pattern as Redis); do not remove it from state when installing the operator

Cutover from the old standalone CloudPirates Helm chart (`rabbitmq` 0.21.4) must destroy that release **before** applying the `RabbitmqCluster` (Service name `rabbitmq` collides otherwise). Orphan PVC `data-rabbitmq-0` can be deleted after cutover.

**Hetzner production URLs** (Gateway API via `tranzr-gateway`, TLS from wildcard `*.tranzr.co.uk` cert):

- Grafana: https://grafana.tranzr.co.uk
- Prometheus: https://prometheus.tranzr.co.uk
- Alertmanager: https://alertmanager.tranzr.co.uk

Requires `tranzr-gateway` in `tranzr-moves` (deployed by tranzr-gitops `gatewayApi.enabled`).

**In-cluster OTLP endpoint for Tranzr apps:** `http://monitoring-alloy.monitoring-system.svc.cluster.local:4317`

**Public Faro (Drivers PWA / browser RUM):** `https://faro.tranzzer.com` → Alloy `faro.receiver` on Service port `12347`. Create Cloudflare DNS `faro.tranzzer.com` (A/CNAME) to the same LB as `grafana.tranzzer.com` if not covered by an existing wildcard.

## Prerequisites

### 1. MicroOS Images

Before the first Terraform apply, you must create MicroOS snapshots in your Hetzner project:

```bash
cd infra-kube-hetzner
packer build -var "hcloud_token=$HCLOUD_TOKEN" hcloud-microos-snapshots.pkr.hcl
```

After building, get the image IDs:
```bash
hcloud image list --selector microos-snapshot=yes
```

Then set them as GitHub Variables (or Terraform variables):
- `TF_VAR_microos_x86_snapshot_id=<x86-image-id>`
- `TF_VAR_microos_arm_snapshot_id=<arm-image-id>` (only if using ARM node types)

See `infra-kube-hetzner/README.md` for details.

### 2. GitHub Secrets & Variables

Create these in **Settings → Secrets and variables → Actions**:

**Secrets:**
- `HETZNER_API_TOKEN` - Hetzner Cloud API token (Read & Write)
- `SSH_PUBLIC_KEY` - Contents of your SSH public key (`~/.ssh/id_ed25519.pub`)
- `SSH_PRIVATE_KEY` - Contents of your SSH private key (`~/.ssh/id_ed25519`)
- `AZURE_CREDENTIALS` - JSON with `clientId`, `clientSecret`, `tenantId`, `subscriptionId`
- `LETSENCRYPT_EMAIL` - Email for Let's Encrypt ACME registration
- `TRANZR_CLOUDFLARE_API_TOKEN_KEY` - Cloudflare API token for DNS-01 challenges
- `AZURE_SERVICE_PRINCIPAL_CLIENT_ID` - Azure SP client ID for Key Vault access
- `AZURE_SERVICE_PRINCIPAL_CLIENT_SECRET` - Azure SP client secret

**Variables (Repository or Environment `production`):**
- `TRANZR_DNS_ZONE` - DNS zone for cert-manager DNS-01 challenges (e.g., `example.com`)
- `AZURE_SERVICE_PRINCIPAL_TENANT_ID` - Azure tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID
- `AZURE_KEY_VAULT_URL` - Azure Key Vault URL (e.g., `https://vault.vault.azure.net/`)

**Azure Storage Backend** (configured in `providers.tf`):
- Resource Group: `tranzr-move-rg`
- Storage Account: `tranzrmovessa`
- Container: `tranzr-infra-tfstate`
- State keys: `infra-kube-hetzner.tfstate`, `crds.tfstate`, `resources.tfstate`

## Usage

### Deploy Cluster

1. **Build MicroOS images** (one-time setup):
   ```bash
   cd infra-kube-hetzner
   packer build -var "hcloud_token=$HCLOUD_TOKEN" hcloud-microos-snapshots.pkr.hcl
   ```

2. **Set image IDs** as GitHub Variables (see Prerequisites).

3. **Trigger workflow**:
   - Push to `main` branch, or
   - Go to **Actions → Provision Hetzner Cluster Infra → Run workflow**

The workflow runs three jobs sequentially:
- `hetzner-infra-deployment` - Creates cluster infrastructure
- `kubernetes-addons-deployment` (crds) - Installs Gateway API CRDs and operators
- `kubernetes-resources-deployment` (resources) - Configures cert-manager and Azure integration

### Access Cluster

After deployment, download the kubeconfig artifact from the workflow run, or:

```bash
cd infra-kube-hetzner
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
```

### Destroy Cluster

Use the workflow with `destroy: true` input, or run locally:

```bash
cd resources && terraform destroy -auto-approve
cd ../crds && terraform destroy -auto-approve
cd ../infra-kube-hetzner && terraform destroy -auto-approve
```

## Key Features

- **Cilium CNI** with native routing and kube-proxy replacement
- **Automatic scaling** via Cluster Autoscaler (1-3 agent nodes)
- **cert-manager** with Let's Encrypt (staging & production ClusterIssuers)
- **Gateway API** support (CRDs + Nginx Gateway Fabric)
- **External Secrets** integration with Azure Key Vault
- **CloudNativePG** operator for PostgreSQL management
- **Automatic OS & k3s upgrades** via kured and system-upgrade-controller
- **Immutable OS** (MicroOS) with automatic rollback on failed updates

## Network Architecture

- **Private Network**: Created automatically by kube-hetzner (`10.0.0.0/8`)
- **Pod CIDR**: `10.42.0.0/16` (Cilium)
- **Service CIDR**: `10.43.0.0/16`
- **Load Balancer**: Hetzner LB for ingress (managed by CCM)

## Storage

- **Default StorageClass**: `hcloud-volumes` (Hetzner Cloud Volumes)
- **CSI Driver**: Hetzner CSI (v2.18.0) - installed by kube-hetzner module

## DNS & Certificates

- **DNS Servers**: `1.1.1.1`, `8.8.8.8`, `2606:4700:4700::1111`
- **cert-manager**: Let's Encrypt via DNS-01 (Cloudflare)
- **ClusterIssuers**: `tranzr-letsencrypt-staging` and `tranzr-letsencrypt-production`

## Notes

- Control plane nodes **do not** allow pod scheduling by default (`allow_scheduling_on_control_plane = false`)
- Traefik is disabled; ingress is handled by Nginx Ingress Controller
- Gateway API CRDs are installed in `crds/` before operators that depend on them
- cert-manager is installed by the kube-hetzner module; ClusterIssuers are configured in `resources/`

## Troubleshooting

### "no image found matching the selection"

Build MicroOS images with Packer first (see Prerequisites).

### SSH key errors

Ensure `SSH_PRIVATE_KEY` secret contains the full key content (not a path). The workflow uses `TF_VAR_ssh_private_key` to avoid `file()` path issues.

### Gateway API CRDs not found

The `crds/` job installs Gateway API CRDs. Ensure it completes successfully before deploying resources that depend on them.
