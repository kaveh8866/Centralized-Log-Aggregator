# terraform/ — OCI provisioning (Stage 2)

Infrastructure-as-code for the host that runs the Stage 1 log pipeline.
Written for **OpenTofu 1.6+** and compatible with **Terraform 1.6+**.

OCI is the validated environment (Always Free eligible). The structure keeps the
cloud-specific surface to two thin modules, so an AWS or GCP environment is a
module swap rather than a rewrite — see [Porting to AWS or GCP](#porting-to-aws-or-gcp).

## What gets created

```
Region (e.g. eu-frankfurt-1)
└── VCN 10.0.0.0/16                       oci_core_vcn
    ├── Internet Gateway                  oci_core_internet_gateway
    ├── Route table  0.0.0.0/0 → IGW      oci_core_route_table
    ├── Security list                     oci_core_security_list
    │     ingress TCP 22   ← ssh_allowed_cidr
    │     ingress TCP 3000 ← grafana_allowed_cidr   (Grafana)
    │     ingress TCP 3100 ← loki_allowed_cidr      (Loki — disabled by default)
    │     egress  all     → 0.0.0.0/0
    └── Public subnet 10.0.1.0/24         oci_core_subnet
        └── Instance VM.Standard.A1.Flex  oci_core_instance
              1 OCPU / 6 GB / 50 GB boot, Ubuntu 24.04 (aarch64),
              cloud-init: Docker + compose + firewall + bootstrap marker
```

| File | Purpose |
| ---- | ------- |
| `versions.tf` | OpenTofu/Terraform version, `oracle/oci` provider constraint, backend note |
| `providers.tf` | OCI provider + authentication (variables or `~/.oci/config`) |
| `variables.tf` | Every input, with Always Free and SSH-key guardrail validations |
| `main.tf` | Module wiring, tags, cloud-init rendering |
| `outputs.tf` | Public IP, endpoints, resource IDs |
| `cloud-init.yaml.tftpl` | First-boot bootstrap (Docker, log rotation, firewall) |
| `modules/network/` | VCN, IGW, route table, security list, public subnet |
| `modules/compute/` | Instance, AD selection, image resolution, VNIC lookup |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` (gitignored) |

## Prerequisites

1. **OpenTofu** (`tofu`) or **Terraform** (`terraform`), 1.6 or newer.
2. **OCI API key** configured in `~/.oci/config`, *or* `user_ocid` + `fingerprint`
   + `private_key_path` passed as variables. The key file must live **outside**
   this repository — `.gitignore` blocks `*.pem` and `*.key` regardless.
3. **Your SSH public key** (the `.pub` file). Pasting a private key is rejected
   by variable validation.
4. A compartment OCID. The tenancy root is fine for a portfolio environment.

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then fill in your values

tofu init                  # downloads oracle/oci, writes .terraform.lock.hcl
tofu fmt -recursive        # canonical formatting
tofu validate              # schema + type check, no credentials needed
tofu plan -out=stage2.tfplan
tofu apply stage2.tfplan
```

Inspect the results:

```bash
tofu output
tofu output -raw instance_public_ip
tofu output -json connection_endpoints
```

Tear everything down (billing stops; the boot volume is deleted):

```bash
tofu destroy
```

> `terraform` works identically — substitute the binary name. The lock file is
> committed so both tools resolve the same provider build.

## Deploy the stack onto the new host

IaC provisions the host; the pipeline is still the Stage 1 compose file:

```bash
ssh ubuntu@$(tofu output -raw instance_public_ip)
git clone https://github.com/kaveh8866/Centralized-Log-Aggregator.git
cd Centralized-Log-Aggregator
cp .env.example .env      # set a real Grafana password
docker compose -f docker/docker-compose.yml up -d --build
```

Then open `http://<public-ip>:3000` and query `{job="fluentbit"}`.

## Always Free guardrails

`variables.tf` refuses values that would leave the free envelope, so a typo
cannot turn into a bill:

| Guard | Rule |
| ----- | ---- |
| `instance_ocpus` | 1–4 (A1 free allowance is 4 OCPU **total** across A1 instances) |
| `instance_memory_gbs` | 1–24 (24 GB total) |
| `boot_volume_size_gbs` | ≥ 50 (200 GB block storage total, shared with other resources) |
| `ssh_public_key` | must start with `ssh-ed25519`, `ssh-rsa` or `ecdsa-sha2-nistp*` |
| `region` | must look like `xx-region-N` |
| `vcn_cidr` / `subnet_cidr` | must parse as CIDR |

If you already run another A1 instance, lower `instance_ocpus` /
`instance_memory_gbs` so the **sum** stays inside the allowance.

**The allowance is metered in hours, not a flat ceiling.** As of the 2026 terms,
Always Free A1 gives 1,500 OCPU-hours and 9,000 GB-hours per month (≈ 2 OCPU /
12 GB running continuously; earlier docs stated a flat 4 OCPU / 24 GB). So the
1–4 / 1–24 range above is a *validity* guard, not a free-forever setting: a
4 OCPU / 24 GB instance running 24/7 exceeds the budget. Stay free with
`instance_ocpus × 730 ≤ 1500` and `instance_memory_gbs × 730 ≤ 9000`. The tested
1 OCPU / 6 GB deployment uses about 49 % of both.

### Capacity and availability domain

A1 capacity is per availability domain and is often exhausted. A launch can fail
with `500-InternalError, Out of host capacity.` while the network resources are
created normally. Retry in another AD:

```bash
tofu apply -var "availability_domain=jiTx:EU-FRANKFURT-1-AD-2"
```

**Pin that AD in `terraform.tfvars` afterwards.** The default (`null`) resolves to
the region's *first* AD, so without pinning, the next plan sees config AD-1
against a state instance in AD-2 and proposes to replace it.

`cloud-init` is instance metadata, so editing `cloud-init.yaml.tftpl` (or pinning
a new AD) only takes effect on a new instance:

```bash
tofu apply -replace=module.compute.oci_core_instance.this
```

Because the provider treats `metadata.user_data` as ForceNew, a **CRLF checkout**
of the template also forces replacement: the rendered payload must stay
byte-identical, so `.gitattributes` pins `*.tftpl`/`*.sh` to LF on every platform.

## Security notes

- **No credentials in the repository.** The API key path, tenancy OCID and
  compartment OCID live in `terraform.tfvars`, which is gitignored, or in
  `~/.oci/config`. State (`*.tfstate`) is gitignored too — it records resource
  IDs and, for some resources, rendered user-data.
- **Loki has no authentication, so it is closed by default.**
  `enable_loki_ingress` is `false`, compose binds it to `127.0.0.1:3100`, and the
  network module rewrites a `0.0.0.0/0` CIDR to the private subnet if one is
  supplied. Reach it with `ssh -L 3100:localhost:3100`; enable the rule only for a
  remote collector, scoped to that collector's address.
- **Restrict SSH.** Default `ssh_allowed_cidr = 0.0.0.0/0` is convenient, not
  safe; set it to your own address.
- **Egress is open** so the instance can install packages and pull images.
  Tighten it once the image set is stable.
- Cloud-init installs Docker from the distro repository — no `curl | sh` of a
  remote script, and no secret is written into instance metadata.

## Porting to AWS or GCP

The log pipeline (`docker/`, `configs/`, `Dockerfile`) is identical on every
provider; only the two modules change. The ingress contract (22, 3000, 3100),
the cloud-init payload and the outputs stay the same.

| OCI (implemented) | AWS | GCP |
| ----------------- | --- | --- |
| `oci_core_vcn` | `aws_vpc` | `google_compute_network` |
| `oci_core_internet_gateway` | `aws_internet_gateway` | implicit in a default-route VPC |
| `oci_core_route_table` | `aws_route_table` + `aws_route` | `google_compute_route` |
| `oci_core_security_list` | `aws_security_group` + ingress rules | `google_compute_firewall` |
| `oci_core_subnet` | `aws_subnet` | `google_compute_subnetwork` |
| `oci_core_instance` | `aws_instance` (`t4g.small` / `t3.micro`) | `google_compute_instance` (`e2-micro`) |
| `shape_config { ocpus, memory_in_gbs }` | `instance_type` (fixed sizes) | `machine_type` (fixed sizes) |
| `metadata.user_data` | `user_data` | `metadata_startup_script` |
| `availability_domain` | `availability_zone` | `zone` |
| `oci_core_vnic_attachments` + `oci_core_vnic` | `aws_instance.public_ip` | `google_compute_instance.network_interface[0].access_config[0].nat_ip` |

Sketch of the port:

```hcl
# environments/aws/main.tf
provider "aws" { region = var.region }

module "network" {
  source   = "../../modules/network-aws"   # same variables, AWS resources
  vpc_cidr = var.vcn_cidr
  subnet_cidr = var.subnet_cidr
  ssh_allowed_cidr = var.ssh_allowed_cidr
  grafana_port = 3000
  loki_port    = 3100
}

module "compute" {
  source            = "../../modules/compute-aws"
  subnet_id         = module.network.subnet_id
  instance_type     = "t4g.small"          # arm64, free-trial eligible
  ssh_public_key    = var.ssh_public_key
  user_data         = local.user_data      # same cloud-init template
}
```

Notes that save a debugging session:

- **Architecture.** OCI A1 is ARM; on AWS pick `t4g.*` (Graviton) or keep the
  `amd64` path — both are published for all three images in the stack.
- **Images.** AWS needs an AMI lookup (`data "aws_ami"` filtered by
  architecture + owner) instead of `oci_core_images`; GCP uses
  `data "google_compute_image"` with `family = "ubuntu-2404-lts-arm64"`.
- **Cloud-init differs by image.** `docker-compose-v2` is an Ubuntu package
  name; on Amazon Linux use `docker` + the compose plugin from Docker's repo.
- **Firewall on the host.** AWS/GCP images ship their own firewall; the
  `iptables` lines in `cloud-init.yaml.tftpl` are harmless but redundant, and
  the cloud security group is the real control.
- **Free tiers are smaller.** `t3.micro` (1 GB) and `e2-micro` (1 GB) are below
  the 4 GB this stack is sized for. Raise the machine size or lower Loki's
  `mem_limit` and `retention_period` before claiming it runs comfortably.
- **State.** Use one backend key per environment so OCI and AWS state never mix.

## Verification performed

Static checks, OpenTofu 1.13.9 + `oracle/oci` v7.32.0:

```text
tofu fmt -check -recursive   → clean
tofu init -backend=false     → oracle/oci installed, lock file written
tofu validate                → Success! The configuration is valid.
```

Live deployment, 2026-11-12 (`eu-frankfurt-1`, `VM.Standard.A1.Flex`, 1 OCPU /
6 GB / 50 GB, AD-2 after AD-1 reported no host capacity):

```text
tofu apply                   → 6 added (VCN, IGW, route table, security list, subnet, instance)
tofu plan (AD pinned)        → No changes. Your infrastructure matches the configuration.
```

The stack was then deployed over SSH and verified: Grafana `:3000/api/health`
HTTP 200 from the public internet, Loki queries HTTP 200 with live container
logs, and Grafana's provisioned Loki datasource reporting "Data source
successfully connected". `tofu output` prints that instance's public IP.

A hardening pass then removed the public `3100` rule and bound Loki to loopback.
Current state: `:3100` from the internet returns HTTP 000 (blocked), the host
listens on `127.0.0.1:3100` only, and the same checks pass through
`ssh -L 3100:localhost:3100`. Grafana on `:3000` and SSH on `:22` are unchanged.

Three defects were caught by this process and fixed — which is why the live run
matters:

1. Child modules without `required_providers` resolved `hashicorp/oci`
   (a different, much older schema) instead of `oracle/oci`.
2. `oci_core_vnic` exposes `public_ip_address` / `private_ip_address`, not
   `public_ip` / `private_ip`.
3. `cloud-init.yaml.tftpl` had a comment above `#cloud-config`, so cloud-init
   logged `Unhandled non-multipart ... userdata` and skipped **everything**: the
   instance booted without Docker while still reporting `status: done`. The
   marker is now line 1, and a `runcmd` guard fails loudly if Docker is absent.
