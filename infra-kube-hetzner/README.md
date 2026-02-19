# infra-kube-hetzner

Terraform config for [kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner) on Hetzner Cloud.

## MicroOS images (required before first apply)

The module expects Hetzner images built from OpenSUSE MicroOS. If you see **"no image found matching the selection"**:

1. **Build the images once** with Packer (from this directory):
   ```bash
   packer build -var "hcloud_token=$HCLOUD_TOKEN" hcloud-microos-snapshots.pkr.hcl
   ```
2. **Get the image IDs**:
   ```bash
   hcloud image list --selector microos-snapshot=yes
   ```
3. **Set them** for Terraform (e.g. in CI as env or in a `.tfvars` file):
   - `TF_VAR_microos_x86_snapshot_id=<id>` (required for x86 nodes)
   - `TF_VAR_microos_arm_snapshot_id=<id>` (only if using ARM agent/control plane types)

Alternatively, if images with label `microos-snapshot=yes` already exist in your project (e.g. from a previous Packer run), the module will use the most recent one and you do not need to set the variables.

## SSH key (CI)

In CI, set **`TF_VAR_ssh_private_key`** to the **content** of the private key (e.g. from a secret). That avoids `file()` and path issues. Optionally you can still use `TF_VAR_ssh_private_key_path` with an absolute path to a key file.
