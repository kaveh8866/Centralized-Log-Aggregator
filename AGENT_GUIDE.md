# AGENT_GUIDE — Centralized Log Aggregator

**AI code-agent playbook** for Cursor, Claude Code, Windsurf, or any autonomous
coding agent working on this repository. It is written to be executed, not
skimmed: every phase is a numbered block of shell commands with an expected
result and a stop condition.

Read [`MANUAL_PREREQS.md`](MANUAL_PREREQS.md) first. The human operator must
finish that checklist — OCI API key, IAM policy, `.env`, `terraform.tfvars` —
before Phase 3 can run. Phases 1 and 2 need no cloud credentials at all.

---

## How to use this guide (agent instruction)

1. Open the repository root (the directory containing `docker/`, `configs/` and
   `terraform/`). All commands below are relative to it.
2. Work phases **in order**. Do not skip Phase 0.
3. Run every command yourself and read its real output. Never report a phase as
   passed because the file looked correct — only because the command exited 0.
4. If a command fails, stop and apply the matching entry in
   [Troubleshooting](#troubleshooting). Do not "fix" a failure by weakening a
   check, disabling a config, or adding `|| true`.
5. Report using the [report template](#report-template) at the end.

### Non-negotiables

- **Never write a credential into a tracked file.** No passwords, API keys,
  private keys, tenancy/compartment OCIDs or PEM blocks in `README.md`,
  `AGENT_GUIDE.md`, `.env.example`, `terraform.tfvars.example`, commits or chat.
- **Never run `tofu apply` or `tofu destroy` without explicit human approval.**
  They create and destroy real cloud resources. Plan first, show the plan.
- **Never commit `.env` or `terraform.tfvars`.** Verify with `git check-ignore`.
- **Never edit `.terraform/`** and never hand-edit `.terraform.lock.hcl`.
- **Do not claim a cloud is verified.** Only OCI is certified — see
  [Certification scope](#certification-scope-and-multi-cloud-portability).

---

## System map

| Piece | What it is | Where |
| ----- | ---------- | ----- |
| Collector | Fluent Bit 3.1, tails Docker JSON logs, ships to Loki | `configs/fluent-bit/`, built from root `Dockerfile` |
| Store | Grafana Loki 3.2, single binary, TSDB + filesystem, 14-day retention | `configs/loki/loki-config.yml` |
| UI | Grafana 11.3, Loki provisioned as default data source | `configs/grafana/provisioning/datasources/loki.yml` |
| Orchestration | Docker Compose stack (ports 3000 / 3100 / 2020) | `docker/docker-compose.yml` |
| Infrastructure | OpenTofu/Terraform: VCN, IGW, security list 22/3000 (3100 closed by default), A1.Flex instance | `terraform/` |

File-by-file ownership:

| Path | Owns |
| ---- | ---- |
| `docker/docker-compose.yml` | service graph, ports, limits, volumes, networks |
| `Dockerfile` (root) | Fluent Bit image; bakes `configs/fluent-bit/*` |
| `configs/fluent-bit/fluent-bit.conf` | input / filter / output pipeline, buffering |
| `configs/fluent-bit/parsers.conf` | Docker `json-file` timestamp + JSON parsing |
| `configs/loki/loki-config.yml` | storage, schema, limits, retention, WAL |
| `configs/grafana/provisioning/datasources/loki.yml` | Loki as default data source |
| `.env.example` | every knob the compose stack accepts (placeholders only) |
| `terraform/*.tf` | infrastructure root module (OCI) |
| `terraform/modules/network`, `.../compute` | VCN/IGW/security list · instance/AD/image/VNIC |
| `terraform/terraform.tfvars.example` | variable template; the real file stays ignored |
| `MANUAL_PREREQS.md` | human checklist that gates Phase 3 |

There is no `package.json` and no unit-test suite: the compose file, the configs
and the HCL are the source of truth.

---

## Phase 0 — Preflight

Run from the repository root. Every command must succeed before continuing.

```bash
# 0.1 You are in the right directory
test -f docker/docker-compose.yml && test -f terraform/versions.tf && echo "repo root OK"

# 0.2 Git state: branch main, clean tree
git rev-parse --abbrev-ref HEAD        # expected: main
git status --porcelain                 # expected: no output

# 0.3 Docker CLI *and daemon*
docker --version
docker info --format '{{.ServerVersion}}'   # must print a version, not "cannot connect"
```

If `docker info` reports
`failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`,
Docker Desktop is not running: start it and wait for "Engine running". On Linux,
`sudo systemctl start docker` (ask the human; do not escalate silently).

```bash
# 0.4 OpenTofu (or Terraform) >= 1.6
tofu version    # or: terraform version
```

If neither exists, install OpenTofu (Linux/macOS: `brew install opentofu` or the
official installer; Windows: `winget install OpenTofu.OpenTofu`). Do **not**
continue to Phase 3 with a version below 1.6.

```bash
# 0.5 Compose file validity (no daemon work, no credentials)
docker compose --env-file .env.example -f docker/docker-compose.yml config --quiet \
  && echo "compose config valid"

# 0.6 Ignore boundary still intact
git check-ignore -q .env && git check-ignore -q terraform/terraform.tfvars && echo "secrets ignored"
```

**Stop condition:** all six blocks pass. Otherwise fix the environment, not the
repository, before touching anything else.

---

## Phase 1 — Initialize Docker Compose locally

```bash
# 1.1 Create the local environment file (never committed)
cp .env.example .env
```

Edit `.env` and set **`GRAFANA_ADMIN_PASSWORD`** to a real value. Leave
`LOG_HOST_LABEL` as your machine name so logs are attributable, e.g.
`LOG_HOST_LABEL=laptop-dev`. Everything else can stay default.

```bash
# 1.2 Confirm variables interpolate as intended
docker compose --env-file .env -f docker/docker-compose.yml config \
  | grep -E 'GF_SECURITY_ADMIN_PASSWORD|published|LOG_HOST_LABEL'
```

```bash
# 1.3 Build the collector image and start the stack
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
```

```bash
# 1.4 All three services running
docker compose -f docker/docker-compose.yml ps
# cg-loki, cg-fluent-bit, cg-grafana all "Up"
```

```bash
# 1.5 Readiness probes
curl -s http://localhost:3100/ready; echo          # expected: ready
curl -s http://localhost:2020/api/v1/health; echo  # expected: {"fluent-bit":{"ok":true}}
curl -s http://localhost:3000/api/health; echo     # expected: {"database":"ok",...}
```

```bash
# 1.6 Collector connected to Loki (look for errors only)
docker compose -f docker/docker-compose.yml logs --tail=40 fluent-bit
```

A healthy collector logs `[output:loki:loki.0]` activity and no repeated
`failed to flush chunk`. Repeated flush errors mean Loki is not ready yet (wait
30 s) or the Loki config did not load (see Phase 2.6).

**Stop condition:** 3 containers up, three probes healthy, no flush errors.

---

## Phase 2 — Prove log ingestion into Loki

The point of this phase is end-to-end evidence: a container writes a line, Fluent
Bit ships it, Loki stores it, Grafana can query it.

```bash
# 2.1 Emit a uniquely identifiable log line from a throwaway container
STAMP="cloudguard-smoke-$(date +%s)"
docker run --rm --name cg-smoke-test alpine:3.20 sh -c "echo '$STAMP'; sleep 3"
echo "look for: $STAMP"
```

```bash
# 2.2 Query Loki directly (allow ~15 s: Flush 1s + Batch_Wait 5s)
NOW=$(date +%s)
curl -sG "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="fluentbit"}' \
  --data-urlencode "start=$((NOW - 900))000000000" \
  --data-urlencode "end=${NOW}000000000" \
  --data-urlencode 'limit=20'
```

Expected: a JSON body whose `data.result` is non-empty and whose `values`
contain your `cloudguard-smoke-...` line. With `jq` installed:

```bash
curl -sG "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="fluentbit"} |= "cloudguard-smoke"' \
  --data-urlencode "start=$((NOW - 900))000000000" \
  --data-urlencode "end=${NOW}000000000" \
  | jq -r '.data.result[].values[][1]'
```

```bash
# 2.3 Confirm labels are the low-cardinality set
curl -s http://localhost:3100/loki/api/v1/labels | jq -r '.data[]' | sort
# expected: cluster, host, job, service_name, stream  (never container ids)
```

```bash
# 2.4 Grafana sees Loki as the DEFAULT data source
set -a; . ./.env; set +a
curl -s -u "admin:${GRAFANA_ADMIN_PASSWORD}" http://localhost:3000/api/datasources \
  | jq -r '.[] | "\(.name) default=\(.isDefault)"'
# expected: Loki default=true
```

```bash
# 2.5 Grafana can execute the same query through the proxy
curl -s -u "admin:${GRAFANA_ADMIN_PASSWORD}" \
  "http://localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=%7Bjob%3D%22fluentbit%22%7D&limit=5" \
  | head -c 300
```

**Stop condition:** steps 2.2 (or 2.2b) return the smoke-test line, 2.3 shows only
the four expected labels, 2.4 shows `Loki default=true`.

### Common Phase 2 failures

| Symptom | Real cause | Fix |
| ------- | ---------- | --- |
| Query returns `{"result":[]}` | Container log driver is not `json-file` | `docker info --format '{{.LoggingDriver}}'`; the collector tails `/var/lib/docker/containers/*/*-json.log` |
| Query returns empty, logs show `no such file` | Docker data-root is not `/var/lib/docker` | `docker info --format '{{.DockerRootDir}}'` and adjust the bind mount in `docker/docker-compose.yml` |
| Collector logs `failed to flush chunk` repeatedly | Loki not ready / wrong DNS name | `docker compose logs loki`; the output must target host `loki`, not `localhost` |
| `data.result` empty only after a restart | Loki replaying its WAL | wait ~30 s and re-run |
| Loki exits at boot: `delete request store not set` | Loki ≥ 3.0 requirement | `delete_request_store: filesystem` must stay in `loki-config.yml` |

---

## Phase 3 — Apply OpenTofu for OCI

**Gate:** the human must have completed [`MANUAL_PREREQS.md`](MANUAL_PREREQS.md)
(OCI API key, `~/.oci/config`, IAM policy, `terraform/terraform.tfvars`) and
explicitly approved creating cloud resources.

```bash
cd terraform

# 3.1 Variables are present and NOT tracked
test -f terraform.tfvars || cp terraform.tfvars.example terraform.tfvars
git check-ignore -q terraform.tfvars && echo "tfvars ignored (correct)"

# 3.2 Static validation — no credentials needed
tofu fmt -check -recursive
tofu init
tofu validate                                  # expected: Success! The configuration is valid.
```

```bash
# 3.3 Confirm the provider resolved to oracle/oci (not hashicorp/oci)
tofu providers | grep -E 'oracle/oci|hashicorp/oci'
# required: only registry.opentofu.org/oracle/oci
```

```bash
# 3.4 Plan and review
tofu plan -out=stage3.tfplan
tofu show stage3.tfplan | grep -E 'will be created|Plan:'
```

Expected shape of the plan: **6 resources to add** — VCN, internet gateway,
route table, security list, subnet, instance — and no `destroy` of anything.
On top of those, four data sources are read (availability domains, Ubuntu image,
VNIC attachment, VNIC); table reads never appear as "to add". Confirm `shape = "VM.Standard.A1.Flex"`, `ocpus = 1`,
`boot_volume_size_in_gbs = 50`. If the plan wants to change existing resources
you do not own, **stop** and report.

```bash
# 3.5 Apply — REQUIRES HUMAN APPROVAL FIRST
tofu apply stage3.tfplan
```

```bash
# 3.6 Read the outputs
tofu output
tofu output -raw instance_public_ip
tofu output -json connection_endpoints
```

**Stop condition:** apply succeeds, `instance_public_ip` is a public address, and
retrieving `connection_endpoints` prints SSH + Grafana + Loki URLs.

---

## Phase 4 — Deploy the stack onto the provisioned host

```bash
cd terraform
IP=$(tofu output -raw instance_public_ip)
ssh -o StrictHostKeyChecking=accept-new ubuntu@"$IP" 'cloud-init status --wait; docker --version'
# cloud-init installs Docker on first boot; "status: done" means the host is ready
```

```bash
# 4.1 Clone the repository on the host
ssh ubuntu@"$IP" 'git clone https://github.com/kaveh8866/Centralized-Log-Aggregator.git'
```

```bash
# 4.2 Prepare the operator's .env for a remote origin.
# Done locally so the Grafana password never appears in a remote command line,
# shell history or process list.
test -f .env || { echo "create .env in Phase 1 first"; exit 1; }
TMP_ENV=$(mktemp)
sed -e "s|^GRAFANA_ROOT_URL=.*|GRAFANA_ROOT_URL=http://$IP:3000|" \
    -e "s|^LOG_HOST_LABEL=.*|LOG_HOST_LABEL=oci-log-aggregator|" \
    .env > "$TMP_ENV"
```

```bash
# 4.3 Copy it over and start the stack
scp "$TMP_ENV" ubuntu@"$IP":Centralized-Log-Aggregator/.env
rm -f "$TMP_ENV"
ssh ubuntu@"$IP" 'cd Centralized-Log-Aggregator && docker compose --env-file .env -f docker/docker-compose.yml up -d --build'
```

Then verify from your machine. Grafana is public; Loki is **not** — it binds to
loopback and the security list carries no `3100` rule:

```bash
curl -s "http://$IP:3000/api/health"; echo          # public
ssh -L 3100:localhost:3100 ubuntu@$IP              # in a second terminal
curl -s "http://localhost:3100/ready"; echo        # through the tunnel
```

Repeat the Phase 2 smoke test against `http://localhost:3100` (the tunnel), or
simply open `http://$IP:3000` and run `{job="fluentbit"}` in Explore.

> Loki on `:3100` has **no authentication** in this stage, so it is closed by
> default: `enable_loki_ingress = false`, a loopback port binding, and a network
> module that rewrites any `0.0.0.0/0` CIDR to the private subnet. Only enable the
> rule — scoped to a collector's address — if a remote agent must push directly.

---

## Phase 5 — Clean teardown

Teardown is destructive and irreversible: it deletes the instance, its boot
volume and every log stored on it.

```bash
# 5.1 Local stack (keep named volumes)
docker compose -f docker/docker-compose.yml down

# 5.2 Local stack including log data
docker compose -f docker/docker-compose.yml down -v
```

```bash
# 5.3 Cloud resources — REQUIRES HUMAN APPROVAL FIRST
cd terraform
tofu plan -destroy               # review first
tofu destroy
```

```bash
# 5.4 Verify nothing is left
tofu state list                  # expected: no output
tofu output                      # expected: warnings only, no values
```

Optional cross-check with the OCI CLI when it is installed and configured:

```bash
oci compute instance list --compartment-id "$(grep -E '^OCI_COMPARTMENT_OCID' ../.env | cut -d= -f2)" \
  --query 'data[].{name:"display-name",state:"lifecycle-state"}' --output table
```

Also confirm the security list, subnet, IGW and VCN are gone, then check the OCI
console's billing/cost page shows no active compute. Always Free resources do not
bill, but a leftover boot volume still consumes the 200 GB allowance.

**Stop condition:** state is empty, no running instances, local containers gone.

---

## Troubleshooting

### Container port conflicts

Symptom (from compose):

```text
Error starting userland proxy: listen tcp4 0.0.0.0:3000: bind: address already in use
Bind for 0.0.0.0:3100 failed: port is already allocated
```

Diagnose who owns the port:

```bash
# Any platform, container-level view
docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Image}}'

# Linux / macOS
ss -lntp | grep -E ':(3000|3100|2020)\b'   # or: lsof -nP -iTCP:3000 -sTCP:LISTEN

# Windows (Git Bash or cmd)
netstat -ano | grep -E ':(3000|3100|2020)\b'   # then: tasklist /FI "PID eq <pid>"
```

Fixes, in order of preference:

1. **Re-map instead of killing the other service** — the ports are variables:
   ```bash
   # .env
   GRAFANA_PORT=3001
   LOKI_PORT=3101
   FLUENT_BIT_HTTP_PORT=2021
   ```
   Then restart with the same compose command. Remember Loki's output host stays
   `loki:3100` inside the compose network — only the host-side mapping changes.
2. **Stop the stack that owns the port**: `docker stop <name>`, or
   `docker compose -f docker/docker-compose.yml down --remove-orphans`.
3. **Docker Desktop on Windows/macOS**: a stale `com.docker.backend` proxy can
   hold 3000; quit and restart Docker Desktop.
4. **Port 2020 is bound to loopback on purpose** (`127.0.0.1:2020`). If that still
   conflicts, set `FLUENT_BIT_HTTP_PORT` — do not remove the loopback binding.

Note the internal container ports never change: Loki listens on 3100 and Grafana
on 3000 inside the network. `GRAFANA_PORT`/`LOKI_PORT` only move the published
host port.

### OCI provider authentication

Match the error text to the cause before changing anything.

| Error text | Cause | Fix |
| ---------- | ----- | --- |
| `401-NotAuthenticated` / `The required information to complete authentication was not provided` | Key and fingerprint do not match, or no credential source was found | Regenerate the API key pair, paste the **new** fingerprint into `~/.oci/config` / `terraform.tfvars` |
| `401-NotAuthenticated` with a correct fingerprint | Private key unreadable, wrong path, or too-open permissions (Linux/macOS) | `chmod 600 ~/.oci/oci_api_key.pem`; confirm `private_key_path`/`key_file` is absolute |
| `Error: No valid credential sources found` | `config_file_profile` unset **and** the inline variables are null | Set `config_file_profile = "DEFAULT"`, or fill `user_ocid` + `fingerprint` + `private_key_path` |
| `404-NotAuthorizedOrNotFound` on the VCN/subnet | Wrong `compartment_ocid`, or the user lacks permission in that compartment | Copy the compartment OCID from the console; verify the IAM policy in `MANUAL_PREREQS.md` |
| `404-NotAuthorizedOrNotFound` on `oci_identity_availability_domains` | `tenancy_ocid` is actually a compartment OCID | Availability domains need the **tenancy** OCID |
| `InvalidParameter: region` / resource not found in region | Provider `region` differs from the tenancy's home region | Use the region shown in the console URL for that tenancy |
| `500 OutOfCapacity` / `InternalError` on `VM.Standard.A1.Flex` | No A1 capacity in the chosen AD (common on free tier) | Retry another AD with `-var "availability_domain=..."`, then **pin it in `terraform.tfvars`** — otherwise the next plan proposes replacing the instance — or lower `instance_ocpus` / `instance_memory_gbs` |
| Docker missing on a fresh instance, yet `cloud-init status: done` | `#cloud-config` was not the first line of user-data; cloud-init logs `Unhandled non-multipart` and skips the payload | Keep the marker on line 1 of `cloud-init.yaml.tftpl`; check `/var/log/cloud-init-output.log`; re-provision with `-replace=module.compute.oci_core_instance.this` |
| `InvalidParameter: bootVolumeSizeInGBs` | Boot volume below the image minimum | Keep `boot_volume_size_gbs >= 50` |
| `Error: ... clock skew` / signature expired | Host clock drift | Sync the OS clock (Windows: Settings → Time; Linux: `timedatectl set-ntp true`) |
| `Error: Failed to install provider` | Network/proxy blocks the registry | Retry `tofu init`; behind a proxy set `HTTPS_PROXY`; never hand-edit the lock file |

Prove the credentials independently of OpenTofu before debugging HCL:

```bash
# If the OCI CLI is installed and configured
oci iam user get --user-id <user-ocid> --query 'data.name' --output table

# Or let the provider talk
TF_LOG=DEBUG tofu plan 2>&1 | grep -iE 'oci|auth|401|404' | head -30
```

Other failures worth knowing:

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `docker info` → `cannot connect ... dockerDesktopLinuxEngine` | Docker daemon not running | Start Docker Desktop (or `systemctl start docker`) |
| `tofu validate` → `Unsupported attribute oci_core_vnic.public_ip` | A module is missing `required_providers` and resolves `hashicorp/oci` | Keep `modules/*/versions.tf` with `source = "oracle/oci"` |
| `tofu init` installed `hashicorp/oci` | Same as above; stale lock entry | Add the module `versions.tf`, then `tofu init -upgrade` |
| Grafana shows "No data source found" | Provisioning mount missing | Confirm `configs/grafana/provisioning/datasources/loki.yml` is mounted read-only |
| Fluent Bit container starts then exits | Config syntax error | `docker compose logs fluent-bit`; validate `[SECTION]`/`Key Value` alignment in `configs/fluent-bit/*.conf` |

---

## Certification scope and multi-cloud portability

### Certification scope — read before claiming anything is verified

- **The code is cloud-agnostic.** Infrastructure is OpenTofu-based, the runtime is
  a standard Docker Compose stack, and no provider SDK, region or credential is
  baked into `docker/`, `configs/` or the `Dockerfile`.
- **Runtime verification and testing certification are performed strictly on
  Oracle Cloud Infrastructure (OCI), using OCI trial credits.** OCI is the
  validated environment: it is where the stack is deployed, smoke-tested and
  signed off.
- **AWS and GCP are documented ports, not certified targets.** The mapping below
  exists so a port is mechanical; it is **not** evidence that the stack was
  tested there. Never describe this project as "AWS-verified" or "GCP-verified",
  and never copy an OCI result into an AWS/GCP claim.

Verification record for this repository:

| Check | Method | Status |
| ----- | ------ | ------ |
| HCL formatting | `tofu fmt -check -recursive` | proven locally |
| HCL schema/types | `tofu init -backend=false` + `tofu validate` | proven locally (oracle/oci v7.32.0) |
| Compose validity | `docker compose config --quiet` | proven locally |
| Zero-leak / docs / git isolation | CloudGuard portability audit | proven (100/100) |
| Live OCI apply + log smoke test | Phases 3–4 of this guide | **operator-run on OCI; not yet recorded here** |
| AWS / GCP deployment | — | **not tested, not certified** |

Do not upgrade the last two rows without command output from the target cloud.

### Porting to AWS or GCP — variables to change

Provider-specific resources live only in `terraform/modules/network` and
`terraform/modules/compute`; the resource-by-resource mapping table is in
[`terraform/README.md`](terraform/README.md#porting-to-aws-or-gcp).

| Variable (OCI) | AWS | GCP |
| -------------- | --- | --- |
| `region` | `region` (e.g. `eu-central-1`) | `region` + `zone` |
| `tenancy_ocid`, `compartment_ocid`, `user_ocid`, `fingerprint`, `private_key_path`, `config_file_profile` | delete; use `AWS_PROFILE` / env credentials / IAM role | delete; use `project` + Application Default Credentials or a service-account impersonation |
| `vcn_cidr` | `vpc_cidr` → `aws_vpc.cidr_block` | `network_cidr` → `google_compute_network` |
| `subnet_cidr` | `subnet_cidr` → `aws_subnet.cidr_block` | `subnet_cidr` → `google_compute_subnetwork` |
| `instance_shape = "VM.Standard.A1.Flex"` | `instance_type = "t4g.small"` (arm64) or `t3.micro` | `machine_type = "e2-small"` (1 GB `e2-micro` is below this stack's sizing) |
| `instance_ocpus`, `instance_memory_gbs` | remove (`instance_type` is fixed-size) | remove (`machine_type` is fixed-size) |
| `boot_volume_size_gbs` | `root_block_device { volume_size }` | `boot_disk { initialize_params { size } }` |
| `availability_domain` | `availability_zone` | `zone` |
| `image_id` / `image_operating_system*` | `data "aws_ami"` filtered by architecture | `data "google_compute_image"` (`ubuntu-2404-lts-arm64`) |
| `ssh_allowed_cidr`, `grafana_allowed_cidr`, `loki_allowed_cidr`, `grafana_port`, `loki_port` | **unchanged** — same ingress contract | **unchanged** — same ingress contract |
| `ssh_public_key`, `hostname_label`, `freeform_tags` | `key_name` / `tags` | `ssh-keys` metadata / `labels` |

Cloud-init needs one edit per provider: `docker-compose-v2` is an Ubuntu package
name (Amazon Linux and GCP's Debian images differ), and AWS/GCP enforce ingress in
the security group / firewall rather than in the host `iptables` rules.

---

## Invariants — do not break these

1. **No secrets in the repository.** `.env` and `terraform.tfvars` are ignored;
   the `.example` files hold placeholders only.
2. **Pinned image tags.** `grafana/loki:3.2.1`, `grafana/grafana:11.3.1`,
   `fluent/fluent-bit:3.1.9`. No `latest`. `amd64` and `arm64` must both exist.
3. **Loki labels stay low-cardinality.** `job`, `cluster`, `host`, `stream`, plus
   the constant `service_name` that Fluent Bit's Loki output adds automatically.
   Never label by container id, request id or file path.
4. **No Docker socket mount.** Read-only `/var/lib/docker/containers` only.
5. **Bounded disk and memory.** Every service has `mem_limit`, log rotation and a
   retention/size cap. The target host is 4–6 GB.
6. **Collector configs are baked into the image.** Change
   `configs/fluent-bit/` and rebuild; never bind-mount over them at runtime.
7. **Keep `required_providers { oci = { source = "oracle/oci" } }` in every
   module.** Without it, modules silently resolve `hashicorp/oci`.
8. **No state in Git.** `*.tfstate`, `*.tfplan`, `*.tfvars` and `.terraform/` stay
   ignored; `.terraform.lock.hcl` is committed.
9. **Loki is unauthenticated.** It binds to `127.0.0.1` and the security list
   carries no `3100` rule; reach it with `ssh -L 3100:localhost:3100`. The module
   rewrites a `0.0.0.0/0` CIDR to the private subnet if one is supplied.

---

## Known limitations

- Container **names** are not in Docker's log records; filter with
  `|= "container_log" |= "<substring>"`.
- Multi-line logs (stack traces) are stored line by line.
- Containers that start and are removed within about a second
  (`docker run --rm ...` with no sleep) can be missed: their `*-json.log` file is
  deleted before the collector opens it. Long-lived containers and services are
  captured normally.
- The collector's own container logs are collected too (`cg-fluent-bit`).
- Single-binary Loki with filesystem storage cannot scale horizontally.
- No TLS: terminate HTTPS at a reverse proxy before public exposure.
- Cloud-init installs Docker but does **not** deploy the stack — Phase 4 does.
- The Grafana admin password is passed through `.env` on the host; rotate it there
  and in `GF_SECURITY_ADMIN_PASSWORD` together.

---

## Report template

When you finish, report exactly this, filled with real output — no adjectives:

```text
Phase 0 preflight      : PASS/FAIL — <one line of evidence>
Phase 1 compose init   : PASS/FAIL — <containers up, probe results>
Phase 2 ingestion      : PASS/FAIL — <query returned the smoke stamp? labels seen?>
Phase 3 tofu           : PASS/FAIL — <fmt/validate/plan result; resources planned; applied? approved by whom>
Phase 4 host deploy    : PASS/FAIL — <public IP, container count, remote probe results>
Phase 5 teardown       : PASS/FAIL — <state list empty, containers removed>

Not performed           : <phases skipped, and why>
Deviations from guide   : <any command you altered and why>
Follow-ups / risks      : <e.g. Loki 3100 still open to 0.0.0.0/0>
```

A phase is only `PASS` if the command that proves it ran in this session.
