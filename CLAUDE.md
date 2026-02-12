# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Wiz Technical Exercise v4** — two-tier web app on GCP with intentional security misconfigurations. Full spec in `Wiz_Tech_Exercise_V4.pdf`.

## Architecture

```
Internet → GCP HTTP LB → GKE (private subnet) → bucket-list app (Node.js)
                                                        ↓
                          VM (public subnet) ────→ MongoDB 6.0
                                                        ↓
                                                  cron backup → GCS bucket (public)
```

## Intentional Misconfigurations (do NOT fix)

- VM: Ubuntu 22.04 (outdated), MongoDB 6.0 (EOL Aug 2025), SSH open to `0.0.0.0/0`
- VM service account: `roles/compute.admin` (overly permissive)
- GCS backup bucket: public read + public listing (`allUsers`)
- K8s: `cluster-admin` ClusterRoleBinding for the app SA (`k8s/rbac.yaml`)
- App: three NoSQL injection surfaces (see below)

## Secure Configurations (must stay correct)

- MongoDB accepts connections only from GKE pod CIDR (`10.4.0.0/14`)
- MongoDB authentication enabled (admin + app user)
- GKE private nodes, control plane audit logging (`APISERVER`, `SYSTEM_COMPONENTS`, `WORKLOADS`)
- `wizexercise.txt` in container image
- **Preventative**: Binary Authorization — GKE only runs attested images (no critical CVEs)
- **Preventative**: Firewall restricting MongoDB to K8s network only
- **Detective**: GKE Security Posture with vulnerability scanning
- **Detective**: Artifact Registry automatic vulnerability scanning

## Key Conventions

- **Passwords**: use diceware-style (no special chars like `!#@`) — terraform `templatefile()` + GCP metadata mangles shell-special characters
- **K8s deploys**: use Kustomize (`kubectl apply -k k8s/`), CI overrides image with `kustomize edit set image`
- **Secrets**: `MONGO_URI` passed via K8s Secret (`mongo-credentials`), NOT hardcoded in manifests
- **authSource**: app user is created on `bucketlist` db, so use `authSource=bucketlist` (not `admin`)
- **Docker tools**: `docker build -f Dockerfile.tools -t wiz-tools .` — has gcloud, kubectl, terraform, jq
- **Terraform state**: GCS backend (`gs://clgcporg10-171-terraform-state`)

## Application: bucket-list

`bucket-list/` — Node.js + Express SPA backed by MongoDB.

### Local Dev

```bash
cd bucket-list && docker compose up    # app at localhost:3000
```

### Env Vars

`MONGO_URI` (full connection string) or individual: `MONGO_HOST`, `MONGO_PORT`, `MONGO_USER`, `MONGO_PASSWORD`, `MONGO_DB`. `PORT` defaults to 3000.

### NoSQL Injection (intentional — do NOT patch)

1. `GET /api/tasks?status[$ne]=done` — query param operator injection
2. `POST /api/tasks/search` — request body forwarded as raw MongoDB `find()` query
3. `PUT /api/tasks/:id` — request body forwarded as raw MongoDB update (`$set`, `$unset`, etc.)

### API Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tasks` | List tasks (filterable via query params) |
| POST | `/api/tasks` | Create task |
| POST | `/api/tasks/search` | Search (raw MongoDB query) |
| PUT | `/api/tasks/:id` | Update task |
| DELETE | `/api/tasks/:id` | Delete task |
| GET | `/api/health` | Health / DB connectivity check |

## CI/CD Pipelines

### Container Pipeline (`.github/workflows/docker-build-push.yml`)

Triggers on push to `main` (paths: `bucket-list/**`). Steps: build → push to AR → verify wizexercise.txt → vuln scan gate → Binary Authorization attestation → deploy to GKE via kustomize.

Uses `ci-pipeline-sa` with: `artifactregistry.writer`, `containeranalysis.*`, `binaryauthorization.attestorsVerifier`, `cloudkms.signerVerifier`, `container.developer`.

### Terraform Pipeline (`.github/workflows/terraform.yml`)

Triggers on push/PR to `main` (paths: `terraform/**`). Plan on PR (comments on PR), apply on merge. Uses `terraform-sa` with: `editor`, `projectIamAdmin`, `serviceUsageAdmin`, `cloudkms.viewer`, `cloudkms.publicKeyViewer`.

### GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `GCP_SA_KEY` | CI pipeline SA JSON key |
| `GCP_TERRAFORM_SA_KEY` | Terraform SA JSON key |
| `GCP_PROJECT_ID` | `clgcporg10-171` |
| `MONGO_ADMIN_PASSWORD` | MongoDB admin password |
| `MONGO_APP_PASSWORD` | MongoDB app password |

## Infrastructure (Terraform)

| File | Resources |
|------|-----------|
| `vpc.tf` | VPC, subnets (public `10.0.1.0/24`, private `10.0.2.0/24`), firewall, Cloud NAT |
| `gke.tf` | Private GKE cluster, node pool, Binary Authorization enforcement |
| `vm.tf` | MongoDB VM (Ubuntu 22.04, e2-medium), startup script |
| `storage.tf` | GCS backup bucket (public read/list) |
| `iam.tf` | Service accounts: `mongo-vm-sa`, `ci-pipeline-sa`, `terraform-sa` + all IAM bindings |
| `artifact-registry.tf` | Docker repo + Container Scanning APIs |
| `binary-authorization.tf` | KMS key, attestor, Binary Authorization policy |
| `scripts/mongo-startup.sh` | MongoDB 6.0 install, auth setup, daily backup cron to GCS |

## K8s Manifests

| File | Purpose |
|------|---------|
| `k8s/deployment.yaml` | App deployment (2 replicas), image templated via Kustomize |
| `k8s/service.yaml` | ClusterIP port 80 → 3000 |
| `k8s/ingress.yaml` | GCE Ingress (HTTP LB) |
| `k8s/rbac.yaml` | ServiceAccount + `cluster-admin` binding (intentional) |
| `k8s/kustomization.yaml` | Kustomize config for all manifests |
