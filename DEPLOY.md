# Deploy Cadence - Final Guide

## ✅ Configuration Updated

**Databases**: `cadence` and `cadence_visibility` (without "1" suffix)

All configuration files have been updated to use these database names.

---

## 🚀 Deploy in 3 Steps

### Step 1: Push to GitHub (30 seconds)

```bash
cd /Users/appointy/cadence-deploy-uat/app-of-apps

# Add all files
git add .

# Commit
git commit -m "Add Cadence deployment with cadence and cadence_visibility databases"

# Push to GitHub
git push origin main
```

---

### Step 2: Deploy to Kubernetes (2 minutes)

```bash
# Get GKE credentials (if not already connected)
gcloud container clusters get-credentials dailytumour-uat-gke \
  --region=australia-southeast1-a \
  --project=focal-psyche-460009-a5

# Apply ExternalSecret (syncs MySQL password from GCP Secret Manager)
kubectl apply -f argocd-deploy/cadence-credentials.yaml

# Wait for secret to sync (30-60 seconds)
echo "Waiting for secret sync..."
sleep 30

# Verify secret was created by ESO
kubectl get secret cadence-mysql -n cadence
kubectl get secret cadence-mysql -n cadence -o jsonpath='{.data}' | jq 'keys'

# Apply Cadence ArgoCD Application
kubectl apply -f argocd-deploy/cadence.yaml

# Watch pods starting (press Ctrl+C when all are Running)
kubectl get pods -n cadence -w
```

**Expected Pods** (wait until all show `1/1 Running`):
- `cadence-frontend-xxx` (2 pods)
- `cadence-history-0`, `cadence-history-1`, `cadence-history-2` (3 pods)
- `cadence-matching-xxx` (2 pods)
- `cadence-worker-xxx` (1 pod)
- `cadence-web-xxx` (1 pod)

**Total: 9 pods**

---

### Step 3: Initialize Database Schema (2 minutes)

**IMPORTANT**: Only run this AFTER all pods are Running!

```bash
# Get MySQL password from Kubernetes secret
MYSQL_PWD=$(kubectl get secret cadence-mysql -n cadence -o jsonpath='{.data.password}' | base64 -d)

# Create schema initialization job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: cadence-schema-init
  namespace: cadence
spec:
  ttlSecondsAfterFinished: 86400  # Auto-delete after 24 hours
  template:
    spec:
      serviceAccountName: cadence
      restartPolicy: OnFailure
      containers:
      - name: schema-init
        image: ubercadence/server:0.25.0
        env:
        - name: MYSQL_PWD
          value: "$MYSQL_PWD"
        - name: MYSQL_USER
          value: "cadence"
        - name: MYSQL_HOST
          value: "10.3.65.5"
        - name: DB_PORT
          value: "3306"
        - name: KEYSPACE
          value: "cadence"
        - name: VISIBILITY_KEYSPACE
          value: "cadence_visibility"
        command:
        - /bin/bash
        - -c
        - |
          set -ex

          echo "========================================"
          echo "Initializing Cadence Database Schema"
          echo "========================================"

          echo ""
          echo "1. Setting up 'cadence' database schema..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$KEYSPACE \
            setup-schema -v 0.0

          echo ""
          echo "2. Updating 'cadence' database to latest version..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$KEYSPACE \
            update-schema -d /etc/cadence/schema/mysql/v8/cadence/versioned

          echo ""
          echo "3. Setting up 'cadence_visibility' database schema..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$VISIBILITY_KEYSPACE \
            setup-schema -v 0.0

          echo ""
          echo "4. Updating 'cadence_visibility' database to latest version..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$VISIBILITY_KEYSPACE \
            update-schema -d /etc/cadence/schema/mysql/v8/visibility/versioned

          echo ""
          echo "========================================"
          echo "✅ Schema Initialization Complete!"
          echo "========================================"
EOF

# Watch schema initialization logs
kubectl logs -n cadence -l job-name=cadence-schema-init -f
```

**Expected Output**: You should see messages about creating tables in both `cadence` and `cadence_visibility` databases.

---

## ✅ Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n cadence

# Check services
kubectl get svc -n cadence

# Check ArgoCD application status
kubectl get application cadence -n argocd

# Check ExternalSecret status
kubectl get externalsecret cadence-mysql -n cadence
```

---

## 🌐 Access Cadence Web UI

```bash
# Port forward to Web UI
kubectl port-forward -n cadence svc/cadence-web 8088:8088
```

Then open in your browser: **http://localhost:8088**

---

## 🧪 Test Cadence CLI

```bash
# Port forward to Frontend service
kubectl port-forward -n cadence svc/cadence-frontend 7933:7933
```

In another terminal:

```bash
# Register a test domain
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain register \
  --domain test-domain \
  --description "Test domain for UAT environment"

# List all domains
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain list

# Describe the domain
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain describe \
  --domain test-domain
```

---

## 📊 Monitoring

### View Logs

```bash
# All Cadence logs
kubectl logs -n cadence -l app.kubernetes.io/name=cadence --all-containers --tail=50

# Frontend logs
kubectl logs -n cadence -l app.kubernetes.io/component=frontend -f

# History logs
kubectl logs -n cadence -l app.kubernetes.io/component=history -f

# Web UI logs
kubectl logs -n cadence -l app.kubernetes.io/component=web -f
```

### Prometheus Metrics

All components expose metrics on port 9090:

```bash
# Port forward to frontend metrics
kubectl port-forward -n cadence svc/cadence-frontend 9090:9090

# View metrics
curl http://localhost:9090/metrics
```

---

## 🔧 Troubleshooting

### Secret Not Created

```bash
# Check ExternalSecret status
kubectl describe externalsecret cadence-mysql -n cadence

# Check ESO logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=100

# Verify GCP secret exists
gcloud secrets describe dailytumour-uat-db-mysql-cadence-password \
  --project=focal-psyche-460009-a5
```

### Pods Not Starting

```bash
# Describe pod to see events
kubectl describe pod -n cadence <pod-name>

# Check events in namespace
kubectl get events -n cadence --sort-by='.lastTimestamp'

# Check if nodes have correct labels
kubectl get nodes --show-labels | grep workload
```

### Cannot Connect to MySQL

```bash
# Test MySQL connectivity from cluster
kubectl run -it --rm mysql-test --image=mysql:8.4 --restart=Never -- \
  mysql -h 10.3.65.5 -P 3306 -u cadence -p

# Enter the password from the secret
```

### Schema Initialization Failed

```bash
# View job logs
kubectl logs -n cadence -l job-name=cadence-schema-init

# Delete and retry
kubectl delete job cadence-schema-init -n cadence

# Then re-run the schema initialization command from Step 3
```

---

## 📈 Scaling

### Scale Components

```bash
# Scale frontend to 3 replicas
kubectl scale deployment cadence-frontend -n cadence --replicas=3

# Scale history to 5 replicas
kubectl scale statefulset cadence-history -n cadence --replicas=5
```

Or edit `helm/cadence/values-uat.yaml` and push to Git (ArgoCD auto-syncs).

---

## 🎉 What You Have Now

- ✅ **Cadence Server** - Fully functional workflow engine
- ✅ **High Availability** - Multiple replicas for frontend, history, matching
- ✅ **GitOps** - ArgoCD auto-syncs from GitHub
- ✅ **Secure Secrets** - MySQL password from GCP Secret Manager
- ✅ **Dedicated Resources** - Running on `workload=cadence` node pool
- ✅ **Web UI** - Visual dashboard for workflows
- ✅ **Prometheus Metrics** - Ready for monitoring
- ✅ **Production Ready** - Resource limits, health checks, PodDisruptionBudget

---

## 📚 Next Steps

1. **Register Production Domains** for your workflows
2. **Set up Monitoring** with Prometheus/Grafana
3. **Configure Alerts** for critical metrics
4. **Document Workflows** your team will run
5. **Set up CI/CD** to deploy workflows automatically

---

## 📞 Support

- **Cadence Docs**: https://cadenceworkflow.io/docs/
- **Cadence GitHub**: https://github.com/uber/cadence
- **Cadence Slack**: https://cadenceworkflow.slack.com

---

**Deployment Date**: 2025-10-27
**Environment**: UAT
**Cluster**: dailytumour-uat-gke
**Databases**: `cadence`, `cadence_visibility`
**Project**: focal-psyche-460009-a5
