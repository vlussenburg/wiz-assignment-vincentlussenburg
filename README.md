# Wiz Technical Exercise v4

Two-tier web application deployed on GCP with intentional security misconfigurations for demonstration purposes.

## Architecture

```
Internet → GCP HTTP LB → GKE (private subnet) → bucket-list app (Node.js)
                                                        ↓
                          VM (public subnet) ────→ MongoDB 5.0
                                                        ↓
                                                  cron backup → GCS bucket (public)
```

## Components

| Component | Details |
|-----------|---------|
| **App** | Node.js/Express SPA (`bucket-list/`) — task manager backed by MongoDB |
| **GKE Cluster** | Private cluster in `10.0.2.0/24`, exposed via GCE Ingress (HTTP LB) |
| **MongoDB VM** | Ubuntu 22.04, MongoDB 5.0, public IP, in `10.0.1.0/24` |
| **GCS Bucket** | Daily `mongodump` backups via cron |
| **Artifact Registry** | Docker repo for the app container image |

## Intentional Misconfigurations

These are **required** by the exercise spec — do not fix:

- VM runs Ubuntu 22.04 (1+ year outdated — 24.04 LTS available)
- MongoDB 5.0 (EOL Oct 2024)
- SSH open to `0.0.0.0/0` on the VM
- VM service account has `roles/compute.admin` (can create/manage VMs)
- GCS backup bucket allows public read and public listing
- App has `cluster-admin` ClusterRoleBinding in Kubernetes

## Secure Configurations

- MongoDB accepts connections only from the GKE pod CIDR (`10.4.0.0/14`)
- MongoDB authentication enabled (admin + app user)
- GKE cluster uses private nodes
- Control plane audit logging enabled (`APISERVER`, `SYSTEM_COMPONENTS`, `WORKLOADS`)
- **Preventative control**: Firewall restricting MongoDB to K8s network only
- **Detective control**: GKE Security Posture with vulnerability scanning

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

### 3. Build & Push Container

```bash
# Configure Docker for Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build and push
docker build -t us-central1-docker.pkg.dev/<PROJECT_ID>/bucket-list/bucket-list:latest ./bucket-list
docker push us-central1-docker.pkg.dev/<PROJECT_ID>/bucket-list/bucket-list:latest
```

### 4. Deploy to Kubernetes

Update `k8s/deployment.yaml` with the Artifact Registry image URL and MongoDB VM internal IP from `terraform output`, then:

```bash
kubectl apply -f k8s/
```

### 5. Verify

```bash
# Get the load balancer IP (may take a few minutes)
kubectl get ingress bucket-list

# Check public bucket access
gsutil ls gs://<PROJECT_ID>-wiz-backups
```

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
│   └── scripts/
│       └── mongo-startup.sh  # MongoDB install, auth, backup cron
├── k8s/                   # Kubernetes manifests
│   ├── deployment.yaml    # App deployment
│   ├── service.yaml       # ClusterIP service
│   ├── ingress.yaml       # GCE Ingress (HTTP LB)
│   └── rbac.yaml          # cluster-admin binding (intentional)
└── Dockerfile.tools       # Dev toolbox (terraform + kubectl + gcloud)
```
