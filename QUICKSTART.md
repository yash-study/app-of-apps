# Cadence Deployment - Quick Start Guide

## Prerequisites Checklist

- [ ] GKE cluster: `dailytumour-uat-gke` is running
- [ ] Cloud SQL MySQL: `10.3.65.5` is accessible
- [ ] Databases created: `cadence1`, `cadence_visibility1`
- [ ] MySQL user `cadence` created with proper permissions
- [ ] External Secrets Operator is installed in cluster
- [ ] ArgoCD is installed and configured
- [ ] ClusterSecretStore `gcpsm-cluster-store` is configured

## Step 1: Create MySQL Password in Google Secret Manager

```bash
# Generate strong password
PASSWORD=$(openssl rand -base64 32)

# Create secret in GCP Secret Manager
echo -n "$PASSWORD" | gcloud secrets create dailytumour-uat-db-mysql-cadence-password \
  --data-file=- \
  --replication-policy="automatic" \
  --project=focal-psyche-460009-a5 \
  --labels=app=cadence,environment=uat

# Verify secret created
gcloud secrets describe dailytumour-uat-db-mysql-cadence-password \
  --project=focal-psyche-460009-a5
```

## Step 2: Create MySQL User and Databases

```bash
# Connect to Cloud SQL
gcloud sql connect dailytumour-uat-db-mysql \
  --user=root \
  --project=focal-psyche-460009-a5

# In MySQL prompt, run:
```

```sql
-- Create databases if they don't exist
CREATE DATABASE IF NOT EXISTS cadence1;
CREATE DATABASE IF NOT EXISTS cadence_visibility1;

-- Create user (use the password you generated above)
CREATE USER IF NOT EXISTS 'cadence'@'%' IDENTIFIED BY 'YOUR_PASSWORD_HERE';

-- Grant permissions
GRANT ALL PRIVILEGES ON cadence1.* TO 'cadence'@'%';
GRANT ALL PRIVILEGES ON cadence_visibility1.* TO 'cadence'@'%';
FLUSH PRIVILEGES;

-- Verify
SHOW GRANTS FOR 'cadence'@'%';
```

## Step 3: Get GKE Credentials

```bash
gcloud container clusters get-credentials dailytumour-uat-gke \
  --region=australia-southeast1-a \
  --project=focal-psyche-460009-a5
```

## Step 4: Apply Cadence Credentials ExternalSecret

```bash
# Apply the ExternalSecret
kubectl apply -f argocd-deploy/cadence-credentials.yaml

# Wait for secret to be created (should take < 1 minute)
kubectl wait --for=condition=Ready externalsecret/cadence-mysql \
  -n cadence \
  --timeout=120s

# Verify secret exists
kubectl get secret cadence-mysql -n cadence

# Check secret keys
kubectl get secret cadence-mysql -n cadence -o jsonpath='{.data}' | jq 'keys'
```

## Step 5: Deploy Cadence via ArgoCD

### Option A: Using ArgoCD App-of-Apps (Recommended)

```bash
# The cadence app is already defined in your app-of-apps
# Just sync the parent application
kubectl apply -f dailytumour-uat.yaml

# Or if you have ArgoCD CLI
argocd app sync dailytumour-uat
```

### Option B: Deploy Cadence App Directly

```bash
# Apply Cadence application
kubectl apply -f argocd-deploy/cadence.yaml

# Sync the application
argocd app sync cadence

# Watch deployment
kubectl get pods -n cadence -w
```

## Step 6: Initialize Database Schema

```bash
# Create init job manifest
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
          valueFrom:
            secretKeyRef:
              name: cadence-mysql
              key: password
        - name: MYSQL_USER
          value: cadence
        - name: MYSQL_HOST
          value: "10.3.65.5"
        - name: DB_PORT
          value: "3306"
        - name: KEYSPACE
          value: cadence1
        - name: VISIBILITY_KEYSPACE
          value: cadence_visibility1
        command:
        - /bin/bash
        - -c
        - |
          set -ex

          echo "Initializing default database schema..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$KEYSPACE \
            setup-schema -v 0.0

          echo "Updating default database to latest version..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$KEYSPACE \
            update-schema -d /etc/cadence/schema/mysql/v8/cadence/versioned

          echo "Initializing visibility database schema..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$VISIBILITY_KEYSPACE \
            setup-schema -v 0.0

          echo "Updating visibility database to latest version..."
          cadence-sql-tool \
            --ep \$MYSQL_HOST \
            -p \$DB_PORT \
            -u \$MYSQL_USER \
            --pw \$MYSQL_PWD \
            --db \$VISIBILITY_KEYSPACE \
            update-schema -d /etc/cadence/schema/mysql/v8/visibility/versioned

          echo "Schema initialization complete!"
EOF

# Watch job completion
kubectl logs -n cadence -l job-name=cadence-schema-init -f
```

## Step 7: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n cadence

# Expected output should show:
# - cadence-frontend-xxxx (2 replicas)
# - cadence-history-xxxx (3 replicas)
# - cadence-matching-xxxx (2 replicas)
# - cadence-worker-xxxx (1 replica)
# - cadence-web-xxxx (1 replica)

# Check services
kubectl get svc -n cadence

# View logs
kubectl logs -n cadence -l app.kubernetes.io/component=frontend --tail=50
```

## Step 8: Access Cadence Web UI

```bash
# Port forward to Cadence Web UI
kubectl port-forward -n cadence svc/cadence-web 8088:8088
```

Then open in browser: **http://localhost:8088**

## Step 9: Register a Domain (Optional)

```bash
# Port forward to frontend
kubectl port-forward -n cadence svc/cadence-frontend 7933:7933

# In another terminal, register a domain
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain register \
  --domain test-domain \
  --description "Test domain for UAT"

# List domains
kubectl exec -it -n cadence deployment/cadence-frontend -- \
  cadence --address 127.0.0.1:7933 domain list
```

## Troubleshooting

### Secret Not Created

```bash
# Check ExternalSecret status
kubectl describe externalsecret cadence-mysql -n cadence

# Check ESO logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

### Pods Not Starting

```bash
# Describe pod to see events
kubectl describe pod -n cadence <pod-name>

# Check if nodes have correct labels/taints
kubectl get nodes --show-labels | grep workload
```

### Cannot Connect to MySQL

```bash
# Test MySQL connectivity from cluster
kubectl run -it --rm mysql-test --image=mysql:8.4 --restart=Never -- \
  mysql -h 10.3.65.5 -P 3306 -u cadence -p
```

### Schema Init Job Failed

```bash
# Check job logs
kubectl logs -n cadence -l job-name=cadence-schema-init

# Delete and retry
kubectl delete job cadence-schema-init -n cadence
# Then re-run the Step 6 command
```

## Next Steps

1. **Configure domains** for your workflows
2. **Set up monitoring** with Prometheus/Grafana
3. **Configure Istio VirtualService** for Web UI ingress
4. **Set up backups** for MySQL databases
5. **Configure archival** for workflow history

## Useful Commands

```bash
# Watch all pods
kubectl get pods -n cadence -w

# View frontend logs
kubectl logs -n cadence -l app.kubernetes.io/component=frontend -f

# View history logs
kubectl logs -n cadence -l app.kubernetes.io/component=history -f

# Restart a component
kubectl rollout restart deployment/cadence-frontend -n cadence

# Scale history service
kubectl scale statefulset/cadence-history -n cadence --replicas=5

# ArgoCD sync
argocd app sync cadence --prune

# ArgoCD app status
argocd app get cadence
```

## Important Notes

- **Do NOT commit passwords** to Git
- **Use strong passwords** (minimum 32 characters)
- **Backup MySQL** databases regularly
- **Monitor resource usage** and adjust limits as needed
- **Keep Cadence version** consistent across all components

## Support

- **Documentation**: https://cadenceworkflow.io/docs/
- **GitHub**: https://github.com/uber/cadence
- **Slack**: https://cadenceworkflow.slack.com
