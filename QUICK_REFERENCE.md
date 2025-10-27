# Cadence Deployment - Quick Reference

## Repository Structure ✅

```
app-of-apps/                           # Your Git Repository
├── argocd/
│   ├── cadence-application.yaml       # Deploy this to ArgoCD cluster
│   └── cadence-externalsecret.yaml    # Deploy this to target cluster first
├── helm/
│   └── cadence/                       # Official Cadence Helm chart
│       ├── Chart.yaml                 # v0.24.2
│       ├── values.yaml                # Default values (don't edit)
│       ├── values-uat.yaml            # ✅ EDIT THIS for your environment
│       └── templates/                 # Helm templates (don't edit)
├── DEPLOYMENT_GUIDE.md                # Full deployment instructions
├── CONFIGURATION_FILES.md             # Detailed config explanations
└── QUICK_REFERENCE.md                 # This file
```

---

## Files You Created

### 1. ExternalSecret (argocd/cadence-externalsecret.yaml)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cadence-mysql
  namespace: cadence-uat
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcpsm-cluster-store
  target:
    name: cadence-mysql
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: dailytumour-uat-db-mysql-cadence-password
```

**Purpose:** Fetches MySQL password from GCP Secret Manager

---

### 2. ArgoCD Application (argocd/cadence-application.yaml)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cadence
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/yash-study/app-of-apps.git
    targetRevision: main
    path: helm/cadence
    helm:
      releaseName: cadence
      valueFiles:
        - values.yaml
        - values-uat.yaml
  destination:
    name: dailytumour-uat-gke
    namespace: cadence-uat
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Purpose:** Defines how ArgoCD deploys Cadence
**Key Settings:**
- `automated: true` = GitOps auto-sync enabled ✅
- `prune: true` = Removes deleted resources
- `selfHeal: true` = Reverts manual changes

---

### 3. Helm Values (helm/cadence/values-uat.yaml)

```yaml
# Cadence UAT - Minimal Resource Configuration

server:
  replicaCount: 1

  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 50m
      memory: 128Mi

  config:
    persistence:
      default:
        driver: "sql"
        sql:
          pluginName: "mysql"
          host: "10.3.65.5"
          port: 3306
          database: "cadence1"
          user: "cadence"
          existingSecret: "cadence-mysql"

      visibility:
        driver: "sql"
        sql:
          pluginName: "mysql"
          host: "10.3.65.5"
          port: 3306
          database: "cadence_visibility1"
          user: "cadence"
          existingSecret: "cadence-mysql"

web:
  enabled: true
  replicaCount: 1

schema:
  setup:
    enabled: true  # Fresh empty databases
  update:
    enabled: true
    backoffLimit: 100

mysql:
  enabled: false

cassandra:
  enabled: false
```

**Purpose:** UAT environment configuration
**✅ EDIT THIS FILE** to change Cadence settings

---

## GitOps Workflow

### Current Setup
✅ **Auto-Sync Enabled** - Changes in Git automatically deploy
✅ **Self-Heal Enabled** - Manual changes get reverted to Git state
✅ **Auto-Prune Enabled** - Deleted resources removed automatically

### Making Changes

#### 1. Edit Configuration Locally
```bash
cd /Users/appointy/cadence-deploy-uat/app-of-apps
vim helm/cadence/values-uat.yaml
```

#### 2. Commit and Push
```bash
git add helm/cadence/values-uat.yaml
git commit -m "Update Cadence CPU limits"
git push origin main
```

#### 3. ArgoCD Auto-Syncs (within ~3 minutes)
No manual action needed! ArgoCD will:
- Detect changes
- Run helm upgrade
- Update pods
- Report status

#### 4. Monitor Deployment
```bash
# From ArgoCD cluster
kubectl get application cadence -n argocd

# From target cluster
kubectl get pods -n cadence-uat -w
```

---

## Common Configuration Changes

### Increase Resources
```yaml
# In helm/cadence/values-uat.yaml
server:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 512Mi
```

### Scale to Multiple Replicas
```yaml
server:
  replicaCount: 3  # Changed from 1

web:
  replicaCount: 2  # Changed from 1
```

### Change Database
```yaml
server:
  config:
    persistence:
      default:
        sql:
          host: "NEW_HOST"
          database: "NEW_DB"
```

### Disable Auto-Sync
```yaml
# In argocd/cadence-application.yaml
syncPolicy:
  automated: null  # Changed from automated: {...}
```

Then manually sync:
```bash
kubectl patch application cadence -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"main"}}}'
```

---

## Quick Deployment Commands

### Initial Deployment

```bash
# 1. Target Cluster - Create namespace
kubectl config use-context gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke
kubectl create namespace cadence-uat

# 2. Target Cluster - Deploy ExternalSecret
kubectl apply -f argocd/cadence-externalsecret.yaml

# 3. Verify secret created
kubectl get externalsecret,secret -n cadence-uat

# 4. ArgoCD Cluster - Deploy Application
kubectl config use-context gke_focal-psyche-460009-a5_us-central1-a_argo-workflow
kubectl apply -f argocd/cadence-application.yaml

# 5. Target Cluster - Monitor
kubectl config use-context gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke
kubectl get pods -n cadence-uat -w
```

### Check Status

```bash
# ArgoCD Application Status
kubectl config use-context gke_focal-psyche-460009-a5_us-central1-a_argo-workflow
kubectl get application cadence -n argocd

# Cadence Pods
kubectl config use-context gke_focal-psyche-460009-a5_australia-southeast1-a_dailytumour-uat-gke
kubectl get pods -n cadence-uat

# Schema Jobs
kubectl get jobs -n cadence-uat

# Services
kubectl get svc -n cadence-uat
```

### Access Web UI

```bash
kubectl port-forward svc/cadence-web -n cadence-uat 8088:80
# Open: http://localhost:8088
```

### Manual Sync (if auto-sync disabled)

```bash
kubectl config use-context gke_focal-psyche-460009-a5_us-central1-a_argo-workflow
kubectl patch application cadence -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"main"}}}'
```

---

## Current Deployment Status

✅ **Deployed Successfully!**

**Pods Running:**
- cadence-frontend: 1/1 Running
- cadence-history: 1/1 Running
- cadence-matching: 1/1 Running
- cadence-web: 1/1 Running
- cadence-worker: 1/1 Running

**Schema Jobs:** Both completed
- cadence-schema-setup: Complete (1/1)
- cadence-schema-update: Complete (1/1)

**Database:** Cloud SQL MySQL at 10.3.65.5
- cadence1 (default store)
- cadence_visibility1 (visibility store)

**ArgoCD:** Auto-sync enabled on main branch

---

## Important Notes

### ✅ What's Automated (GitOps)
- Configuration changes (edit values-uat.yaml, push to Git)
- Application updates (ArgoCD auto-syncs)
- Resource scaling
- Environment variable changes

### ⚠️ What's NOT Automated
- Initial namespace creation (one-time manual step)
- ExternalSecret deployment (one-time manual step)
- ArgoCD Application creation (one-time manual step)
- Database schema changes (requires manual job or migration)

### 🔒 Security Best Practices
- ✅ Using External Secrets Operator for passwords
- ✅ Secrets stored in GCP Secret Manager
- ✅ No passwords in Git
- ✅ Workload Identity for GKE service accounts

### 📊 Monitoring
- ArgoCD UI: Check sync status, health
- Kubernetes Dashboard: Pod metrics, logs
- Cadence Web UI: Workflow execution, domain management

---

## Troubleshooting

### ArgoCD shows OutOfSync
```bash
# Check what's different
kubectl describe application cadence -n argocd

# Force sync
kubectl patch application cadence -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"main"}}}'
```

### Pods CrashLooping
```bash
# Check logs
kubectl logs -n cadence-uat -l app.kubernetes.io/component=frontend --tail=50

# Common issues:
# - Database connection failed: Check secret
# - Schema mismatch: Run schema update
```

### Schema Job Failed
```bash
# Check logs
kubectl logs -n cadence-uat -l job-name=cadence-schema-setup

# If "table already exists": Set schema.setup.enabled=false
# If database error: Check credentials in secret
```

---

## Next Steps

1. ✅ Deployment complete
2. Access Web UI at http://localhost:8088 (after port-forward)
3. Register a test domain
4. Start deploying workflows!

**For Production:**
- Increase replicas (3+ for high availability)
- Increase resources (cpu: 1000m+, memory: 2Gi+)
- Set up monitoring/alerting
- Configure backups for Cloud SQL
- Review security settings
