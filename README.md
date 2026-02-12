# Wiz Technical Exercise v4

Two-tier web application deployed on GCP with intentional security misconfigurations for demonstration purposes.

## Architecture

```
Internet → GCP HTTP LB → GKE (private subnet) → bucket-list app (Node.js)
                                                        ↓
                          VM (public subnet) ────→ MongoDB 6.0
                                                        ↓
                                                  cron backup → GCS bucket (public)
```

## Components

| Component | Details |
|-----------|---------|
| **App** | Node.js/Express SPA (`bucket-list/`) — task manager backed by MongoDB |
| **GKE Cluster** | Private cluster in `10.0.2.0/24`, exposed via GCE Ingress (HTTP LB) |
| **MongoDB VM** | Ubuntu 22.04, MongoDB 6.0, public IP, in `10.0.1.0/24` |
| **GCS Bucket** | Daily `mongodump` backups via cron |
| **Artifact Registry** | Docker repo for the app container image |

## Intentional Misconfigurations

These are **required** by the exercise spec — do not fix:

- VM runs Ubuntu 22.04 (1+ year outdated — 24.04 LTS available)
- MongoDB 6.0 (EOL Aug 2025)
- SSH open to `0.0.0.0/0` on the VM
- VM service account has `roles/compute.admin` (can create/manage VMs)
- GCS backup bucket allows public read and public listing
- App has `cluster-admin` ClusterRoleBinding in Kubernetes

## Secure Configurations

- MongoDB accepts connections only from the GKE pod CIDR (`10.4.0.0/14`)
- MongoDB authentication enabled (admin + app user)
- GKE cluster uses private nodes
- Control plane audit logging enabled (`APISERVER`, `SYSTEM_COMPONENTS`, `WORKLOADS`)
- **Preventative control**: Binary Authorization — GKE only runs images attested by the CI pipeline after passing vulnerability scan (no critical CVEs)
- **Preventative control**: Firewall restricting MongoDB to K8s network only
- **Detective control**: GKE Security Posture with vulnerability scanning
- **Detective control**: Artifact Registry automatic vulnerability scanning

## Local Development

```bash
cd bucket-list
docker compose up
```

App at http://localhost:3000 with a local MongoDB. No GCP needed.

## Prerequisites

- Docker
- GCP project with billing enabled
- `gcloud auth application-default login` completed

### Tools Container

A Docker-based toolbox with terraform, kubectl, and gcloud:

```bash
docker build -f Dockerfile.tools -t wiz-tools .
docker run --rm -it -v "$(pwd):/workspace" -v "$HOME/.config/gcloud:/root/.config/gcloud" -v "$HOME/.kube:/root/.kube" wiz-tools
```

## Deployment

### 1. Provision Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and passwords

terraform init
terraform apply
```

### 2. Connect to GKE

```bash
gcloud container clusters get-credentials wiz-gke --zone us-central1-a --project <PROJECT_ID>
```

### 3. Create Kubernetes Secret

The app reads `MONGO_URI` from a Kubernetes Secret. Build the URI from Terraform outputs:

```bash
MONGO_IP=$(terraform -chdir=terraform output -raw mongo_vm_internal_ip)
MONGO_USER=$(terraform -chdir=terraform output -raw mongo_app_user)
MONGO_PASS=$(terraform -chdir=terraform output -raw mongo_app_password)

kubectl create secret generic mongo-credentials \
  --from-literal=MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASS}@${MONGO_IP}:27017/bucketlist?authSource=bucketlist"
```

> **Note:** If your password contains `@`, `:`  or `/`, URL-encode those characters (e.g. `@` → `%40`).

### 4. Deploy to Kubernetes

Push to `main` triggers the CI pipeline which builds, scans, attests, and deploys automatically. For the initial deploy or manual deploys:

```bash
kubectl apply -k k8s/
```

### 5. Verify

```bash
# Get the load balancer IP (may take a few minutes)
kubectl get ingress bucket-list

# Check public bucket access
gsutil ls gs://<PROJECT_ID>-wiz-backups
```

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/docker-build-push.yml`) runs on push to `main`:

1. **Build & push** — builds container, tags with commit SHA + `latest`, pushes to Artifact Registry
2. **Verify** — confirms `wizexercise.txt` is in the image
3. **Vulnerability scan gate** — waits for GCP Container Scanning, fails on critical CVEs
4. **Binary Authorization attestation** — signs the image with a KMS key so GKE accepts it
5. **Deploy to GKE** — `kustomize edit set image` + `kubectl apply -k` with the attested image digest

Required GitHub secrets: `GCP_SA_KEY` (CI service account JSON key), `GCP_PROJECT_ID`

## Project Structure

```
├── bucket-list/           # Node.js app (Express + MongoDB)
│   ├── Dockerfile
│   ├── server.js
│   └── public/            # SPA frontend
├── terraform/             # IaC (GCP)
│   ├── main.tf            # Provider config
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Useful outputs
│   ├── vpc.tf             # VPC, subnets, firewall, Cloud NAT
│   ├── gke.tf             # GKE private cluster + node pool
│   ├── vm.tf              # MongoDB VM (Ubuntu 22.04)
│   ├── storage.tf         # GCS backup bucket (public)
│   ├── iam.tf             # Service accounts + IAM
│   ├── artifact-registry.tf
│   ├── binary-authorization.tf  # KMS key, attestor, policy
│   └── scripts/
│       └── mongo-startup.sh  # MongoDB install, auth, backup cron
├── k8s/                   # Kubernetes manifests
│   ├── deployment.yaml    # App deployment
│   ├── service.yaml       # ClusterIP service
│   ├── ingress.yaml       # GCE Ingress (HTTP LB)
│   └── rbac.yaml          # cluster-admin binding (intentional)
├── .github/workflows/
│   └── docker-build-push.yml  # CI: build, scan, attest, deploy
└── Dockerfile.tools       # Dev toolbox (terraform + kubectl + gcloud)
```
