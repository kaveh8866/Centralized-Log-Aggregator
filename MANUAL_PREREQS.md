# MANUAL_PREREQS — Human Setup Checklist

Everything a **human operator** must do before an AI agent (Cursor, Claude Code,
Windsurf) runs the automated playbook in [`AGENT_GUIDE.md`](AGENT_GUIDE.md).

Phases 1–2 of the agent guide (local Docker stack and log ingestion) need nothing
from this file beyond Step 2. Everything from **Phase 3 onward** is blocked until
Steps 1–8 here are complete.

> **Certification scope.** The infrastructure code is cloud-agnostic (OpenTofu),
> but the **final production verification and testing certification for this
> project are performed strictly on Oracle Cloud Infrastructure (OCI), using OCI
> trial credits**. AWS and GCP are documented ports, not certified targets — see
> [Porting to AWS or GCP](#porting-to-aws-or-gcp).

---

## Checklist at a glance

| # | Step | Time | Blocks |
| - | ---- | ---- | ------ |
| 1 | OCI account, region, tenancy access | 10 min | Step 4–6 |
| 2 | Local tooling: Docker + OpenTofu + git | 15 min | Phases 1–5 |
| 3 | SSH key pair for the instance | 2 min | Step 8 |
| 4 | OCI API signing key | 5 min | Step 5 |
| 5 | `~/.oci/config` profile | 2 min | Agent Phase 3 |
| 6 | IAM policy for the operator group | 5 min | Agent Phase 3 |
| 7 | `.env` for the compose stack | 3 min | Agent Phase 1 |
| 8 | `terraform/terraform.tfvars` | 5 min | Agent Phase 3 |
| 9 | Preflight verification (run the commands) | 5 min | Agent Phase 0 |
| 10 | Approval + hand-off to the agent | 1 min | Agent Phase 3 apply |

Work top to bottom. Tick each box only when the **verification command** in that
step succeeds — not when the console tab looked right.

---

## Step 1 — OCI account, region and access

- [ ] An OCI account exists and you can sign in to the console.
- [ ] You know the **home region** of the tenancy (shown in the console URL, e.g.
      `cloud.oracle.com/?region=eu-frankfurt-1`). Use this region for
      `region` in `terraform.tfvars`; resources in other regions need that region
      subscription first.
- [ ] Trial credits are active (Billing & Cost Management → Credits), or the
      tenancy is on Always Free. **Trial credits do not raise Always Free limits**
      — A1 capacity is still first-come.
- [ ] You can see **Compute → Instances** and **Networking → Virtual Cloud
      Networks** in the console.

Notes you will need (keep them out of chat and out of Git):

| Identifier | Where to find it |
| ---------- | ---------------- |
| Tenancy OCID | Profile menu → Tenancy: &lt;name&gt; → "OCID" copy link |
| User OCID | Profile menu → My profile → "OCID" copy link |
| Compartment OCID | Identity → Compartments (or the root compartment = tenancy OCID) |
| Region | Console URL / region selector |
| API key fingerprint | Generated in Step 4 |

---

## Step 2 — Local tooling

Install and verify each one. Commands must print a version.

- [ ] **Git**
  ```bash
  git --version
  git clone https://github.com/kaveh8866/Centralized-Log-Aggregator.git
  cd Centralized-Log-Aggregator
  ```
- [ ] **Docker with a running daemon** (Docker Desktop on Windows/macOS,
      Docker Engine on Linux)
  ```bash
  docker --version
  docker info --format '{{.ServerVersion}}'   # must print a version
  ```
  If it prints `cannot connect ... dockerDesktopLinuxEngine`, start Docker Desktop
  and wait for "Engine running".
- [ ] **OpenTofu ≥ 1.6** (Terraform ≥ 1.6 works identically)
  ```bash
  # Windows
  winget install OpenTofu.OpenTofu
  # macOS
  brew install opentofu
  # Debian/Ubuntu: follow https://opentofu.org/docs/intro/install/
  tofu version
  ```
- [ ] *(Optional)* **OCI CLI**, useful for independent credential checks and for
      reading leftover resources after a teardown:
  ```bash
  oci --version
  ```
- [ ] *(Optional)* `jq` for readable API output in the playbook.

---

## Step 3 — SSH key pair

The Terraform module injects a **public** key; keep the private key off the repo.

```bash
# Create an ed25519 key pair in the default location
ssh-keygen -t ed25519 -C "cloudguard-log-aggregator" -f ~/.ssh/cloudguard_logs

# Show the PUBLIC key — this is the only part that goes into terraform.tfvars
cat ~/.ssh/cloudguard_logs.pub
```

- [ ] Public key prints one line starting with `ssh-ed25519 ...`.
- [ ] Private key (`~/.ssh/cloudguard_logs`) is **not** inside the repository and
      never will be: `.gitignore` blocks `*.pem`, `*.key`, `id_rsa`, `id_ed25519`.
- [ ] Sanity check from inside the repo: `git check-ignore -q .env && echo ok`.

> Pasting the private key into `ssh_public_key` is rejected by variable
> validation, by design. If it ever lands in `terraform.tfvars`, delete it and
> regenerate the key pair.

---

## Step 4 — Generate the OCI API signing key

You need an API key pair (RSA) plus the fingerprint OCI assigns to it.

### Console path (recommended)

1. Open the console → profile menu (top right) → **My profile**.
2. **API keys** → **Add API key** → **Generate API key pair**.
3. **Download the private key** — OCI will not show it again.
   Move it to a stable location outside any repository:
   ```bash
   mkdir -p ~/.oci
   mv ~/Downloads/*.pem ~/.oci/oci_api_key.pem
   chmod 600 ~/.oci/oci_api_key.pem            # Linux / macOS
   ```
   Windows:
   ```bash
   icacls "$USERPROFILE/.oci/oci_api_key.pem" /inheritance:r /grant:r "$USERNAME:F"
   ```
4. Click **Add**. The console shows a **configuration file preview** with
   `user`, `fingerprint`, `tenancy`, `region`, `key_file`. Copy the
   **fingerprint** — you need it for Step 5.
5. Leave the key **without a passphrase**. The provider would need the passphrase
   in plain text to use it, which defeats the purpose of keeping it out of files.

### CLI path (if the OCI CLI is installed)

```bash
oci setup keys          # writes ~/.oci/oci_api_key.pem + oci_api_key_public.pem
cat ~/.oci/oci_api_key_public.pem
```

Then upload the **public** key in the same console page: **API keys → Add API
key → Paste public key**, and copy the fingerprint it returns.

- [ ] `~/.oci/oci_api_key.pem` exists and is readable **only** by you.
- [ ] Fingerprint copied (format: `xx:xx:...` 16 pairs of hex, no spaces needed).
- [ ] No `.pem` file anywhere inside the repository:
  ```bash
  git status --porcelain | grep -iE '\.pem|\.key' || echo "no key material in the tree"
  ```

---

## Step 5 — Configure `~/.oci/config`

The preferred authentication path: no key paths or OCIDs inside the repository.

- Linux/macOS: `~/.oci/config`
- Windows: `C:\Users\<you>\.oci\config`

```ini
[DEFAULT]
user=<your-user-ocid>
fingerprint=<your-api-key-fingerprint>
key_file=/home/<you>/.oci/oci_api_key.pem
tenancy=<your-tenancy-ocid>
region=eu-frankfurt-1
```

Windows works too — use forward slashes in `key_file`:

```ini
key_file=C:/Users/<you>/.oci/oci_api_key.pem
```

- [ ] File saved, permissions restricted (`chmod 600 ~/.oci/config`).
- [ ] Region matches Step 1 (home region).
- [ ] Verify the credentials **outside** OpenTofu:
  ```bash
  oci iam user get --user-id <your-user-ocid> --query 'data.name' --output table
  # prints your display name
  ```
  If the OCI CLI is not installed, the provider check in Step 9 covers it.

> Multiple tenancies? Use named profiles (`[PROD]`) and set
> `config_file_profile = "PROD"` in `terraform.tfvars`.

---

## Step 6 — OCI IAM permissions

The tenancy administrator already has everything. For a least-privilege operator
identity, create a group and one policy in the target compartment.

1. **Identity → Domains → (Default) → Groups → Create group**, e.g.
   `log-aggregator-operators`.
2. Add your user to the group.
3. **Identity → Policies → Create policy** in the compartment, name
   `log-aggregator-iac`, and paste:

```text
Allow group log-aggregator-operators to manage virtual-network-family in compartment <compartment-name>
Allow group log-aggregator-operators to manage instance-family in compartment <compartment-name>
Allow group log-aggregator-operators to use volume-family in compartment <compartment-name>
Allow group log-aggregator-operators to read instance-images in tenancy
Allow group log-aggregator-operators to read availability-domains in tenancy
```

Why each line:

| Policy | Needed for |
| ------ | ---------- |
| `manage virtual-network-family` | VCN, internet gateway, route table, security list, subnet, VNIC |
| `manage instance-family` | launch / terminate the instance |
| `use volume-family` | boot volume attached at launch |
| `read instance-images in tenancy` | `oci_core_images` data source (Ubuntu lookup) |
| `read availability-domains in tenancy` | `oci_identity_availability_domains` data source |

- [ ] Policy created in the **same compartment** as `compartment_ocid`.
- [ ] Group membership confirmed (policy changes can take a few seconds).
- [ ] If you skip the group and use an admin user, note it in the hand-off: the
      agent's `tofu plan` runs with full tenancy rights.

---

## Step 7 — Compose environment (`.env`)

Local stack only; the cloud host repeats this after clone.

```bash
cp .env.example .env
```

| Variable | Set it to | Notes |
| -------- | --------- | ----- |
| `GRAFANA_ADMIN_USER` | `admin` (or your own) | console user |
| `GRAFANA_ADMIN_PASSWORD` | **a real password** | the only value you must change |
| `GRAFANA_ROOT_URL` | `http://localhost:3000` | becomes `http://<public-ip>:3000` on OCI |
| `GRAFANA_PORT` | `3000` | host port; change on conflict |
| `LOKI_PORT` | `3100` | host port; change on conflict |
| `FLUENT_BIT_HTTP_PORT` | `2020` | loopback metrics only |
| `LOG_HOST_LABEL` | e.g. `laptop-dev` | becomes a Loki label — keep it stable |
| `LOG_CLUSTER_LABEL` | `cloudguard-logs` | becomes a Loki label |
| `OCI_*` | optional | informational for Stage 3; the compose stack does not read them |

- [ ] `GRAFANA_ADMIN_PASSWORD` is no longer the placeholder.
- [ ] `.env` is ignored: `git check-ignore -q .env && echo "ignored (correct)"`.
- [ ] `.env` contains **no** OCI API key, fingerprint or private key. OCI
      credentials belong in `~/.oci/` (Step 5), never in `.env`.

---

## Step 8 — Terraform credentials (`terraform/terraform.tfvars`)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Pick **one** authentication path.

**A. Config profile (recommended)** — nothing sensitive in the file:

```hcl
tenancy_ocid        = "<your-tenancy-ocid>"
compartment_ocid    = "<your-compartment-ocid>"
region              = "eu-frankfurt-1"
config_file_profile = "DEFAULT"

user_ocid        = null
fingerprint      = null
private_key_path = null
```

**B. Inline API key** — when there is no `~/.oci/config`:

```hcl
tenancy_ocid     = "<your-tenancy-ocid>"
compartment_ocid = "<your-compartment-ocid>"
region           = "eu-frankfurt-1"
user_ocid        = "<your-user-ocid>"
fingerprint      = "<your-api-key-fingerprint>"
private_key_path = "/home/<you>/.oci/oci_api_key.pem"
```

Then the values that decide cost and exposure:

| Variable | Suggested | Why |
| -------- | --------- | --- |
| `ssh_public_key` | contents of `~/.ssh/cloudguard_logs.pub` | instance login; private key rejected |
| `ssh_allowed_cidr` | **your public IP** `/32` | do not leave SSH open to the world |
| `grafana_allowed_cidr` | `0.0.0.0/0` only if you intend to browse from anywhere | Grafana UI |
| `loki_allowed_cidr` | the VCN CIDR (`10.0.0.0/16`) or a collector IP | **Loki has no auth in Stage 1** |
| `enable_loki_ingress` | `false` (recommended default) | adds the Loki ingress rule; leave off unless a remote collector must push |
| `instance_ocpus` / `instance_memory_gbs` | `1` / `6` | Always Free A1 allowance is 4 OCPU / 24 GB **total** |
| `boot_volume_size_gbs` | `50` | free block storage is 200 GB total |
| `availability_domain` | `null` (first AD) | set explicitly if A1 capacity fails |

- [ ] `terraform.tfvars` is ignored:
      `git check-ignore -q terraform/terraform.tfvars && echo "ignored (correct)"`
- [ ] No real OCID or key path is in `terraform.tfvars.example`.
- [ ] Formatting and schema are valid:
  ```bash
  tofu fmt -check -recursive
  tofu init
  tofu validate          # Success! The configuration is valid.
  ```

---

## Step 9 — Preflight verification

Run from the repository root. All must pass before hand-off.

```bash
# Repository
git rev-parse --abbrev-ref HEAD                 # main
git status --porcelain                          # empty

# Local runtime
docker info --format '{{.ServerVersion}}'       # a version
docker compose --env-file .env.example -f docker/docker-compose.yml config --quiet && echo "compose ok"

# Infrastructure
cd terraform
tofu version                                    # >= 1.6
tofu validate                                   # Success
tofu providers | grep -c 'oracle/oci'           # >= 1 (and no hashicorp/oci)
tofu plan -refresh=false 2>&1 | tail -5         # credential + schema check
```

`tofu plan` is a **read-only** call: it lists what would be created (6 resources
on a fresh compartment) and proves authentication, IAM, region and quota all work.
It still talks to OCI, so it needs Steps 1–8 done.

- [ ] Every command above exited 0.
- [ ] `tofu plan` reported `Plan: 6 to add, 0 to change, 0 to destroy`.
- [ ] No `OutOfCapacity`, `401`, `404` or `NotAuthorized` in the plan output.

---

## Step 10 — Approve and hand off

- [ ] You understand that `tofu apply` creates a real VM and that `tofu destroy`
      deletes it **and its boot volume, including all stored logs**.
- [ ] You will approve apply/destroy explicitly. The agent guide requires it.
- [ ] Hand-off message to the agent, with no secrets in it:

```text
Repository: Centralized-Log-Aggregator (branch main)
Prereqs: MANUAL_PREREQS.md steps 1-9 complete; `tofu plan` shows 6 to add.
Approved: Phase 0-3 (plan only). Ask again before `tofu apply`.
OCI: region eu-frankfurt-1, Always Free A1 (1 OCPU / 6 GB), trial credits.
Do not paste OCIDs, keys or passwords into chat.
```

---

## Cost and teardown hygiene

- Always Free A1 covers **4 OCPU / 24 GB total** and **200 GB** of block storage
  across the tenancy; this stack uses 1 OCPU / 6 GB / 50 GB.
- Trial credits do not increase those limits. A second A1 instance shares them.
- Stopping an instance keeps its boot volume (and its 50 GB allocation).
  `tofu destroy` removes both.
- Always finished with a session? Run the agent guide's Phase 5 and confirm
  `tofu state list` is empty.

---

## Porting to AWS or GCP

Same repository, different `terraform/modules`. Change these inputs (full mapping
table in [`terraform/README.md`](terraform/README.md#porting-to-aws-or-gcp)):

| OCI input | AWS | GCP |
| --------- | --- | --- |
| `tenancy_ocid`, `compartment_ocid`, `user_ocid`, `fingerprint`, `private_key_path`, `config_file_profile` | remove → `AWS_PROFILE` / env keys / IAM role | remove → `project` + ADC or service-account impersonation |
| `region` | `region` | `region` + `zone` |
| `vcn_cidr`, `subnet_cidr` | `vpc_cidr`, `subnet_cidr` | `network_cidr`, `subnet_cidr` |
| `instance_shape`, `instance_ocpus`, `instance_memory_gbs` | `instance_type = "t4g.small"` | `machine_type = "e2-small"` |
| `boot_volume_size_gbs` | `root_block_device.volume_size` | `boot_disk.initialize_params.size` |
| `availability_domain` | `availability_zone` | `zone` |
| `image_id`, `image_operating_system*` | `data "aws_ami"` by architecture | `data "google_compute_image"` family |
| `ssh_allowed_cidr`, `grafana_allowed_cidr`, `loki_allowed_cidr`, `grafana_port`, `loki_port` | unchanged | unchanged |

**Certification does not carry over.** A working AWS or GCP deploy is new
evidence that must be collected there; this project is certified on OCI only.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `401-NotAuthenticated` from the provider or CLI | fingerprint/key mismatch, or unreadable key | regenerate the pair (Step 4) and re-copy the fingerprint |
| `401` with correct fingerprint on Linux/macOS | key file permissions too open | `chmod 600 ~/.oci/oci_api_key.pem` |
| `Error: No valid credential sources found` | no `config_file_profile` and no inline key | Step 5 or Step 8-B |
| `404-NotAuthorizedOrNotFound` | wrong compartment, or IAM policy missing | recheck Step 6 and the OCID |
| `500 OutOfCapacity` on `VM.Standard.A1.Flex` | free A1 capacity exhausted in that AD | retry later, pick another `availability_domain`, or reduce OCPU/RAM |
| `tofu init` installs `hashicorp/oci` | a module lacks `required_providers` | keep `modules/*/versions.tf`, then `tofu init -upgrade` |
| `bind: address already in use` on 3000/3100 | another service owns the port | set `GRAFANA_PORT`/`LOKI_PORT` in `.env`, or stop the other stack |
| `docker info` cannot connect | daemon not running | start Docker Desktop / `systemctl start docker` |
| Grafana login rejected | `.env` password changed after first start (volume keeps the old one) | use the old password, or reset via `docker compose down -v` (deletes dashboards/data) |

---

## Sign-off

```text
[ ] Step 1  OCI account, region, credits confirmed
[ ] Step 2  Docker daemon + OpenTofu + git verified
[ ] Step 3  SSH key pair created, public key copied
[ ] Step 4  API key pair generated, fingerprint recorded
[ ] Step 5  ~/.oci/config written and permissions restricted
[ ] Step 6  IAM policy applied (or admin identity acknowledged)
[ ] Step 7  .env created, password set, file ignored
[ ] Step 8  terraform.tfvars filled, ignored, validate passes
[ ] Step 9  tofu plan shows 8 to add, no auth errors
[ ] Step 10 Hand-off sent, apply approval scope agreed

Operator: ______________________   Date: ______________
```
