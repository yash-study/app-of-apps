# Final Deployment Steps for Cadence

## Repository Information
- **Infrastructure Repo**: Current repository
- **Application Repo**: `git@github.com:yash-study/app-of-apps.git`
- **ArgoCD Application**: Already configured to point to your repo

---

## Step 1: Copy Helm Chart to Your Application Repository

### 1.1 Extract the Helm Chart

The complete Helm chart is available in `/tmp/cadence-helm-complete/`

```bash
# Copy to your repository (same repo in this case)
cp -r /tmp/cadence-helm-complete/helm /Users/appointy/cadence-deploy-uat/app-of-apps/

# Verify structure
tree /Users/appointy/cadence-deploy-uat/app-of-apps/helm
```

Expected structure:
```
helm/
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

### 1.2 Commit and Push

```bash
cd /Users/appointy/cadence-deploy-uat/app-of-apps

# Add files
git add helm/
git add argocd-deploy/
git add *.md
git add deploy-cadence.sh

# Commit
git commit -m "Add Cadence Helm chart and ArgoCD deployment configuration"

# Push to GitHub
git push origin main
```

---

## Step 2: Create MySQL Password in Google Secret Manager

```bash
# Generate secure password
PASSWORD=$(openssl rand -base64 32)
echo "Generated password: $PASSWORD"
echo "SAVE THIS PASSWORD SECURELY!"

# Create secret in Google Secret Manager
echo -n "$PASSWORD" | gcloud secrets create dailytumour-uat-db-mysql-cadence-password \
  --data-file=- \
  --replication-policy="automatic" \
  --project=focal-psyche-460009-a5 \
  --labels=app=cadence,environment=uat

# Verify secret created
gcloud secrets describe dailytumour-uat-db-mysql-cadence-password \
  --project=focal-psyche-460009-a5
```

---

## Step 3: Create MySQL Databases and User

```bash
# Connect to Cloud SQL
gcloud sql connect dailytumour-uat-db-mysql \
  --user=root \
  --project=focal-psyche-460009-a5
```

In the MySQL prompt, run:

```sql
-- Create databases
CREATE DATABASE IF NOT EXISTS cadence1;
CREATE DATABASE IF NOT EXISTS cadence_visibility1;

-- Create user (use the password generated above)
CREATE USER IF NOT EXISTS 'cadence'@'%' IDENTIFIED BY 'YOUR_PASSWORD_HERE';

-- Grant permissions
GRANT ALL PRIVILEGES ON cadence1.* TO 'cadence'@'%';
GRANT ALL PRIVILEGES ON cadence_visibility1.* TO 'cadence'@'%';
FLUSH PRIVILEGES;

-- Verify
SHOW GRANTS FOR 'cadence'@'%';
SELECT User, Host FROM mysql.user WHERE User = 'cadence';

-- Exit
EXIT;
```

---

## Step 4: Get GKE Cluster Credentials

```bash
# Authenticate with GCP
gcloud auth login

# Get cluster credentials
gcloud container clusters get-credentials dailytumour-uat-gke \
  --region=australia-southeast1-a \
  --project=focal-psyche-460009-a5

# Verify connection
kubectl get nodes
kubectl get namespaces
```

---

## Step 5: Deploy Cadence

### Option A: Automated Deployment (Recommended)

```bash
cd /Users/appointy/cadence-deploy-uat/app-of-apps

# Run deployment script
./deploy-cadence.sh
```

The script will:
1. ✅ Check prerequisites
2. ✅ Connect to GKE cluster
3. ✅ Create cadence namespace
4. ✅ Apply ExternalSecret for MySQL credentials
5. ✅ Wait for secret to sync from GCP Secret Manager
6. ✅ Deploy Cadence via ArgoCD
7. ✅ Optionally initialize database schema

### Option B: Manual Deployment

```bash
# Create namespace
kubectl create namespace cadence

# Apply ExternalSecret
kubectl apply -f argocd-deploy/cadence-credentials.yaml

# Wait for secret (will take ~30-60 seconds)
kubectl wait --for=condition=Ready externalsecret/cadence-mysql \
  -n cadence \
  --timeout=120s

# Verify secret created
kubectl get secret cadence-mysql -n cadence
kubectl get secret cadence-mysql -n cadence -o jsonpath='{.data}' | jq 'keys'

# Apply ArgoCD application
kubectl apply -f argocd-deploy/cadence.yaml

# Watch ArgoCD sync
kubectl get application cadence -n argocd -w
```

---

## Step 6: Initialize Database Schema

```bash
# Get MySQL password from secret
MYSQL_PWD=$(kubectl get secret cadence-mysql -n cadence -o jsonpath='{.data.password}' | base64 -d)

# Create schema initialization job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: cadence-schema-init
  namespace: cadence
spec:
  ttlSecondsAfterFinished: 86400
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
          value: "cadence1"
        - name: VISIBILITY_KEYSPACE
          value: "cadence_visibility1"
        command:
        - /bin/bash
        - -c
        - |
          set -ex
          echo "=== Initializing Cadence Schema ==="

          # Default database
          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$KEYSPACE setup-schema -v 0.0
          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$KEYSPACE update-schema -d /etc/cadence/schema/mysql/v8/cadence/versioned

          # Visibility database
          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$VISIBILITY_KEYSPACE setup-schema -v 0.0
          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$VISIBILITY_KEYSPACE update-schema -d /etc/cadence/schema/mysql/v8/visibility/versioned

          echo "=== Schema Initialization Complete ==="
EOF

# Watch job logs
kubectl logs -n cadence -l job-name=cadence-schema-init -f
```

---

## Step 7: Verify Deployment

```bash
# Check pods
kubectl get pods -n cadence

# Expected output:
# NAME                                READY   STATUS    RESTARTS   AGE
# cadence-frontend-xxx                1/1     Running   0          5m
# cadence-frontend-xxx                1/1     Running   0          5m
# cadence-history-0                   1/1     Running   0          5m
# cadence-history-1                   1/1     Running   0          5m
# cadence-history-2                   1/1     Running   0          5m
# cadence-matching-xxx                1/1     Running   0          5m
# cadence-matching-xxx                1/1     Running   0          5m
# cadence-worker-xxx                  1/1     Running   0          5m
# cadence-web-xxx                     1/1     Running   0          5m

# Check services
kubectl get svc -n cadence

# Check ExternalSecret
kubectl get externalsecret cadence-mysql -n cadence
kubectl describe externalsecret cadence-mysql -n cadence

# Check ArgoCD application
kubectl get application cadence -n argocd
```

---

## Step 8: Access Cadence Web UI

```bash
# Port forward to Web UI
kubectl port-forward -n cadence svc/cadence-web 8088:8088
```

Then open in browser: **http://localhost:8088**

---

## Step 9: Test Cadence CLI

```bash
# Port forward to Frontend
kubectl port-forward -n cadence svc/cadence-frontend 7933:7933

# In another terminal, register a test domain
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain register \
  --domain test-domain \
  --description "Test domain for UAT"

# List domains
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain list
```

---

## Troubleshooting

### Secret Not Created

```bash
# Check ExternalSecret status
kubectl describe externalsecret cadence-mysql -n cadence

# Check ESO logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=100

# Verify GCP secret exists
gcloud secrets describe dailytumour-uat-db-mysql-cadence-password --project=focal-psyche-460009-a5
```

### Pods Not Starting

```bash
# Describe pod
kubectl describe pod -n cadence <pod-name>

# Check events
kubectl get events -n cadence --sort-by='.lastTimestamp'

# Check node labels
kubectl get nodes --show-labels | grep workload
```

### Cannot Connect to MySQL

```bash
# Test MySQL from cluster
kubectl run -it --rm mysql-test --image=mysql:8.4 --restart=Never -- \
  mysql -h 10.3.65.5 -P 3306 -u cadence -p
```

---

## Monitoring

### View Logs

```bash
# All Cadence logs
kubectl logs -n cadence -l app.kubernetes.io/name=cadence --all-containers --tail=50

# Frontend logs
kubectl logs -n cadence -l app.kubernetes.io/component=frontend -f --tail=50

# History logs
kubectl logs -n cadence -l app.kubernetes.io/component=history -f --tail=50
```

### Prometheus Metrics

```bash
# Port forward to metrics endpoint
kubectl port-forward -n cadence svc/cadence-frontend 9090:9090

# View metrics
curl http://localhost:9090/metrics
```

---

## Scaling

### Scale Components

```bash
# Scale frontend
kubectl scale deployment cadence-frontend -n cadence --replicas=3

# Scale history
kubectl scale statefulset cadence-history -n cadence --replicas=5
```

Or edit `helm/cadence/values-uat.yaml` and push to Git (ArgoCD will auto-sync).

---

## Next Steps

1. ✅ **Register Production Domains** for your workflows
2. ✅ **Set up Monitoring** with Prometheus/Grafana
3. ✅ **Configure Alerts** for critical metrics
4. ✅ **Set up Backups** for MySQL (Cloud SQL automated backups)
5. ✅ **Configure Istio VirtualService** for Web UI ingress (optional)
6. ✅ **Document Workflows** your team will run

---

## Support

- **Cadence Docs**: https://cadenceworkflow.io/docs/
- **GitHub Issues**: https://github.com/uber/cadence/issues
- **Slack**: https://cadenceworkflow.slack.com

---

**Deployment Date**: 2025-10-27
**Environment**: UAT
**Cluster**: dailytumour-uat-gke
**Region**: australia-southeast1
**Project**: focal-psyche-460009-a5
