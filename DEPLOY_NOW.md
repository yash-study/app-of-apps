# Deploy Cadence NOW - Quick Guide

## Prerequisites ✅ (Already Done)
- ✅ GKE cluster running
- ✅ External Secrets Operator (ESO) installed
- ✅ GCP Secret Manager configured
- ✅ ArgoCD installed
- ✅ Cloud SQL MySQL running (10.3.65.5)

---

## Step 1: Create MySQL Password Secret (2 minutes)

```bash
# Generate password
PASSWORD=$(openssl rand -base64 32)
echo "Password: $PASSWORD"  # SAVE THIS!

# Create in Secret Manager
echo -n "$PASSWORD" | gcloud secrets create dailytumour-uat-db-mysql-cadence-password \
  --data-file=- \
  --replication-policy="automatic" \
  --project=focal-psyche-460009-a5
```

---

## Step 2: Create MySQL Databases (3 minutes)

```bash
gcloud sql connect dailytumour-uat-db-mysql --user=root --project=focal-psyche-460009-a5
```

```sql
CREATE DATABASE IF NOT EXISTS cadence1;
CREATE DATABASE IF NOT EXISTS cadence_visibility1;
CREATE USER IF NOT EXISTS 'cadence'@'%' IDENTIFIED BY 'YOUR_PASSWORD_FROM_STEP1';
GRANT ALL PRIVILEGES ON cadence1.* TO 'cadence'@'%';
GRANT ALL PRIVILEGES ON cadence_visibility1.* TO 'cadence'@'%';
FLUSH PRIVILEGES;
EXIT;
```

---

## Step 3: Push Helm Chart to GitHub (1 minute)

```bash
cd /Users/appointy/cadence-deploy-uat/app-of-apps

# Add all files
git add .

# Commit
git commit -m "Add Cadence Helm chart and deployment configs"

# Push
git push origin main
```

---

## Step 4: Deploy via ArgoCD (1 minute)

```bash
# Get GKE credentials
gcloud container clusters get-credentials dailytumour-uat-gke \
  --region=australia-southeast1-a \
  --project=focal-psyche-460009-a5

# Apply ExternalSecret (creates cadence-mysql secret from GCP Secret Manager)
kubectl apply -f argocd-deploy/cadence-credentials.yaml

# Wait 30 seconds for ESO to sync secret
sleep 30

# Apply Cadence ArgoCD application
kubectl apply -f argocd-deploy/cadence.yaml

# Watch deployment
kubectl get pods -n cadence -w
```

---

## Step 5: Initialize Database Schema (2 minutes)

```bash
# Get password from secret
MYSQL_PWD=$(kubectl get secret cadence-mysql -n cadence -o jsonpath='{.data.password}' | base64 -d)

# Run schema init job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: cadence-schema-init
  namespace: cadence
spec:
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
        command:
        - /bin/bash
        - -c
        - |
          cadence-sql-tool --ep 10.3.65.5 -p 3306 -u cadence --pw \$MYSQL_PWD --db cadence1 setup-schema -v 0.0
          cadence-sql-tool --ep 10.3.65.5 -p 3306 -u cadence --pw \$MYSQL_PWD --db cadence1 update-schema -d /etc/cadence/schema/mysql/v8/cadence/versioned
          cadence-sql-tool --ep 10.3.65.5 -p 3306 -u cadence --pw \$MYSQL_PWD --db cadence_visibility1 setup-schema -v 0.0
          cadence-sql-tool --ep 10.3.65.5 -p 3306 -u cadence --pw \$MYSQL_PWD --db cadence_visibility1 update-schema -d /etc/cadence/schema/mysql/v8/visibility/versioned
EOF

# Watch logs
kubectl logs -n cadence -l job-name=cadence-schema-init -f
```

---

## Step 6: Verify (1 minute)

```bash
# Check pods (should all be Running)
kubectl get pods -n cadence

# Expected:
# cadence-frontend-xxx    1/1  Running
# cadence-frontend-xxx    1/1  Running
# cadence-history-0       1/1  Running
# cadence-history-1       1/1  Running
# cadence-history-2       1/1  Running
# cadence-matching-xxx    1/1  Running
# cadence-matching-xxx    1/1  Running
# cadence-worker-xxx      1/1  Running
# cadence-web-xxx         1/1  Running
```

---

## Step 7: Access Web UI

```bash
# Port forward
kubectl port-forward -n cadence svc/cadence-web 8088:8088
```

Open: **http://localhost:8088**

---

## Done! 🎉

Total time: **~10 minutes**

### What You Have:
- ✅ Cadence deployed on GKE
- ✅ 2x Frontend (for HA)
- ✅ 3x History (for load distribution)
- ✅ 2x Matching
- ✅ 1x Worker
- ✅ 1x Web UI
- ✅ Auto-sync with ArgoCD (any Git push auto-deploys)
- ✅ Secrets from GCP Secret Manager
- ✅ Running on dedicated `cadence` node pool

### Next Steps:
1. Register a domain:
   ```bash
   kubectl exec -it -n cadence deployment/cadence-frontend -- \
     cadence domain register --domain my-domain
   ```

2. Scale if needed (edit `helm/cadence/values-uat.yaml` and push to Git)

3. Monitor with Prometheus (metrics on port 9090)

---

## Troubleshooting

**Secret not created?**
```bash
kubectl describe externalsecret cadence-mysql -n cadence
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

**Pods not starting?**
```bash
kubectl describe pod -n cadence <pod-name>
kubectl get events -n cadence --sort-by='.lastTimestamp'
```

**Schema init failed?**
```bash
kubectl logs -n cadence -l job-name=cadence-schema-init
# Delete and retry:
kubectl delete job cadence-schema-init -n cadence
# Then re-run Step 5
```
