# Cadence Deployment Guide
## Multi-Cluster Setup with ArgoCD and External Secrets Operator

This guide walks you through deploying Cadence on a target cluster managed by ArgoCD running on a different cluster.

## Architecture

- **ArgoCD Cluster**: `gke_focal-psyche-460009-a5_us-central1-a_argo-workflow`
- **Target Cluster**: `gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke`
- **Namespace**: `cadence-uat`
- **Database**: Cloud SQL MySQL at `10.3.65.5`
  - Default DB: `cadence1`
  - Visibility DB: `cadence_visibility1`

---

## Prerequisites

### 1. Cluster Setup

Ensure your target cluster is registered with ArgoCD:

```bash
# Switch to ArgoCD cluster
kubectl config use-context gke_focal-psyche-460009-a5_us-central1-a_argo-workflow

# List registered clusters
argocd cluster list

# If not registered, add it:
argocd cluster add gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke
```

### 2. External Secrets Operator

Ensure ESO is installed on the target cluster with a ClusterSecretStore:

```bash
# Switch to target cluster
kubectl config use-context gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke

# Verify ESO is installed
kubectl get pods -n external-secrets

# Verify ClusterSecretStore exists
kubectl get clustersecretstore gcpsm-cluster-store
```

### 3. GCP Secret Manager

Ensure the MySQL password secret exists in GCP Secret Manager:
- Secret name: `dailytumour-uat-db-mysql-cadence-password`
- Contains: MySQL password for user `cadence`

### 4. MySQL Databases

Create two empty databases in Cloud SQL:

```sql
CREATE DATABASE cadence1;
CREATE DATABASE cadence_visibility1;
GRANT ALL PRIVILEGES ON cadence1.* TO 'cadence'@'%';
GRANT ALL PRIVILEGES ON cadence_visibility1.* TO 'cadence'@'%';
FLUSH PRIVILEGES;
```

---

## File Structure

```
app-of-apps/
├── argocd/
│   ├── cadence-application.yaml      # ArgoCD Application manifest
│   └── cadence-externalsecret.yaml   # ExternalSecret for MySQL password
└── helm/
    └── cadence/
        ├── Chart.yaml                 # Official Cadence chart
        ├── values.yaml                # Default values
        ├── values-uat.yaml            # UAT environment overrides
        └── templates/                 # Helm templates
```

---

## Deployment Steps

### Step 1: Create Namespace on Target Cluster

```bash
# Switch to target cluster
kubectl config use-context gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke

# Create namespace
kubectl create namespace cadence-uat
```

### Step 2: Deploy ExternalSecret

Create the ExternalSecret to sync MySQL password from GCP Secret Manager:

```bash
kubectl apply -f argocd/cadence-externalsecret.yaml
```

Verify the secret is synced:

```bash
# Check ExternalSecret status
kubectl get externalsecret cadence-mysql -n cadence-uat

# Verify secret was created
kubectl get secret cadence-mysql -n cadence-uat
```

Expected output:
```
NAME            STORETYPE            STORE                 REFRESH INTERVAL   STATUS         READY
cadence-mysql   ClusterSecretStore   gcpsm-cluster-store   1h                 SecretSynced   True

NAME            TYPE     DATA   AGE
cadence-mysql   Opaque   1      1m
```

### Step 3: Deploy ArgoCD Application

```bash
# Switch to ArgoCD cluster
kubectl config use-context gke_focal-psyche-460009-a5_us-central1-a_argo-workflow

# Create ArgoCD application
kubectl apply -f argocd/cadence-application.yaml
```

Verify the application:

```bash
kubectl get application cadence -n argocd
```

### Step 4: Monitor Deployment

Switch back to target cluster and watch the deployment:

```bash
# Switch to target cluster
kubectl config use-context gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke

# Watch schema initialization
kubectl get jobs -n cadence-uat -w

# Expected jobs:
# - cadence-schema-setup: Creates initial schema (should complete)
# - cadence-schema-update: Applies migrations (should complete)
```

Wait for schema jobs to complete:

```bash
# Check job status
kubectl get jobs -n cadence-uat

# Expected output:
# NAME                    COMPLETIONS   DURATION   AGE
# cadence-schema-setup    1/1           4s         1m
# cadence-schema-update   1/1           6s         1m
```

### Step 5: Verify Pods are Running

```bash
# Check all pods
kubectl get pods -n cadence-uat

# Expected output (all Running):
# NAME                                READY   STATUS    RESTARTS   AGE
# cadence-frontend-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# cadence-history-xxxxxxxxxx-xxxxx    1/1     Running   0          2m
# cadence-matching-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# cadence-web-xxxxxxxxxx-xxxxx        1/1     Running   0          2m
# cadence-worker-xxxxxxxxxx-xxxxx     1/1     Running   0          2m
```

### Step 6: Verify Services

```bash
kubectl get svc -n cadence-uat

# Expected services:
# - cadence-frontend (ClusterIP)
# - cadence-frontend-headless (ClusterIP None)
# - cadence-history-headless (ClusterIP None)
# - cadence-matching-headless (ClusterIP None)
# - cadence-web (ClusterIP)
# - cadence-worker-headless (ClusterIP None)
```

---

## Post-Deployment Verification

### 1. Check Cadence Web UI

```bash
# Port-forward to web UI
kubectl port-forward svc/cadence-web -n cadence-uat 8088:80
```

Then open your browser to: http://localhost:8088

### 2. Register a Test Domain

```bash
# Get frontend pod name
FRONTEND_POD=$(kubectl get pods -n cadence-uat -l app.kubernetes.io/component=frontend -o jsonpath='{.items[0].metadata.name}')

# Register domain
kubectl exec -it $FRONTEND_POD -n cadence-uat -- cadence --domain test-domain domain register

# List domains
kubectl exec -it $FRONTEND_POD -n cadence-uat -- cadence --domain test-domain domain describe
```

### 3. Check Database Tables

Verify tables were created:

```bash
# Create a test pod
kubectl run mysql-test --image=mysql:8.4 --rm -it --restart=Never -n cadence-uat \
  --env MYSQL_PWD="$(kubectl get secret cadence-mysql -n cadence-uat -o jsonpath='{.data.password}' | base64 -d)" \
  -- mysql -h 10.3.65.5 -u cadence cadence1 -e "SHOW TABLES;"

# Expected tables in cadence1:
# - cluster_membership
# - domain
# - domain_metadata
# - executions
# - history_node
# - history_tree
# - queue
# - queue_metadata
# - schema_update_history
# - schema_version
# - shards
# - tasks
# - transfer_tasks
# - visibility_tasks
```

---

## Troubleshooting

### Schema Setup Job Failing

If schema-setup job shows "Table already exists" error:

```bash
# Check if databases are empty
kubectl run mysql-test --image=mysql:8.4 --rm -it --restart=Never -n cadence-uat \
  --command -- sh -c 'mysql -h 10.3.65.5 -u cadence -p"$MYSQL_PWD" cadence1 -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"cadence1\";"'
```

If tables exist, disable schema setup in `helm/cadence/values-uat.yaml`:

```yaml
schema:
  setup:
    enabled: false  # Databases already initialized
  update:
    enabled: true
```

### Pods Not Starting

Check pod logs:

```bash
# Frontend logs
kubectl logs -n cadence-uat -l app.kubernetes.io/component=frontend --tail=50

# History logs
kubectl logs -n cadence-uat -l app.kubernetes.io/component=history --tail=50
```

Common issues:
- Database connection failed: Check MySQL credentials in secret
- Schema version mismatch: Run schema update job manually

### ArgoCD Not Syncing

```bash
# Check application status
kubectl get application cadence -n argocd -o yaml

# Manually trigger sync
kubectl patch application cadence -n argocd --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main"}}}'
```

---

## Cleanup

To completely remove Cadence:

```bash
# Delete ArgoCD application (will also delete resources on target cluster)
kubectl delete application cadence -n argocd

# Or manually delete from target cluster
kubectl delete namespace cadence-uat
```

To drop databases:

```sql
DROP DATABASE cadence1;
DROP DATABASE cadence_visibility1;
```

---

## Configuration Files

See the following sections for the complete configuration files.
