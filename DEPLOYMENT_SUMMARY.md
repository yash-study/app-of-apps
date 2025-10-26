# Cadence Deployment Summary

## What Has Been Created

This deployment setup creates a complete Cadence infrastructure on GKE with:
- ✅ ArgoCD GitOps automation
- ✅ Google Secret Manager integration via External Secrets Operator
- ✅ Cloud SQL MySQL database backend
- ✅ Helm chart-based deployment
- ✅ High availability configuration

## Files Created

### 1. Infrastructure Repository (Current Directory)

```
app-of-apps/
├── QUICKSTART.md                          # Step-by-step deployment guide
├── DEPLOYMENT_SUMMARY.md                  # This file
├── deploy-cadence.sh                      # Automated deployment script
├── dailytumour-uat.yaml                   # ArgoCD App of Apps (existing)
├── wcc.yaml                               # (existing)
│
├── argocd-deploy/
│   ├── cadence-credentials.yaml           # ExternalSecret for MySQL (existing)
│   ├── cadence.yaml                       # ArgoCD Application for Cadence (existing)
│   └── apps/cadence/
│       └── values-uat.yaml                # Environment-specific overrides (existing)
│
└── helm-chart-reference/                  # Reference Helm chart (copy to app repo)
    ├── README.md                          # How to use the reference chart
    └── cadence/
        ├── Chart.yaml                     # Helm chart metadata
        ├── values.yaml                    # Default values
        └── templates/
            ├── _helpers.tpl               # Template helpers
            ├── serviceaccount.yaml        # Kubernetes ServiceAccount
            ├── configmap.yaml             # Cadence configuration
            ├── frontend-deployment.yaml   # Frontend Deployment
            ├── frontend-service.yaml      # Frontend Service
            ├── web-deployment.yaml        # Web UI Deployment
            └── web-service.yaml           # Web UI Service
```

### 2. Application Repository (TO BE CREATED)

You need to create a separate repository for the Cadence Helm chart:

**Repository Name**: `dailytumour-cadence` (or your choice)
**Structure**: Copy from `helm-chart-reference/`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      GCP Project                                 │
│                 focal-psyche-460009-a5                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐                 ┌──────────────────────┐  │
│  │  GKE Cluster     │    Private IP   │  Cloud SQL MySQL     │  │
│  │  australia-se1-a │ ◄────────────── │  10.3.65.5          │  │
│  │                  │                 │                      │  │
│  │  Namespace:      │                 │  Databases:          │  │
│  │  ┌────────────┐  │                 │  - cadence1          │  │
│  │  │  cadence   │  │                 │  - cadence_visibility1│ │
│  │  │            │  │                 │                      │  │
│  │  │ Components:│  │                 │  User: cadence       │  │
│  │  │ • frontend │  │                 └──────────────────────┘  │
│  │  │ • history  │  │                           ▲               │
│  │  │ • matching │  │                           │               │
│  │  │ • worker   │  │                    Password from          │
│  │  │ • web      │  │                           │               │
│  │  └────────────┘  │                 ┌─────────┴────────────┐  │
│  │                  │                 │  Secret Manager      │  │
│  │  ┌────────────┐  │  Syncs Secrets │  • MySQL Password    │  │
│  │  │    ESO     │ ─┼────────────────┤                      │  │
│  │  │ (External  │  │                 └──────────────────────┘  │
│  │  │  Secrets)  │  │                                          │
│  │  └────────────┘  │                                          │
│  │                  │                                          │
│  │  ┌────────────┐  │  Monitors Git                           │
│  │  │  ArgoCD    │ ─┼──► dailytumour-uat-infrastructure       │
│  │  │            │ ─┼──► dailytumour-cadence (app repo)       │
│  │  └────────────┘  │                                          │
│  └──────────────────┘                                          │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment Flow

### Prerequisites
1. GKE cluster running
2. Cloud SQL MySQL instance running
3. Databases created (`cadence1`, `cadence_visibility1`)
4. MySQL user `cadence` created
5. External Secrets Operator installed
6. ArgoCD installed
7. ClusterSecretStore configured

### Step-by-Step Process

#### Phase 1: Prepare Secrets
1. Create MySQL password in Google Secret Manager
   ```bash
   echo -n "your-password" | gcloud secrets create dailytumour-uat-db-mysql-cadence-password --data-file=-
   ```

2. Create MySQL user in Cloud SQL
   ```sql
   CREATE USER 'cadence'@'%' IDENTIFIED BY 'your-password';
   GRANT ALL PRIVILEGES ON cadence1.* TO 'cadence'@'%';
   GRANT ALL PRIVILEGES ON cadence_visibility1.* TO 'cadence'@'%';
   ```

#### Phase 2: Setup Application Repository
1. Create new Git repository: `dailytumour-cadence`
2. Copy Helm chart from `helm-chart-reference/`
3. Create missing templates (history, matching, worker)
4. Commit and push to Git

#### Phase 3: Deploy via ArgoCD
1. Get GKE credentials
   ```bash
   gcloud container clusters get-credentials dailytumour-uat-gke --region=australia-southeast1-a
   ```

2. Apply ExternalSecret
   ```bash
   kubectl apply -f argocd-deploy/cadence-credentials.yaml
   ```

3. Wait for secret sync
   ```bash
   kubectl wait --for=condition=Ready externalsecret/cadence-mysql -n cadence --timeout=120s
   ```

4. Deploy Cadence via ArgoCD
   ```bash
   kubectl apply -f argocd-deploy/cadence.yaml
   ```

#### Phase 4: Initialize Database
1. Run schema initialization job (see QUICKSTART.md)
2. Verify tables created

#### Phase 5: Verify Deployment
1. Check pods running
   ```bash
   kubectl get pods -n cadence
   ```

2. Access Web UI
   ```bash
   kubectl port-forward -n cadence svc/cadence-web 8088:8088
   ```

3. Test Cadence CLI
   ```bash
   kubectl port-forward -n cadence svc/cadence-frontend 7933:7933
   cadence --address localhost:7933 domain list
   ```

## Quick Deployment

### Automated (Recommended)
```bash
./deploy-cadence.sh
```

### Manual
See [QUICKSTART.md](QUICKSTART.md)

## Configuration

### Environment Variables from Secret

The `cadence-mysql` secret (created by ESO) contains:

| Key | Description | Example |
|-----|-------------|---------|
| `password` | MySQL password | `***` |
| `user` | MySQL username | `cadence` |
| `host` | MySQL host | `10.3.65.5` |
| `port` | MySQL port | `3306` |
| `MYSQL_PWD` | MySQL password (env var format) | `***` |
| `MYSQL_USER` | MySQL user (env var format) | `cadence` |
| `MYSQL_SEEDS` | MySQL host (env var format) | `10.3.65.5` |
| `DB` | Database type | `mysql` |
| `DB_PORT` | Database port | `3306` |
| `KEYSPACE` | Default database name | `cadence1` |
| `VISIBILITY_KEYSPACE` | Visibility database name | `cadence_visibility1` |
| `CADENCE_STORE_DSN` | Full connection string for default DB | `cadence:***@tcp(10.3.65.5:3306)/cadence1?...` |
| `CADENCE_VISIBILITY_STORE_DSN` | Full connection string for visibility DB | `cadence:***@tcp(10.3.65.5:3306)/cadence_visibility1?...` |

### Resource Allocation

| Component | Replicas | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|----------|-------------|----------------|-----------|--------------|
| Frontend | 2 | 200m | 512Mi | 1000m | 1Gi |
| History | 3 | 500m | 1Gi | 2000m | 2Gi |
| Matching | 2 | 200m | 512Mi | 1000m | 1Gi |
| Worker | 1 | 200m | 512Mi | 1000m | 1Gi |
| Web | 1 | 100m | 256Mi | 500m | 512Mi |

**Total**: ~2.4 CPU cores, ~5.5 GB RAM (requests)

### Node Placement

All Cadence pods are scheduled on nodes with:
- **Label**: `workload=cadence`
- **Taint**: `workload=cadence:NoSchedule`

This ensures Cadence runs on dedicated nodes.

## Monitoring

### View Logs
```bash
# All Cadence logs
kubectl logs -n cadence -l app.kubernetes.io/name=cadence --all-containers

# Frontend logs
kubectl logs -n cadence -l app.kubernetes.io/component=frontend -f

# History logs
kubectl logs -n cadence -l app.kubernetes.io/component=history -f
```

### Check Status
```bash
# Pods
kubectl get pods -n cadence -o wide

# Services
kubectl get svc -n cadence

# ExternalSecret
kubectl get externalsecret cadence-mysql -n cadence

# ArgoCD
argocd app get cadence
```

### Prometheus Metrics
Metrics are exposed on port `9090` for all components.

```bash
kubectl port-forward -n cadence svc/cadence-frontend 9090:9090
curl http://localhost:9090/metrics
```

## Troubleshooting

### Common Issues

#### 1. Secret Not Created
**Symptom**: `cadence-mysql` secret missing

**Solution**:
```bash
# Check ExternalSecret status
kubectl describe externalsecret cadence-mysql -n cadence

# Check ESO logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# Verify GCP Secret exists
gcloud secrets describe dailytumour-uat-db-mysql-cadence-password
```

#### 2. Pods Not Starting
**Symptom**: Pods stuck in Pending

**Solution**:
```bash
# Check events
kubectl describe pod -n cadence <pod-name>

# Verify node labels
kubectl get nodes --show-labels | grep workload
```

#### 3. Cannot Connect to MySQL
**Symptom**: Connection refused errors

**Solution**:
```bash
# Test MySQL connectivity from cluster
kubectl run -it --rm mysql-test --image=mysql:8.4 --restart=Never -- \
  mysql -h 10.3.65.5 -P 3306 -u cadence -p
```

#### 4. Schema Not Initialized
**Symptom**: Tables missing in database

**Solution**:
Re-run schema initialization (see QUICKSTART.md Step 6)

## Security

### Workload Identity
Cadence pods use Workload Identity to access Google Secret Manager:

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: dailytumour-uat-eso@focal-psyche-460009-a5.iam.gserviceaccount.com
```

### Secret Management
- Secrets stored in Google Secret Manager (encrypted at rest)
- Synced to Kubernetes by External Secrets Operator
- Never committed to Git
- Auto-rotated by ESO (refresh interval: 1m)

### Network Security
- MySQL accessible only via private IP (10.3.65.5)
- No public endpoints for Cadence services
- Access via kubectl port-forward or Istio VirtualService

## Maintenance

### Updating Cadence Version
1. Update image tag in application repository (`values-uat.yaml`)
2. Commit and push
3. ArgoCD auto-syncs the change

### Scaling Components
```bash
# Scale history service
kubectl scale statefulset cadence-history -n cadence --replicas=5

# Or update values-uat.yaml and let ArgoCD sync
```

### Backup Strategy
1. **Database**: Cloud SQL automated backups (7-day retention)
2. **Secrets**: Google Secret Manager versioning
3. **Config**: Git version control

### Disaster Recovery
1. Restore Cloud SQL from backup
2. Re-apply ArgoCD applications
3. Verify Cadence operational

## Next Steps

1. ✅ Review [QUICKSTART.md](QUICKSTART.md)
2. ⬜ Create application repository (`dailytumour-cadence`)
3. ⬜ Copy Helm chart from reference
4. ⬜ Create missing component templates
5. ⬜ Update ArgoCD application with repo URL
6. ⬜ Run deployment script: `./deploy-cadence.sh`
7. ⬜ Initialize database schema
8. ⬜ Register Cadence domains
9. ⬜ Configure monitoring/alerting
10. ⬜ Set up Istio VirtualService for Web UI

## Support & Documentation

- **Cadence Official Docs**: https://cadenceworkflow.io/docs/
- **Cadence GitHub**: https://github.com/uber/cadence
- **Cadence Slack**: https://cadenceworkflow.slack.com
- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **External Secrets Operator**: https://external-secrets.io/
- **Helm Docs**: https://helm.sh/docs/

## Contact

For issues or questions:
- Platform Team: platform@dailytumour.com
- Create issue in infrastructure repository

---

**Generated**: 2025-10-27
**Version**: 1.0.0
**Environment**: UAT
**Cluster**: dailytumour-uat-gke
