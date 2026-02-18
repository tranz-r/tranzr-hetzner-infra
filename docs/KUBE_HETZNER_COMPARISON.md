# Comparison: Our Setup vs Kube-Hetzner (cert-manager, Cilium, no kube-proxy)

Reference: [mysticaltech/terraform-hcloud-kube-hetzner](https://github.com/mysticaltech/terraform-hcloud-kube-hetzner) (kube.tf.example and README).

## How Kube-Hetzner Does It

| Aspect | Kube-Hetzner |
|--------|--------------|
| **Architecture** | Single Terraform module: provisions nodes, installs k3s via cloud-init, then applies **kustomize** to deploy Cilium, CCM, cert-manager, Traefik, etc. in one flow. |
| **CNI** | Default: **Flannel**. Optional: `cni_plugin = "cilium"` (or calico). When Cilium is chosen, the module sets `disable_kube_proxy = true` and `disable_network_policy = true` and installs Cilium via the module’s own mechanism (Helm charts / kustomize). |
| **k3s flags** | When Cilium: k3s is started with kube-proxy and default network policy disabled; Flannel is replaced by Cilium. |
| **Cert-manager** | `enable_cert_manager = true` by default. Installed “by Helm behind the scenes” (k3s Helm controller or kustomize), so it comes **after** the cluster and CNI are up. No separate Terraform `helm_release` in user code. |
| **Cilium values** | Configurable via `cilium_values` / `cilium_merge_values`. Example in kube.tf.example uses `kubeProxyReplacement: true`, `routingMode: native`, `ipv4NativeRoutingCIDR`, etc. No explicit cert-manager webhook policy in the example. |
| **API server → webhook** | With **Flannel** (default), control-plane → pod traffic works without extra policy. With **Cilium**, the example doesn’t add a CiliumNetworkPolicy for the cert-manager webhook; they may rely on default-allow or install cert-manager in an order that avoids the issue. |

So in Kube-Hetzner, cert-manager “just works” for most users because either they use **Flannel**, or when they use Cilium the module’s install order and Cilium defaults don’t block API server → webhook.

---

## Our Setup (Tranzr)

| Aspect | Our setup |
|--------|-----------|
| **Architecture** | **Split**: `infra` (Terraform + cloud-init for k3s) and **addons** (separate Terraform that runs later with kubeconfig). Addons: Cilium → CCM → CSI → … → cert-manager via Terraform `helm_release`. |
| **k3s** | We correctly use `--disable-kube-proxy`, `--flannel-backend=none`, `--disable-network-policy` in cloud-init. |
| **Cilium** | Installed via Terraform Helm in addons with `kubeProxyReplacement: true`, `k8sServiceHost`/`k8sServicePort`, `bpf.lbExternalClusterIP`, etc. **Important**: we must set **k3s CNI paths** so k3s sees Cilium’s config (see below). |
| **Cert-manager** | Installed via Terraform `helm_release` after CCM. API server calls the webhook over the Cilium datapath; without an explicit allow, that traffic can be dropped → “context deadline exceeded”. |
| **Fix for webhook** | Add a **CiliumClusterwideNetworkPolicy** allowing ingress from `kube-apiserver` (and optionally `host`) to the cert-manager webhook pods on port 443, and apply it **before** installing cert-manager. |

We are **not** “doing cert-manager wrong”. The difference is:

- **Kube-Hetzner**: One module, default Flannel or Cilium installed in a single flow; cert-manager is often used with Flannel or with Cilium in a configuration that doesn’t block webhook traffic.
- **Us**: Cilium-only, addons applied in a separate step; Cilium can drop API server → webhook unless we explicitly allow it (and we use k3s-specific CNI paths).

---

## Where We Can Go Wrong (Checklist)

1. **Cilium CNI path on k3s**  
   k3s reads CNI from `/var/lib/rancher/k3s/agent/etc/cni/net.d` (and the same path on the server node). Cilium’s default is `/etc/cni/net.d`. If we don’t set Cilium Helm `cni.confPath` and `cni.binPath` to the k3s paths, **nodes can stay NotReady**.  
   **Fix**: In Cilium Helm `set`:  
   - `cni.confPath` = `/var/lib/rancher/k3s/agent/etc/cni/net.d`  
   - `cni.binPath` = `/var/lib/rancher/k3s/data/current/bin`

2. **API server → cert-manager webhook**  
   With Cilium, traffic from the API server (control-plane host) to the webhook pod can be dropped.  
   **Fix**: Apply a CiliumClusterwideNetworkPolicy that allows ingress to the cert-manager webhook from `kube-apiserver` (and optionally `host`) on port 443, and ensure this policy is applied **before** the cert-manager Helm release.

3. **Order of apply**  
   Infra → kubeconfig → addons (Cilium first, then CCM, then policy, then cert-manager). Our dependency chain should reflect that.

4. **bpf.lbExternalClusterIP**  
   This is for **external** access to ClusterIPs (e.g. from outside the cluster). It does **not** fix API server (host) → webhook pod connectivity; that’s a separate path and may require the policy above.

---

## Summary

- **Kube-Hetzner** doesn’t “jump through hoops” in the example because many users stay on **Flannel** or their Cilium + cert-manager install order/defaults don’t hit the webhook timeout.  
- **We** use Cilium only and a split infra/addons flow, so we need:  
  1. **Cilium k3s CNI paths** so the cluster comes up.  
  2. **One Cilium policy** so the API server can reach the cert-manager webhook.  
That’s the minimal set of “extra” steps for our integration (Cilium + cert-manager + no kube-proxy on k3s).
