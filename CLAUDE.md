# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository implements the **Wiz Technical Exercise v4** — a two-tier web application (containerized front-end + MongoDB database) deployed to a cloud provider (AWS, Azure, or GCP) with **intentional security misconfigurations** for demonstration purposes. The full assignment spec is in `Wiz_Tech_Exercise_V4.pdf`.

## Target Architecture

```
Internet → Load Balancer → K8s Cluster (private subnet) → Containerized App
                                                                  ↓
                           VM (public subnet, outdated Linux) → MongoDB
                                                                  ↓
                                                        backup script → Public Storage Bucket
```

### Components

1. **Kubernetes cluster** (private subnet): Runs the containerized web app (must use MongoDB), exposed via ingress + cloud load balancer
2. **VM with MongoDB** (public subnet): Outdated Linux, outdated MongoDB, SSH open to internet, overly permissive cloud IAM role
3. **Cloud storage bucket**: Receives daily automated MongoDB backups, intentionally configured with public read + public listing
4. **CI/CD pipelines**: One for IaC deployment, one for container build/push/deploy to K8s

### Intentional Misconfigurations (by design)

These are **required** by the exercise — do not "fix" them:
- VM uses 1+ year outdated Linux OS
- MongoDB is 1+ year outdated version
- SSH exposed to public internet on the VM
- VM has overly permissive CSP permissions (e.g. able to create VMs)
- Storage bucket allows public read and public listing
- Container app has cluster-wide Kubernetes admin role

### Required Secure Configurations

These must be correctly implemented:
- MongoDB access restricted to Kubernetes network only, with authentication enabled
- MongoDB connection string passed via Kubernetes environment variable
- K8s cluster in private subnet
- Container image must include `wizexercise.txt` containing the builder's name
- Control plane audit logging enabled
- At least one preventative cloud security control
- At least one detective cloud security control

## Application: bucket-list

`bucket-list/` — Node.js + Express SPA that talks to MongoDB. Serves the frontend from the same container via `express.static`.

### Env vars (set via Kubernetes)

Either provide `MONGO_URI` as a full connection string, or set individual vars:
- `MONGO_HOST`, `MONGO_PORT`, `MONGO_USER`, `MONGO_PASSWORD`, `MONGO_DB`
- `PORT` — HTTP listen port (default 3000)

### Intentional App-Level Vulnerability: NoSQL Injection

Three injection surfaces exist for demo purposes — do **not** patch these:
1. `GET /api/tasks?status[$ne]=done` — Express query parser turns query params into MongoDB operators
2. `POST /api/tasks/search` — request body forwarded verbatim as a MongoDB `find()` query
3. `PUT /api/tasks/:id` — request body forwarded verbatim as a MongoDB update document (allows `$set`, `$unset`, etc. on arbitrary fields)

### API Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tasks` | List tasks (filterable via query params) |
| POST | `/api/tasks` | Create task |
| POST | `/api/tasks/search` | Search (raw MongoDB query) |
| PUT | `/api/tasks/:id` | Update task |
| DELETE | `/api/tasks/:id` | Delete task |
| GET | `/api/health` | Health / DB connectivity check |

### Build & Run

```bash
# Local dev (needs MongoDB running)
cd bucket-list && npm install && npm run dev

# Docker
docker build -t bucket-list ./bucket-list
docker run -e MONGO_URI=mongodb://admin:password@host:27017/bucketlist?authSource=admin -p 3000:3000 bucket-list

# Validate wizexercise.txt in container
docker run --rm bucket-list cat /wizexercise.txt
```

## Infrastructure (to be added)

Expected additional directories:
- **Terraform/IaC** — VPC, subnets, K8s cluster, VM, storage bucket, IAM
- **Kubernetes manifests** — Deployments, services, ingress, RBAC (ClusterRoleBinding for admin)
- **Backup script** — Cron/scheduled `mongodump` to cloud storage
- **CI/CD configs** — GitHub Actions / GitLab CI / ADO pipelines
