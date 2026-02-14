# k3s on Hetzner with Terraform and Cilium – What Can Go Wrong

This doc summarizes findings from public setups (e.g. [identiops/terraform-hcloud-k3s](https://identiops.com/terraform-hcloud-k3s/), [Cilium k3s](https://docs.cilium.io/en/stable/installation/k3s/)) and common reasons an installation “doesn’t succeed”.

---

## 1. **Timing: Addons run before k3s is ready**

**Problem:** After `terraform apply` (infra), the workflow immediately fetches kubeconfig and then the addons job runs. The master has just booted; cloud-init (package_update, k3s install, restart) can take 1–3 minutes. So:

- Fetch kubeconfig can run before `/etc/rancher/k3s/k3s.yaml` exists.
- Addons Terraform then uses a missing or stale kubeconfig and Helm fails to talk to the API.

**Fix (applied in this repo):** A **“Wait for k3s master and API”** step was added before “Fetch kubeconfig”: it SSHs to the master and retries until `/etc/rancher/k3s/k3s.yaml` exists and `https://127.0.0.1:6443/healthz` responds (up to ~5 minutes). Only then do we fetch kubeconfig and run addons.

---

## 2. **Cilium not where k3s looks for CNI**

**Problem:** k3s (with `--flannel-backend=none`) expects CNI config in:

- **Config:** `/var/lib/rancher/k3s/agent/etc/cni/net.d`
- **Binaries:** `/var/lib/rancher/k3s/data/current/bin` (or `/var/lib/rancher/k3s/data/cni` on newer k3s)

Cilium Helm defaults are `/etc/cni/net.d` and `/opt/cni/bin`. If you don’t override them, Cilium writes there and k3s never sees a CNI → nodes stay **NotReady**.

**Fix (already in this repo):** In addons Cilium Helm release:

- `cni.confPath = "/var/lib/rancher/k3s/agent/etc/cni/net.d"`
- `cni.binPath = "/var/lib/rancher/k3s/data/current/bin"`

References: [k3s Multus/CNI paths](https://docs.k3s.io/networking/multus-ipams), [k3s issue #10869](https://github.com/k3s-io/k3s/issues/10869).

---

## 3. **Workers joining the wrong API endpoint**

**Problem:** Workers must join the master’s API at an address they can reach. If they use the wrong IP (e.g. public IP while only private network is allowed, or the reverse), join fails or is flaky.

**This repo:** Workers get `master_ip` from `hcloud_server.master.network` (private IP in the Hetzner network). They use `K3S_URL=https://${master_ip}:6443`. Firewall allows 10.20.0.0/16 → all ports. So workers joining via private IP is correct.

---

## 4. **Cilium API endpoint for in-cluster traffic**

**Problem:** Cilium agents on nodes need to reach the Kubernetes API. `k8sServiceHost` / `k8sServicePort` must point to an address that every node can reach.

**This repo:** `k8sServiceHost` is set to `master_private_ip` (from infra remote state), port 6443. Master and workers are on the same 10.20.0.0/24; that’s correct for Hetzner.

---

## 5. **Bootstrap order: Cilium before nodes are Ready**

**Problem:** With Flannel disabled, nodes stay NotReady until a CNI is present. Cilium is that CNI, but it’s installed by addons Terraform. So Cilium must be able to schedule on NotReady nodes.

**Reality:** Cilium DaemonSet has tolerations for `node.kubernetes.io/not-ready`, so it schedules anyway. Once Cilium writes CNI config into the k3s paths (see §2), kubelet sees it and nodes become Ready. No change needed if Cilium paths are correct.

---

## 6. **Optional: stable CNI bin path on k3s upgrades**

**Problem:** `/var/lib/rancher/k3s/data/current/bin` is a symlink that can change on k3s upgrade; custom CNI binaries can “disappear” and break after upgrade.

**Optional fix:** On k3s versions that support it (see [k3s #10869](https://github.com/k3s-io/k3s/issues/10869)), use the stable path:

- `cni.binPath = "/var/lib/rancher/k3s/data/cni"`

You can try this if your k3s release notes mention the static CNI bin dir.

---

## Checklist for “installation not succeeding”

| Check | What to verify |
|-------|----------------|
| Master ready before addons | Workflow has “Wait for k3s master and API” before “Fetch kubeconfig”. |
| Cilium CNI paths | Cilium Helm has `cni.confPath` and `cni.binPath` set to k3s paths. |
| Workers join API | Worker user_data uses master’s **private** IP and firewall allows 6443 from 10.20.0.0/16. |
| Cilium API endpoint | `k8sServiceHost` = master private IP, `k8sServicePort` = 6443. |
| Addons kubeconfig | Fetched **after** wait step; kubeconfig server replaced with master public IP for CI. |

---

## References

- [Cilium – Installation using k3s](https://docs.cilium.io/en/stable/installation/k3s/)
- [Cilium – Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [k3s – Multus and IPAM plugins](https://docs.k3s.io/networking/multus-ipams) (CNI paths)
- [k3s issue #10869 – CNI bin dir](https://github.com/k3s-io/k3s/issues/10869)
- [identiops/terraform-hcloud-k3s](https://identiops.com/terraform-hcloud-k3s/) (Hetzner + k3s + Cilium)
