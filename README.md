# Centralized Log Aggregator

![Status](https://img.shields.io/badge/stage-7%20%C2%B7%20audited%20%26%20documented-2EA043)
![Certified on OCI](https://img.shields.io/badge/production%20verification-OCI%20trial%20credits-0066FF)
![Cloud agnostic](https://img.shields.io/badge/infrastructure-cloud--agnostic-6E7781)
![Monthly cost](https://img.shields.io/badge/estimated%20cost-%240.00%20%2F%20month-brightgreen)

![Loki](https://img.shields.io/badge/Grafana%20Loki-3.2.1-F5A800?logo=grafana&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-11.3.1-F46800?logo=grafana&logoColor=white)
![Fluent Bit](https://img.shields.io/badge/Fluent%20Bit-3.1.9-49BDA5)
![Docker Compose](https://img.shields.io/badge/Docker%20Compose-stack-2496ED?logo=docker&logoColor=white)
![OpenTofu](https://img.shields.io/badge/IaC-OpenTofu%20%E2%89%A5%201.6-FFDA18)
![Audit](https://img.shields.io/badge/zero--leak-audit%20passed-success)

A portable, cloud-agnostic log pipeline: **Fluent Bit** collects container logs,
**Grafana Loki** stores and indexes them, and **Grafana** queries them with Loki
provisioned as the default data source — running unchanged on a laptop, on Oracle
Cloud Infrastructure, or on any host with Docker.

Part of the **CloudGuard** portfolio. Certified `PORTABLE_CERTIFIED` (100/100)
by CloudGuard's portability audit, deployed and verified on OCI Always Free.

---

## 📖 Overview

Container logs are the cheapest debugging tool you own and the easiest thing to
lose: `docker logs` only reaches back to the running container, `json-file` logs
rotate away, and every host has its own island of history. This project is the
smallest serious answer to that — a three-container pipeline you can run on a
free-tier VM and keep for as long as the VM lives.

It is deliberately **not** a Kubernetes stack, an ELK cluster, or a SaaS
integration. There is no agent to install on application hosts, no proprietary
query language to learn, and no vendor account required. Logs land in LogQL,
which is queryable over plain HTTP and visualisable in Grafana.

**Design goals:** $0.00/month on Always Free tiers · one `docker compose up` ·
no credential can be committed · identical behaviour on every cloud.

---

## 🏗 Architecture

```text
[Application/System Logs] --> [Fluent Bit Agent] --> [Grafana Loki (Port 3100)] --> [Grafana Dashboard (Port 3000)]
```

In context, on a single host:

```text
┌────────────────────────────────── one Docker host ──────────────────────────────────┐
│                                                                                     │
│  /var/lib/docker/containers/*/*-json.log                                            │
│              │  read-only mount — no Docker socket, no control-plane access         │
│              ▼                                                                      │
│  ┌────────────────────┐   HTTP push    ┌────────────────────────┐   LogQL   ┌──────────────────────┐
│  │  Fluent Bit Agent  │───────────────▶│  Grafana Loki          │──────────▶│  Grafana Dashboard   │
│  │  tail → parse →    │  labels: job,  │  (Port 3100)           │           │  (Port 3000)         │
│  │  label → buffer    │  host, cluster │  TSDB index            │           │  Loki = default DS   │
│  └─────────┬──────────┘  stream        │  filesystem store      │           └──────────────────────┘
│            │                           │  14-day retention      │
│            ▼                           └───────────┬────────────┘
│   filesystem buffer                                │ compaction + retention
│   (256 MB cap, survives Loki downtime)             ▼
│                                            /loki (named volume)
└─────────────────────────────────────────────────────────────────────────────────────┘
       :2020 loopback (health)              :3100 loopback only (SSH tunnel)               :3000 published
```

| Stage | Component | Responsibility | Port |
| ----- | --------- | -------------- | ---- |
| 1 | `fluent-bit` | Read Docker JSON logs, parse timestamps, attach labels, buffer and ship | `2020` (loopback health) |
| 2 | `loki` | Index streams (TSDB) and store chunks on disk, enforce retention and rate limits | `3100` |
| 3 | `grafana` | Explore/dashboard UI, provisioned with Loki as the default data source | `3000` |

A collection stage, a storage stage and a presentation stage — each replaceable
without touching the others.

---

## ✨ Features

**Collection**

- Tails Docker's `json-file` logs through a `docker` parser that extracts the
  message, stream and timestamp from the JSON envelope, so Grafana shows event
  time rather than collection time.
- **Filesystem buffer** (256 MB cap) with infinite retry: a Loki restart does not
  lose logs, and a full buffer drops new lines instead of filling the root disk.
- **Low-cardinality labels only** — `job`, `cluster`, `host`, `stream` (plus the
  constant `service_name` the Loki output adds). Container paths stay a log
  field, so precise filtering costs nothing in stream count.
- **No Docker socket.** The collector mounts `/var/lib/docker/containers`
  read-only; a compromised collector cannot start, stop or exec containers.

**Storage**

- Loki single-binary with **TSDB v13** index and filesystem object store — no
  Cassandra, no S3 bucket, no external dependency.
- **14-day retention** enforced by the compactor (`delete_request_store` set, as
  Loki 3.x requires), plus ingestion/stream rate limits so one noisy producer
  cannot swap the host.
- WAL enabled: in-flight chunks survive a restart.

**Visualisation**

- Grafana **provisioned as code**: Loki is the default data source from first
  boot; no click-through setup, no manual datasource wiring.
- Works in Explore out of the box: `{job="fluentbit"}`.

**Operations**

- One command to start, one to stop: `docker compose up -d` / `down`.
- Every service has `mem_limit`, `cpus`, `no-new-privileges` and `json-file` log
  rotation (`10m × 2`), so the host cannot be starved by its own logging stack.
- Measured idle footprint: **~151 MiB RSS total** (Loki 56, Grafana 66,
  Fluent Bit 29 MiB) — sized for a 1 OCPU / 6 GB Always Free instance.

**Infrastructure & security**

- **OpenTofu/Terraform** (≥ 1.6) provisions VCN, internet gateway, route table,
  security list (22 and 3000; Loki's `3100` is closed by default), public subnet
  and an A1.Flex instance with cloud-init; outputs the public IP and endpoints.
- **Zero-leak boundary**: strict `.gitignore`, placeholder-only `.env.example`,
  no `.env` or Terraform state in history, no key material in the tree.
- **AI-agent ready**: `AGENT_GUIDE.md` is an executable playbook with stop
  conditions; `MANUAL_PREREQS.md` is the human checklist that gates provisioning.

---

## 🚀 Quick start (any cloud, any laptop)

Two audiences, two entry points: humans work through
[`MANUAL_PREREQS.md`](MANUAL_PREREQS.md) first, then AI agents (Cursor, Claude
Code, Windsurf) follow [`AGENT_GUIDE.md`](AGENT_GUIDE.md) phase by phase.

```bash
git clone https://github.com/kaveh8866/Centralized-Log-Aggregator.git
cd Centralized-Log-Aggregator

cp .env.example .env          # set a real GRAFANA_ADMIN_PASSWORD
docker compose --env-file .env -f docker/docker-compose.yml config --quiet
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
```

Open <http://localhost:3000>, go to **Explore**, pick **Loki**, query:

```logql
{job="fluentbit"}
```

Health and ingestion checks:

```bash
curl -s localhost:3100/ready                  # ready
curl -s localhost:2020/api/v1/health          # ok
curl -s localhost:3000/api/health             # {"database":"ok",...}

# prove end-to-end ingestion
docker run --rm --name cg-smoke alpine:3.20 sh -c 'echo cloudguard-smoke; sleep 5'
NOW=$(date +%s)
curl -sG localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="fluentbit"} |= "cloudguard-smoke"' \
  --data-urlencode "start=$((NOW - 600))000000000" \
  --data-urlencode "end=${NOW}000000000"
```

**Port conflict on 3000?** Remap instead of stopping the other service —
`GRAFANA_PORT=3001` and `LOKI_PORT=3101` in `.env`. Container-internal ports
never change.

---

## ☁ Provision on OCI

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # tenancy, compartment, region, SSH public key
tofu init && tofu validate
tofu plan && tofu apply
tofu output connection_endpoints
```

Creates: VCN `10.0.0.0/16`, internet gateway, route table, security list
(**22 and 3000**; Loki's `3100` stays closed), public subnet `10.0.1.0/24`, one `VM.Standard.A1.Flex`
(1 OCPU / 6 GB / 50 GB, Ubuntu 24.04 aarch64) bootstrapped with Docker via
cloud-init.

Then deploy the stack onto the host:

```bash
ssh ubuntu@$(tofu output -raw instance_public_ip)
git clone https://github.com/kaveh8866/Centralized-Log-Aggregator.git
cd Centralized-Log-Aggregator && cp .env.example .env
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
```

Capacity notes, guardrails and the AWS/GCP resource mapping live in
[`terraform/README.md`](terraform/README.md).

### Deployment record

| Item | Value |
| ---- | ----- |
| Environment | OCI Always Free, `eu-frankfurt-1`, `jiTx:EU-FRANKFURT-1-AD-2` |
| Shape | `VM.Standard.A1.Flex` — 1 OCPU / 6 GB / 50 GB boot |
| Endpoints (while live) | Grafana `:3000` only — Loki `:3100` was loopback-bound and closed at the security list |
| Loki access | `ssh -L 3100:localhost:3100 ubuntu@<ip>`, then `http://localhost:3100` |
| Provisioning | `tofu apply` → 6 resources added; `tofu plan` → no drift |
| Status | Grafana health 200 (public), Loki `/ready` ready over loopback, live logs queryable |
| Teardown | `tofu destroy` → 6/6 resources destroyed; endpoints unreachable, trial burn back to $0.00 |

---

## 📂 Repository layout

```text
.
├── Dockerfile                     # Fluent Bit collector image (configs baked in)
├── .dockerignore                  # build context = configs/fluent-bit only
├── .env.example                   # placeholder-only environment template
├── .gitignore                     # zero-leak boundary (keys, state, runtime data)
├── README.md
├── AGENT_GUIDE.md                 # AI-agent execution playbook (phases 0-5)
├── MANUAL_PREREQS.md              # human setup checklist that gates provisioning
├── configs/
│   ├── fluent-bit/
│   │   ├── fluent-bit.conf        # tail → record_modifier → loki output
│   │   └── parsers.conf           # Docker json-file parser
│   ├── loki/loki-config.yml       # single binary, TSDB, retention, limits
│   └── grafana/provisioning/datasources/loki.yml
├── docker/
│   └── docker-compose.yml         # the stack (Compose Spec, no `version:` key)
└── terraform/                     # OpenTofu ≥ 1.6 root module (OCI)
    ├── versions.tf · providers.tf · variables.tf · main.tf · outputs.tf
    ├── cloud-init.yaml.tftpl      # first-boot Docker + firewall bootstrap
    ├── terraform.tfvars.example   # copy to terraform.tfvars (gitignored)
    └── modules/{network,compute}/ # VCN/IGW/security list · A1.Flex instance
```

| Document | Audience |
| -------- | -------- |
| [`AGENT_GUIDE.md`](AGENT_GUIDE.md) | AI coding agents executing phases 0–5, with troubleshooting and a report template |
| [`MANUAL_PREREQS.md`](MANUAL_PREREQS.md) | Humans: OCI API key, IAM policy, `.env`, `terraform.tfvars`, preflight |
| [`terraform/README.md`](terraform/README.md) | IaC usage, free-tier guardrails, AWS/GCP port mapping |

---

## ⚙️ Configuration

All runtime knobs come from `.env` (see `.env.example`). Every value has a
working compose default, so the stack starts without the file — but never expose
a public host with the default Grafana password.

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `GRAFANA_ADMIN_USER` | `admin` | Grafana console user |
| `GRAFANA_ADMIN_PASSWORD` | *(placeholder)* | **must be changed** |
| `GRAFANA_ROOT_URL` | `http://localhost:3000` | public URL of the UI |
| `GRAFANA_PORT` / `LOKI_PORT` | `3000` / `3100` | published host ports |
| `FLUENT_BIT_HTTP_PORT` | `2020` | loopback-only health endpoint |
| `LOG_HOST_LABEL` / `LOG_CLUSTER_LABEL` | `docker-host` / `cloudguard-logs` | Loki labels injected by the collector |
| `OCI_*` | *(placeholders)* | Stage 2 provisioning inputs; the compose stack does not read them |

---

## 🧠 Design decisions

**Configs are baked into the collector image.** The same image runs on OCI, AWS,
GCP or a laptop, so parsing and labelling cannot drift between environments.
Edit `configs/fluent-bit/`, then rebuild (`--build`).

**Labels stay low-cardinality.** `job`, `cluster`, `host`, `stream` are the only
configured labels (`service_name` is added by Fluent Bit's Loki output and stays
constant). Filter on container identity through the record field instead (`Path_Key`
preserves each container's log path as `container_log`):

```logql
{job="fluentbit"} | json | container_log =~ ".*payments-api.*"
```

**Loki is not exposed by design.** It has no authentication in this stage, so it
binds to `127.0.0.1` on the host, the security list has no `3100` rule, and remote
access goes through `ssh -L 3100:localhost:3100`. `enable_loki_ingress` defaults
to `false`, and the network module rewrites a `0.0.0.0/0` CIDR to the private
subnet, so the rule cannot be opened to the internet even by a stale tfvars.

**Retention is a disk policy, not a feature flag.** 14 days, compactor-enforced,
with a 256 MB shipping buffer — both numbers chosen so a 50 GB boot volume holds
weeks of container logs without manual pruning.

---

## 🖥 Sizing & measured footprint

| Service | `mem_limit` | `cpus` | Measured idle RSS |
| ------- | ----------- | ------ | ----------------- |
| `fluent-bit` | 256 MB | 0.5 | 28.8 MiB |
| `loki` | 512 MB | 0.75 | 56.1 MiB |
| `grafana` | 384 MB | 0.5 | 66.3 MiB |
| **Total** | **1.1 GB** | **1.75** | **~151 MiB** |

Fits a **1 OCPU / 6 GB** instance comfortably and leaves headroom on a full
Always Free A1 allowance. Because the configured limits sum to 1.1 GB, a
1 GB-RAM free-tier shape (AWS `t3.micro`, GCP `e2-micro`) cannot run this stack
without lowering those limits.

---

## 🔒 Security & zero-leak policy

- `.env` is never committed; `.env.example` contains **14 placeholder keys**, no
  duplicates, no live signatures.
- `.gitignore` blocks credentials (`*.pem`, `*.key`, `*.p12`), local databases
  (`*.db`, `*.sqlite`), Terraform state (`*.tfstate`, `*.tfplan`, `*.tfvars`,
  `.terraform/`), local `keys/` and runtime data directories.
- Grafana: sign-up disabled, anonymous access disabled, no analytics.
- All three containers run with `no-new-privileges`; the collector has no Docker
  socket.
- OCI credentials are supplied at deploy time (`~/.oci/config` or environment),
  never by this repository. The Terraform provider block reads variables only.

**Audit result (Stage 7, 2026-11-12)** — scan of the whole workspace:

| Check | Result |
| ----- | ------ |
| Key/certificate material (`*.pem`, `*.key`, `*.p12`, `id_rsa*`) | **none found** |
| Files tracked by Git | 29 — no `.env`, no `*.tfvars`, no state |
| Secret paths in Git history | **none** |
| `.gitignore` effectiveness (`git check-ignore`) | `.env`, `.env.local`, `*.tfvars`, `*.tfstate`, `*.tfplan`, `keys/*.pem`, `*.log` all **ignored** |
| `.env.example` structure | 14 keys · 15 comment/blank lines · **0 duplicates** · placeholder-only values |
| Signature scan of all docs/configs (keys, tokens, OCIDs, passwords) | **clean** — 1 hit, the intentional `your_grafana_admin_password_here` placeholder |
| CloudGuard portability audit | `PORTABLE_CERTIFIED` — 100/100 (5/5 checks) |

A local `.env` and `terraform/terraform.tfstate` exist on a working machine and
are both gitignored; neither is ever committed.

---

## 🌍 Cloud-Agnostic Portability Note

The infrastructure is written in **OpenTofu** and the runtime is plain **Docker
Compose**. No cloud SDK, provider-specific image, region or credential appears in
`docker/`, `configs/` or the `Dockerfile`. Cloud-specific code is confined to the two
`terraform/modules/*` modules and the provider-shaped root variables, so
retargeting means swapping those modules — not rewriting the pipeline.

> **Certification scope.** While the infrastructure is cloud-agnostic and
> deployable on AWS, GCP, Azure or bare metal, **final production verification
> and testing certification for this project were performed strictly on Oracle
> Cloud Infrastructure (OCI), using OCI trial credits.** OCI is the validated
> environment: it is where the stack was provisioned with OpenTofu, smoke-tested,
> and signed off. AWS and GCP are **documented ports, not certified targets** —
> they carry no test evidence in this repository, and this project must not be
> described as "AWS-verified" or "GCP-verified".

### Migration tips

**AWS (EC2 + VPC)**

1. Replace `modules/network` with `aws_vpc` + `aws_internet_gateway` +
   `aws_route_table` + `aws_security_group` + `aws_subnet`; keep the same ingress
   contract (22 and 3000).
2. Replace `modules/compute` with `aws_instance`. Use `t4g.small` (arm64) or a
   size with **≥ 4 GB RAM** — `t3.micro` has 1 GB, below this stack's limits.
3. Drop the OCI identity variables; authenticate with `AWS_PROFILE`, environment
   credentials or an instance role. Replace `oci_core_images` with
   `data "aws_ami"` filtered by architecture.
4. `instance_type` replaces `instance_ocpus`/`instance_memory_gbs`;
   `root_block_device.volume_size` replaces `boot_volume_size_gbs`;
   `availability_zone` replaces `availability_domain`.
5. Cloud-init: `docker-compose-v2` is an Ubuntu package name — on Amazon Linux,
   install Docker CE and the compose plugin from Docker's repository instead.

**GCP (Compute Engine + VPC)**

1. `google_compute_network` + `google_compute_firewall` (22 and 3000) +
   `google_compute_subnetwork`; no explicit internet gateway is needed.
2. `google_compute_instance` with `machine_type = "e2-medium"` (4 GB) — `e2-micro`
   is 1 GB. Use `data "google_compute_image"` with an `ubuntu-2404` family and
   select the `arm64` build if you choose Tau T2A.
3. Authenticate with `project` + Application Default Credentials; delete the OCI
   identity variables.
4. `metadata_startup_script` replaces `metadata.user_data`;
   `boot_disk.initialize_params.size` replaces `boot_volume_size_gbs`; `zone`
   replaces `availability_domain`.
5. Egress: GCP's free allowance is ~1 GB/month — a log UI generating tens of GB
   of responses will bill; keep Grafana behind a VPN or a private IP.

Full resource-by-resource mapping: [`terraform/README.md`](terraform/README.md#porting-to-aws-or-gcp).

---

## 💰 Cross-Cloud Cost & Benchmark Estimation

Monthly estimate for **this tested footprint** — 1 vCPU, 6 GB RAM, 50 GB disk,
1 instance running 24/7 (730 h), 50 GB/month egress — on each provider's free-tier
shape and on the closest shape that can actually run the stack.

| Provider | Shape (free tier) | vCPU | RAM | Disk | Egress allowance | Est. monthly cost | Can it run this stack? |
| -------- | ----------------- | ---- | --- | ---- | ---------------- | ----------------- | ---------------------- |
| **OCI** — Always Free *(tested)* | `VM.Standard.A1.Flex` | 1 | 6 GB | 50 GB (of 200 GB free) | **10 TB/mo free** | **$0.00** | ✅ exact tested footprint |
| **OCI** — trial credits | any paid shape, e.g. `VM.Standard.E4.Flex` | 1 | 6 GB | 50 GB | 10 TB/mo free | **$0.00 out of pocket** while prepaid credits last | ✅ (headroom for A1 capacity gaps) |
| **AWS** | `t3.micro` + gp3 EBS | 2 (burst) | 1 GB | 50 GB | 100 GB/mo free | **$11.59** (VM $7.59 + EBS $4.00) | ❌ 1 GB < 1.1 GB of configured limits |
| **AWS** — closest fit | `t3.medium` + gp3 EBS | 2 | 4 GB | 50 GB | 100 GB/mo free | **$34.37** (VM $30.37 + EBS $4.00) | ✅ (tight; 8 GB not offered on t3) |
| **GCP** | `e2-micro` + pd-standard | 2 (shared) | 1 GB | 50 GB | ~1 GB/mo free (NA) | **$6.68–$12.79** ($0 VM in `us-central1` free tier, else $6.11; disk $0.80 after 30 GB free; egress $5.88) | ❌ 1 GB < 1.1 GB of configured limits |
| **GCP** — closest fit | `e2-medium` + pd-standard | 2 | 4 GB | 50 GB | ~1 GB/mo free (NA) | **≈$24.50 + $2 disk + $5.88 egress** (verify on the calculator) | ✅ |

**Benchmark notes (measured, not estimated)**

- Idle RSS across all three containers: **151 MiB** (measured with `docker stats`
  after the Stage 4 run).
- Stage 4 throughput: **1,418 log lines** from the stack's own containers were
  ingested and counted within minutes of first boot on a 1 OCPU host.
- That rate is orders of magnitude below Loki's configured `4 MB/s` per-tenant
  and `3 MB/s` per-stream limits, so the practical ceiling on this shape is disk
  throughput and retention size, not CPU.

**Assumptions & caveats**

- Prices are public on-demand list prices for **November 2026** in AWS
  `us-east-1` (t3.micro $0.0104/h, gp3 $0.08/GB-month), GCP `us-central1`
  (e2-micro $0.0084/h, pd-standard $0.04/GB-month, egress $0.12/GB), OCI home
  region Always Free. Linux, 730 h/month, exclusions: tax, support plans,
  snapshots.
- AWS free tier is credit/12-month based for new accounts — the table shows the
  list price, i.e. what you pay after it expires.
- OCI meters the A1 allowance as **1,500 OCPU-hours and 9,000 GB-hours per
  month** (≈ 2 OCPU / 12 GB running continuously; earlier docs stated a flat
  4 OCPU / 24 GB). This deployment uses 730 OCPU-hours and 4,380 GB-hours —
  about **49 % of both budgets**, so it stays free with room for a second
  instance. Keep `instance_ocpus × 730 ≤ 1500` if you resize.
- Verify with the providers' calculators before committing budget; prices and
  free-tier terms change.

---

## ✅ Verified results

| Stage | Check | Result |
| ----- | ----- | ------ |
| 1 | Portability audit (CloudGuard) | `PORTABLE_CERTIFIED`, 100/100, 5/5 checks |
| 1 | Compose validity | `docker compose config --quiet` exit 0 |
| 4 | Local stack | 3 containers up, Loki `/ready` 200, Grafana health 200 |
| 4 | Local ingestion | Smoke line retrieved from Loki; 1,418 lines / 697 KB counted |
| 4 | Grafana datasource | Provisioned `Loki`, `isDefault=true`, proxied LogQL 200 |
| 5 | OCI provisioning | `tofu apply` → 6 resources; `tofu plan` → no drift |
| 5 | OCI health | Grafana `:3000/api/health` 200 (public); Loki `/ready` ready over loopback |
| 5 | OCI ingestion | Live container log retrieved through Loki with `host=oci-log-aggregator-01` |
| 7 | Zero-leak audit | 29 tracked files, no keys, no secret in history, ignore boundary verified |
| 8 | Network hardening | `:3100` from the internet → blocked (HTTP 000); Loki listens on `127.0.0.1` only; Grafana→Loki datasource health OK |

Not verified: AWS/GCP deployments, ARM64 runtime behaviour on the cloud instance
(the OCI host is ARM and the containers run there, but no ARM-specific test
matrix exists), TLS/DNS, and Grafana dashboards (Stage 5 of the roadmap).

---

## 🧰 Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `port is already allocated` on 3000/3100 | Another service owns the host port | Set `GRAFANA_PORT`/`LOKI_PORT` in `.env`, or stop the other stack |
| No logs in Grafana | Container log driver is not `json-file` | `docker info --format '{{.LoggingDriver}}'` |
| `failed to flush chunk` repeatedly | Loki not ready, or host name wrong | `docker compose logs loki`; output must target host `loki` |
| `{job="fluentbit"}` empty after restart | Loki replaying its WAL | Wait ~30 s, re-run the query |
| Very short-lived `--rm` containers missing | Log file deleted before the collector opens it | Keep the container alive a few seconds, or run it without `--rm` |
| Loki exits: `delete request store not set` | Loki ≥ 3.0 requirement | Keep `delete_request_store: filesystem` |
| `500-InternalError, Out of host capacity.` | No A1 capacity in that AD | Retry another `availability_domain`, then pin it in `terraform.tfvars` |
| Docker missing but `cloud-init status: done` | `#cloud-config` not on line 1 of user-data | Keep the marker first; check `/var/log/cloud-init-output.log` |
| `401-NotAuthenticated` from OpenTofu | Key/fingerprint mismatch or unreadable key | Regenerate the API key pair; `chmod 600` the private key |

Full playbooks: [`AGENT_GUIDE.md`](AGENT_GUIDE.md#troubleshooting) and
[`MANUAL_PREREQS.md`](MANUAL_PREREQS.md#troubleshooting).

---

## 🗺 Roadmap

| Stage | Scope |
| ----- | ----- |
| **1** | ✅ Scaffold, container stack, portability profile |
| **2** | ✅ OpenTofu/Terraform: OCI VCN, IGW, security list, A1.Flex instance, cloud-init |
| **3** | ✅ Agent playbook (`AGENT_GUIDE.md`) + operator checklist (`MANUAL_PREREQS.md`) |
| **4** | ✅ Live OCI deployment — health, ingestion and Grafana verified over the public internet |
| **5** | Grafana dashboards-as-code and alert rules |
| **6** | Remote Loki object storage (S3-compatible) and HTTPS reverse proxy |
| **7** | ✅ Zero-leak audit, README, cross-cloud cost benchmark |

---

<sub>Built for the CloudGuard portfolio. Verified on OCI Always Free — running cost $0.00/month.</sub>
