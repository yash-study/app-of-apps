# Cadence Configuration Files

This document contains all the configuration files needed to deploy Cadence.

---

## 1. ExternalSecret - MySQL Password

**File**: `argocd/cadence-externalsecret.yaml`

This file creates a Kubernetes secret by fetching the MySQL password from GCP Secret Manager.

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

**What it does:**
- Fetches the secret `dailytumour-uat-db-mysql-cadence-password` from GCP Secret Manager
- Creates a Kubernetes secret named `cadence-mysql` in the `cadence-uat` namespace
- The secret contains one key: `password`

**Prerequisites:**
- ClusterSecretStore named `gcpsm-cluster-store` must exist
- GCP Secret Manager must have the secret `dailytumour-uat-db-mysql-cadence-password`
- Service account with permissions to read from Secret Manager

**Deploy:**
```bash
kubectl apply -f argocd/cadence-externalsecret.yaml
```

**Verify:**
```bash
# Check ExternalSecret status
kubectl get externalsecret cadence-mysql -n cadence-uat

# Check created secret
kubectl get secret cadence-mysql -n cadence-uat -o yaml
```

---

## 2. ArgoCD Application

**File**: `argocd/cadence-application.yaml`

This file defines the ArgoCD Application that manages the Cadence deployment.

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

**What it does:**
- Deploys Helm chart from `helm/cadence` directory in your Git repository
- Uses `values.yaml` (defaults) and `values-uat.yaml` (UAT overrides)
- Deploys to cluster named `dailytumour-uat-gke`
- Creates namespace `cadence-uat` automatically
- Auto-sync enabled: ArgoCD will automatically deploy changes from Git
- Auto-prune: Removes resources deleted from Git
- Self-heal: Reverts manual changes to match Git state

**Key Configuration:**
- `repoURL`: Change this to your Git repository
- `targetRevision`: Branch to deploy from (main)
- `destination.name`: Must match your cluster name in ArgoCD
- `syncPolicy.automated`: Set to `null` to disable auto-sync

**Deploy:**
```bash
# Make sure you're on ArgoCD cluster
kubectl config use-context gke_focal-psyche-460009-a5_us-central1-a_argo-workflow

# Create application
kubectl apply -f argocd/cadence-application.yaml
```

**Verify:**
```bash
# Check application status
kubectl get application cadence -n argocd

# Check detailed status
kubectl describe application cadence -n argocd
```

---

## 3. Helm Values - UAT Environment

**File**: `helm/cadence/values-uat.yaml`

This file overrides the default Helm values for the UAT environment.

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

**Configuration Breakdown:**

### Server Settings
- `replicaCount: 1` - Single replica for each Cadence service (frontend, history, matching, worker)
- Minimal resources for UAT environment

### Persistence Configuration
Two databases required:
1. **default** (`cadence1`): Main workflow data
   - Stores workflow executions, tasks, domains
2. **visibility** (`cadence_visibility1`): Search/query data
   - Stores workflow visibility records for UI/API queries

### Database Connection
- `host: "10.3.65.5"` - Cloud SQL private IP
- `user: "cadence"` - MySQL username
- `existingSecret: "cadence-mysql"` - References the secret created by ExternalSecret
- Password is read from `cadence-mysql` secret

### Schema Management
- `setup.enabled: true` - Creates initial schema tables (run once for empty databases)
- `update.enabled: true` - Applies schema migrations

**Important:** If databases already have schema_version tables, set `setup.enabled: false`

### External Services
- `mysql.enabled: false` - Don't deploy MySQL (using external Cloud SQL)
- `cassandra.enabled: false` - Not using Cassandra

**Customization:**
```yaml
# For production, increase resources:
server:
  replicaCount: 3
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 500m
      memory: 1Gi

# For different database:
server:
  config:
    persistence:
      default:
        sql:
          host: "YOUR_MYSQL_HOST"
          database: "YOUR_DB_NAME"
          user: "YOUR_DB_USER"
```

---

## 4. Complete File Listing

Create these files in your repository:

### Directory Structure
```
your-repo/
├── argocd/
│   ├── cadence-application.yaml      # ArgoCD Application
│   └── cadence-externalsecret.yaml   # ExternalSecret for MySQL
└── helm/
    └── cadence/
        ├── Chart.yaml                 # From official chart
        ├── values.yaml                # From official chart
        ├── values-uat.yaml            # YOUR custom values
        └── templates/                 # From official chart
            ├── _helpers.tpl
            ├── NOTES.txt
            ├── server-configmap.yaml
            ├── server-deployment.yaml
            ├── server-job.yaml
            ├── server-secret.yaml
            ├── server-service.yaml
            ├── web-deployment.yaml
            ├── web-ingress.yaml
            └── web-service.yaml
```

### Quick Deployment Commands

```bash
# 1. Create namespace on target cluster
kubectl config use-context YOUR_TARGET_CLUSTER
kubectl create namespace cadence-uat

# 2. Deploy ExternalSecret
kubectl apply -f argocd/cadence-externalsecret.yaml

# 3. Verify secret synced
kubectl get externalsecret,secret -n cadence-uat

# 4. Deploy ArgoCD Application (from ArgoCD cluster)
kubectl config use-context YOUR_ARGOCD_CLUSTER
kubectl apply -f argocd/cadence-application.yaml

# 5. Monitor deployment (on target cluster)
kubectl config use-context YOUR_TARGET_CLUSTER
kubectl get pods -n cadence-uat -w
```

---

## 5. Environment-Specific Customization

### For Different Environments

Create additional values files for other environments:

**values-dev.yaml** (Development)
```yaml
server:
  replicaCount: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
  config:
    persistence:
      default:
        sql:
          database: "cadence_dev"
      visibility:
        sql:
          database: "cadence_visibility_dev"
```

**values-prod.yaml** (Production)
```yaml
server:
  replicaCount: 3
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
  config:
    persistence:
      default:
        sql:
          database: "cadence_prod"
          maxConns: 50
      visibility:
        sql:
          database: "cadence_visibility_prod"
          maxConns: 30

schema:
  setup:
    enabled: false  # Already initialized
```

Then update ArgoCD Application to use the appropriate values file:
```yaml
helm:
  valueFiles:
    - values.yaml
    - values-prod.yaml  # Change this
```

---

## 6. Secret Management Alternatives

If not using External Secrets Operator, you can create the secret manually:

**Option A: Create secret directly**
```bash
kubectl create secret generic cadence-mysql \
  -n cadence-uat \
  --from-literal=password='YOUR_MYSQL_PASSWORD'
```

**Option B: Use Sealed Secrets**
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: cadence-mysql
  namespace: cadence-uat
spec:
  encryptedData:
    password: AgBXXXXXXXXXXX  # Encrypted value
```

**Option C: Use values file (NOT RECOMMENDED for production)**
```yaml
# In values-uat.yaml
server:
  config:
    persistence:
      default:
        sql:
          password: "your-password"  # NOT RECOMMENDED
          existingSecret: ""
```

---

## Summary

**Essential Files:**
1. ✅ `argocd/cadence-externalsecret.yaml` - Syncs MySQL password from GCP
2. ✅ `argocd/cadence-application.yaml` - ArgoCD application definition
3. ✅ `helm/cadence/values-uat.yaml` - UAT environment configuration
4. ✅ `helm/cadence/` - Official Cadence Helm chart (from cadence-0.24.2.tgz)

**Deployment Order:**
1. Create namespace
2. Deploy ExternalSecret
3. Deploy ArgoCD Application
4. Monitor schema jobs completion
5. Verify pods running
