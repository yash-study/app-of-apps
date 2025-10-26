# Cadence Helm Chart Reference

This directory contains a **reference implementation** of a Cadence Helm chart that you should copy to your **application repository**.

## Repository Structure

You need **TWO repositories** for the deployment:

### 1. Infrastructure Repository (CURRENT)
**Location**: This repository (`dailytumour-uat-infrastructure`)
**Purpose**: ArgoCD applications, External Secrets, infrastructure config

```
dailytumour-uat-infrastructure/
├── app-of-apps/
│   └── dailytumour-uat.yaml
├── argocd-deploy/
│   ├── cadence-credentials.yaml
│   ├── cadence.yaml
│   └── apps/cadence/values-uat.yaml
└── helm-chart-reference/  (THIS DIRECTORY - for reference only)
```

### 2. Application Repository (NEEDS TO BE CREATED)
**Name**: `dailytumour-cadence` (or your choice)
**Purpose**: Cadence Helm chart

```
dailytumour-cadence/
├── README.md
└── helm/
    └── cadence/
        ├── Chart.yaml
        ├── values.yaml
        ├── values-uat.yaml
        └── templates/
            ├── _helpers.tpl
            ├── serviceaccount.yaml
            ├── configmap.yaml
            ├── frontend-deployment.yaml
            ├── frontend-service.yaml
            ├── history-statefulset.yaml
            ├── history-service.yaml
            ├── matching-deployment.yaml
            ├── matching-service.yaml
            ├── worker-deployment.yaml
            ├── worker-service.yaml
            ├── web-deployment.yaml
            └── web-service.yaml
```

## How to Use This Reference

### Step 1: Create Application Repository

```bash
# Create a new Git repository
mkdir -p dailytumour-cadence/helm/cadence/templates
cd dailytumour-cadence

# Initialize Git
git init
git remote add origin https://github.com/your-org/dailytumour-cadence.git
```

### Step 2: Copy Reference Files

```bash
# From this directory, copy the Helm chart
cp -r helm-chart-reference/cadence/* dailytumour-cadence/helm/cadence/

# Verify structure
tree dailytumour-cadence/helm/cadence
```

### Step 3: Create Missing Templates

The reference includes `frontend` and `web` components. You need to create similar templates for:

- **history** (StatefulSet, not Deployment)
- **matching** (Deployment)
- **worker** (Deployment)

Copy `frontend-deployment.yaml` and modify for each component:

```bash
cd dailytumour-cadence/helm/cadence/templates

# Create history templates (use StatefulSet for history!)
cp frontend-deployment.yaml history-statefulset.yaml
cp frontend-service.yaml history-service.yaml

# Create matching templates
cp frontend-deployment.yaml matching-deployment.yaml
cp frontend-service.yaml matching-service.yaml

# Create worker templates
cp frontend-deployment.yaml worker-deployment.yaml
cp frontend-service.yaml worker-service.yaml
```

Then edit each file to replace `frontend` with the appropriate component name and adjust values.

### Step 4: Update ArgoCD Application

Update [`argocd-deploy/cadence.yaml`](../argocd-deploy/cadence.yaml) to point to your application repository:

```yaml
source:
  repoURL: https://github.com/your-org/dailytumour-cadence.git  # YOUR REPO HERE
  targetRevision: main
  path: helm/cadence
```

### Step 5: Push to Git

```bash
cd dailytumour-cadence
git add .
git commit -m "Initial Cadence Helm chart"
git push origin main
```

## Helm Chart Details

### Components

1. **Frontend** (Deployment) - RPC gateway for Cadence clients
2. **History** (StatefulSet) - Workflow execution history management
3. **Matching** (Deployment) - Task list management
4. **Worker** (Deployment) - Internal workflow worker
5. **Web** (Deployment) - Web UI dashboard

### Configuration Files

- **Chart.yaml** - Helm chart metadata
- **values.yaml** - Default values (environment-agnostic)
- **values-uat.yaml** - UAT environment overrides (copy from `argocd-deploy/apps/cadence/values-uat.yaml`)
- **templates/_helpers.tpl** - Template helpers and functions
- **templates/configmap.yaml** - Cadence configuration
- **templates/serviceaccount.yaml** - Kubernetes ServiceAccount

### Environment-Specific Values

Create `values-uat.yaml` in your application repo:

```bash
cp ../argocd-deploy/apps/cadence/values-uat.yaml dailytumour-cadence/helm/cadence/values-uat.yaml
```

## Testing the Helm Chart Locally

```bash
cd dailytumour-cadence/helm/cadence

# Lint the chart
helm lint .

# Template rendering (dry-run)
helm template cadence . \
  -f values.yaml \
  -f values-uat.yaml \
  --namespace cadence \
  --debug

# Install locally (requires kubectl context)
helm install cadence . \
  -f values.yaml \
  -f values-uat.yaml \
  --namespace cadence \
  --create-namespace \
  --dry-run

# Actually install
helm install cadence . \
  -f values.yaml \
  -f values-uat.yaml \
  --namespace cadence \
  --create-namespace
```

## ArgoCD Integration

Once your application repository is ready and the Helm chart is committed:

1. **Update** `argocd-deploy/cadence.yaml` with your repo URL
2. **Commit** changes to infrastructure repo
3. **Apply** ArgoCD application:
   ```bash
   kubectl apply -f argocd-deploy/cadence.yaml
   ```
4. **Sync** with ArgoCD:
   ```bash
   argocd app sync cadence
   ```

ArgoCD will now automatically deploy Cadence whenever you push changes to your application repository!

## Important Notes

- **History service** must use StatefulSet (not Deployment) for stable network identity
- **MySQL secret** is created by External Secrets Operator (ESO)
- **Workload Identity** is configured via ServiceAccount annotations
- **Node affinity** uses `workload: cadence` label with tolerations

## Next Steps

1. ✅ Copy files to application repository
2. ✅ Create missing component templates (history, matching, worker)
3. ✅ Push application repository to Git
4. ✅ Update ArgoCD application with correct repo URL
5. ✅ Follow [QUICKSTART.md](../QUICKSTART.md) for deployment

## Support

- Helm Docs: https://helm.sh/docs/
- Cadence Docs: https://cadenceworkflow.io/docs/
- ArgoCD Docs: https://argo-cd.readthedocs.io/
