---
name: deploy-meru-workloads
description: >-
  Create, start, list, and delete user workloads / resources on a running local
  one-node Meru cluster: vnets, vnics (NICs), ingresses, images, virtual machines,
  and block-device volumes. Use this skill when the user wants to "create a VM",
  "deploy a VM with N cpu", "add an ingress", "create a NIC/vnet/image/volume",
  "deploy a cluster with a VM and an ingress", "deploy a VM with a block-device
  volume", or tear those resources down. It generates parameterized resource
  definitions (matching the shared MnM/testbed shapes) and drives
  `meructl resource create/start/stop/delete` with the correct type/provider. VM
  images can come from a LOCAL file:// qcow2 (default) or a REMOTE http(s) image
  server (`--local` / `--remote`), and it diagnoses source problems for both. It
  can also "produce/build a local VM image" via the Prefab Image Toolset (the
  `prefab-image` subcommand). Requires the resource providers to be deployed first (use `deploy-meru-resource-providers`); for VMs/NICs/ingresses the
  `network` and `compute` providers must be deployed, and for volumes the `volume`
  provider.
---

# deploy-meru-workloads

Creates and manages user resources on a running local one-node cluster. Resource
YAMLs are generated (parameterized) and applied with
`meructl resource create` + `meructl resource start`, using the type/provider
pairs reported by `meructl resource types`.

## Prerequisites

- Bare cluster (`deploy-meru-cluster`), core managers (`deploy-meru-core-managers`), and
  the relevant resource providers (`deploy-meru-resource-providers`) are deployed and
  READY. For a VM + ingress you need at least `network`, `compute`, and `image`.

## Type / provider pairs

| Resource | type | provider |
| -------- | ---- | -------- |
| local storage (static backend) | `local_storage` | `local_storage_provider` |
| vm instance (static backend) | `virtual_machine_instance` | `virtual_machine_instance_provider` |
| vnet | `vnet` | `vnet_provider` |
| NIC | `vnic` | `vnic_provider` |
| ingress | `ingress` | `ingress_provider` |
| image | `image` | `image_resource_plugin` |
| VM | `virtualmachine` | `virtualmachine_provider` |
| volume | `volume` | `csi_provider` |

## Static backends

The MRI-v2 model requires prerequisite **static backend** resources before a VM can
be placed (mirrors the original `create_static_resources.sh`): a `local_storage`
backend, a `virtual_machine_instance` backend, and a `vnet`. Create them with:

```bash
"$SKILL" static-backends [--vnet test_vnet]   # local_storage + vm-instance + vnet
# or individually:
"$SKILL" local-storage [name]
"$SKILL" vm-instance   [name]
```

`vm-with-ingress` creates `local_storage` + `vm-instance` automatically (pass
`--skip-backends` if they already exist).

## Usage

```bash
SKILL=~/.copilot/skills/deploy-meru-workloads/create_workload.sh

# Prerequisite static backends (local_storage + vm-instance + vnet):
"$SKILL" static-backends

# Individual resources (each does create + start):
"$SKILL" vnet test_vnet [--subnet 192.168.10.0/24] [--gateway 192.168.10.1]
"$SKILL" nic ip1 --vnet test_vnet [--ingress test_ingress]
"$SKILL" ingress test_ingress --vnet test_vnet --nic ip1
"$SKILL" image ubuntu_image [--local | --remote | --url <file://…|http(s)://…>]
"$SKILL" vm vm1 --nic ip1 --image ubuntu_image --cpu 2 --mem-mib 2048 [--volume vol1]
"$SKILL" volume vol1 [--size-mib 4096]

# One-shot VM scenarios (each creates static backends first; --skip-backends to skip):
# Use --skip-vnet / --skip-image to reuse an existing shared vnet / image.
"$SKILL" vm-basic       --name vm1    --cpu 2 --mem-mib 2048 [--local|--remote] [--skip-backends|--skip-vnet|--skip-image]
"$SKILL" vm-with-ingress --name vm1   --cpu 2 --mem-mib 2048 [--local|--remote] [--skip-backends|--skip-vnet|--skip-image]
"$SKILL" vm-with-volume  --name vm1_bd --cpu 2 --mem-mib 2048 --size-mib 4096 [--local|--remote] [--skip-backends|--skip-vnet|--skip-image]

# Produce the local OS image (see "Producing a local image" below):
"$SKILL" prefab-image --output /var/lib/meru/images/ubuntu.qcow2

# Inspect / tear down:
"$SKILL" list --type vnic --provider vnic_provider
"$SKILL" delete vm1 --type virtualmachine --provider virtualmachine_provider
```

The three one-shot VM scenarios mirror the testbed flows:
- `vm-basic` -> `create_and_start_vm_ip1_ubuntu.sh` (plain VM, no ingress).
- `vm-with-ingress` -> plain VM + an ingress anchored on the nic.
- `vm-with-volume` -> `create_and_start_vm_ip1_ubuntu_test_bd_volume.sh` (VM with a
  block-device CSI volume; needs the `volume` resource provider).

Each orchestrates: static backends (local_storage + vm-instance) -> vnet -> nic
[-> ingress] -> image [-> volume] -> VM. Pass `--skip-backends` to skip the
static-backend step, `--skip-vnet` to reuse an existing vnet, and `--skip-image`
to reuse an existing image (useful against an already-populated cluster: the
shared `local_storage`/`virtual_machine_instance` backends and `test_vnet`
typically already exist, and arbitrarily-named `local_storage` backends fail to
start without host-configured backing storage).

## Operation-failure detection

`meructl` **exits 0 even when a resource operation's status is `Failed`** (the
failure is only in the response body). The skill inspects each create/start
response and aborts (non-zero) on a `Failed` status or a populated
`error_description`, so a failed VM is reported instead of a false "complete".
Verified end-to-end: a VM create failing binding validation is now surfaced as
`[meru][ERROR] create of virtualmachine '<name>' failed`.

## VM os_volume `linux_profile` (required by current bits)

Generated VMs include `linux_profile: {}` on the `os_volume`. Current compute
bits **require** the os_volume to set either `linux_profile` or `windows_profile`
(binding validation fails with "OS volume must have either a linux_profile or
windows_profile set" otherwise). Note the older testbed `vm_mriv2_ip1.yaml` omits
this and would fail on current bits. For SSH provisioning, extend `linux_profile`
with `user_profiles` (username + `ssh_public_keys_base64`), as in the compute
`cogs_vm.yaml` / `vm_reliable_os.yaml` templates.

## VM image: LOCAL vs REMOTE

`image` (and the one-shot scenarios) support two image sources:

| Option | Source | When to use |
| ------ | ------ | ----------- |
| `--local` (default) | `file://` qcow2 (`MERU_IMAGE_URL` / `MERU_IMAGE_PATH`, default `/var/lib/meru/images/ubuntu.qcow2`) | Offline / no corp network. Build one with `prefab-image`. |
| `--remote` | http(s) image server (`MERU_REMOTE_IMAGE_URL`, default the internal **meruperi** server the testbed used) | On corp network / VPN; matches the testbed `ubuntu_image.yaml`. |
| `--url URL` | explicit `file://` or `http(s)://` | Any custom location. |

`create image` pre-flights the source and prints diagnosis hints (it warns, never
fails):
- **Local**: missing file -> build with `prefab-image` or pass `--url`; unreadable
  -> fix perms so the cluster user (`meruuser`) can read it.
- **Remote**: unreachable -> check corp network/VPN, DNS + port (`curl -I <url>`),
  whether the image tag still exists, and that the **cluster node** (not just your
  shell) can reach the server; otherwise switch to `--local`.


## Producing a local image

The default VM image is a local `file://` qcow2 (see caveats). The meru build does
NOT bake a ready OS image; instead it builds the **VM guest agents** and packages
the **Prefab Image Toolset (PIT)** as `prefab_image_toolset.tar.gz` (a release
artifact, alongside the other packages). To produce a deployable image you run the
PIT against a stock base cloud image: it embeds the meru guest agents
(heartbeat/provisioning) into the rootfs and writes a `*.qcow2`.

The `prefab-image` subcommand wraps this:

```bash
# Produce the default local image from the default Ubuntu 22.04 base cloud image:
"$SKILL" prefab-image
# -> finds prefab_image_toolset*.tar.gz in the local-dir (MERU_LOCAL_DIR,
#    default ~/latest-release-packages), downloads the base image, runs the PIT
#    as root, and writes /var/lib/meru/images/ubuntu.qcow2

# From a base image you already have (no internet needed):
"$SKILL" prefab-image --base /tmp/ubuntu-22.04-server-cloudimg-amd64.img \
    --output /var/lib/meru/images/ubuntu.qcow2

# Point at a specific toolset (extracted dir or the tar) and forward extra PIT args:
"$SKILL" prefab-image --toolset /path/to/prefab_image_toolset.tar.gz -- --include-guest-dca
```

Options: `--output PATH` (default = the local `file://` image path),
`--base IMG|URL` (default = `MERU_BASE_IMAGE_URL` or the upstream Ubuntu 22.04
cloudimg), `--toolset DIR|TAR` (default = `prefab_image_toolset*.tar.gz` in the
local-dir), `--os-type linux|windows` (default `linux`), and `-- EXTRA` to forward
remaining args to `prefab-image.sh` (e.g. `--include-ti-guest-dca`).

Notes:
- Runs `prefab-image.sh` as **root** (it mounts/chroots the image rootfs).
- The base image is a stock cloud image (e.g. Ubuntu cloudimg); only this base
  pull touches the internet — pass a local `--base` to avoid it.
- Place the output where the cluster user (`meruuser`) can read it (e.g.
  `/var/lib/meru/images/`), then create it with
  `image <name> --url file://<output>` or just rely on the default.

## Notes & caveats

- Defaults: vnet=`test_vnet`, nic=`ip1`, ingress=`test_ingress`,
  image=`ubuntu_image`, vm=`vm1`, cpu=`2`, mem-mib=`2048`, os-mib=`4096`.
- **Host setup required for some resources.** Creating networking resources
  (vnet/vnic/ingress) requires the host's CNI/networking to be configured for
  Meru; if the net resource-provider controller is deployed (READY) but its RPCs
  time out with `DEADLINE_EXCEEDED` / "downstream duration timeout", the host
  networking is not set up — this is an environment issue, not a resource-spec
  issue. Non-network resources (e.g. `local_storage`) work without that setup.
- **VM OS image (local by default, no cloud dependency).** The default image URL
  is a local `file://` path: `file://${MERU_IMAGE_PATH}` where `MERU_IMAGE_PATH`
  defaults to `/var/lib/meru/images/ubuntu.qcow2`. Place a qcow2 image there
  (readable by the cluster user) — produce one with the `prefab-image` subcommand
  (see "Producing a local image") — or override with the `MERU_IMAGE_PATH` /
  `MERU_IMAGE_URL` env vars or the `--url` / `--image-url` flag. `create image`
  warns (does not fail) if a `file://` path is missing. To pull from a remote
  server instead, pass an `http(s)://` URL. A working hypervisor (CHV/QEMU + KVM)
  is still needed for the guest to actually boot; resource *creation* may succeed
  even where the guest cannot fully start in a constrained environment.
- Block-device `volume` resources additionally require the `volume` provider and
  chibd host/kernel setup.
