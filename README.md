# Hetzner k3s Cluster via Terraform + GitHub Actions (Azure Remote State)

This repo provisions a production-ready k3s cluster on Hetzner Cloud using Terraform from GitHub Actions,
stores Terraform state in **Azure Storage**, and installs core addons (Hetzner CCM, CSI, ingress-nginx, cert-manager).

## Structure

```
hetzner-k3s/
├── infra/                 # Terraform for servers/network + k3s via cloud-init
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf       # azurerm backend + providers
│   └── cloudinit/
│       ├── master.yaml.tmpl
│       └── worker.yaml.tmpl
├── addons/                # Terraform (Helm) for CCM, CSI, Ingress, cert-manager
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf       # azurerm backend + providers
│   └── values/
│       ├── ingress-nginx-values.yaml
│       └── cert-manager-values.yaml
└── .github/workflows/
    ├── terraform-infra.yml
    └── terraform-addons.yml
```

## GitHub Secrets & Variables

Create these in **Settings → Secrets and variables → Actions**:

**Secrets**

- `HETZNER_API_TOKEN` – Hetzner Cloud API token
- `SSH_PUBLIC_KEY` – contents of your `~/.ssh/id_ed25519.pub`
- `SSH_PRIVATE_KEY` – contents of your `~/.ssh/id_ed25519`
- `AZURE_STORAGE_KEY` – access key for the Azure Storage Account used by the Terraform backend
- `LETSENCRYPT_EMAIL` – email for Let's Encrypt ACME

**Variables (Repository or Environment `production`)**

- `AZURE_RG_NAME` – resource group of your Storage Account
- `AZURE_STORAGE_ACCOUNT` – name of Storage Account
- `AZURE_STORAGE_CONTAINER` – name of container for TF state (e.g., `tfstate`)
- `AZURE_STATE_KEY_INFRA` – blob key for infra state (e.g., `hetzner/infra.tfstate`)
- `AZURE_STATE_KEY_ADDONS` – blob key for addons state (e.g., `hetzner/addons.tfstate`)

> The workflows request an OIDC token (`id-token: write`) and use **Environment=production**.
> While Hetzner doesn’t yet support native OIDC federation, scoping secrets to an Environment gives you strong controls and is future-proof.

## Usage

1. Commit this project to GitHub.
2. Set all the secrets and variables above.
3. Run **Actions → Provision Hetzner Cluster Infra**.
   - This creates network + VMs and installs k3s via cloud-init.
   - It uploads a `kubeconfig` artifact.
4. Run **Actions → Deploy Kubernetes Addons** (or wait for the workflow_run trigger).
   - This installs Hetzner CCM + CSI + ingress-nginx + cert-manager.
5. Point your DNS (`A` records) at the `EXTERNAL-IP` shown on the `ingress-nginx-controller` Service.

## Notes

- Default image: Ubuntu 24.04 (root login with SSH key).
- Traefik is disabled in k3s; ingress is via `ingress-nginx` Helm chart.
- StorageClass `hcloud-volumes` is set as **default**.
- Increase worker count via `TF_VAR_workers` or variables in code.
- For CloudNativePG and Redis, simply request PVCs; they’ll land on Hetzner Volumes.

## Clean up

- `terraform destroy` from both `addons/` and `infra/` workflows (add a `destroy` job or run locally).

## Initial Hetzner Cloud config

```

#cloud-config
package_update: true
packages: [curl]
runcmd:
  - curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL='${k3s_channel}' K3S_TOKEN='${k3s_token}' INSTALL_K3S_EXEC="server \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --disable-cloud-controller \
    --kubelet-arg cloud-provider=external \
    --disable-kube-proxy \
    --flannel-backend=none \
    --disable-network-policy \
    --write-kubeconfig-mode 0644 \
    --cluster-cidr 10.42.0.0/16 \
    --service-cidr 10.43.0.0/16 \
    --node-name ${node_name}" sh -s -
  - systemctl enable k3s && systemctl restart k3s
```
