#!/bin/bash

# Cadence Deployment Script for DailyTumour UAT
# This script deploys Cadence with ArgoCD and initializes the database schema

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="focal-psyche-460009-a5"
CLUSTER_NAME="dailytumour-uat-gke"
CLUSTER_REGION="australia-southeast1-a"
NAMESPACE="cadence"
MYSQL_HOST="10.3.65.5"
MYSQL_PORT="3306"
MYSQL_USER="cadence"
DB_NAME="cadence1"
VISIBILITY_DB="cadence_visibility1"

echo "========================================"
echo "  Cadence Deployment - DailyTumour UAT"
echo "========================================"
echo ""

# Function to print step headers
print_step() {
    echo ""
    echo -e "${BLUE}===> $1${NC}"
    echo ""
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
print_step "Step 1: Checking prerequisites"

command -v gcloud >/dev/null 2>&1 || { print_error "gcloud CLI is not installed"; exit 1; }
print_success "gcloud CLI is installed"

command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is not installed"; exit 1; }
print_success "kubectl is installed"

# Get cluster credentials
print_step "Step 2: Getting GKE cluster credentials"
gcloud container clusters get-credentials $CLUSTER_NAME \
  --region=$CLUSTER_REGION \
  --project=$PROJECT_ID

print_success "Connected to cluster: $(kubectl config current-context)"

# Create namespace
print_step "Step 3: Creating namespace"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
print_success "Namespace '$NAMESPACE' ready"

# Apply ExternalSecret for MySQL credentials
print_step "Step 4: Applying MySQL credentials ExternalSecret"
if [ -f "argocd-deploy/cadence-credentials.yaml" ]; then
    kubectl apply -f argocd-deploy/cadence-credentials.yaml
    print_success "ExternalSecret applied"
else
    print_error "File argocd-deploy/cadence-credentials.yaml not found"
    exit 1
fi

# Wait for secret to be created by ESO
print_step "Step 5: Waiting for secret to be synced by External Secrets Operator"
echo "This may take up to 2 minutes..."

TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if kubectl get secret cadence-mysql -n $NAMESPACE >/dev/null 2>&1; then
        print_success "Secret 'cadence-mysql' created successfully"
        break
    fi
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_error "Timeout waiting for secret creation"
    print_warning "Check ExternalSecret status:"
    kubectl describe externalsecret cadence-mysql -n $NAMESPACE
    exit 1
fi

# Verify secret contents
print_step "Step 6: Verifying secret contents"
SECRET_KEYS=$(kubectl get secret cadence-mysql -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]')
echo "Secret keys:"
echo "$SECRET_KEYS" | sed 's/^/  - /'
print_success "Secret verified"

# Apply Cadence ArgoCD application
print_step "Step 7: Applying Cadence ArgoCD application"
if [ -f "argocd-deploy/cadence.yaml" ]; then
    kubectl apply -f argocd-deploy/cadence.yaml
    print_success "ArgoCD application applied"
else
    print_error "File argocd-deploy/cadence.yaml not found"
    exit 1
fi

# Wait for pods to be created
print_step "Step 8: Waiting for Cadence pods to be created"
echo "This may take a few minutes..."

sleep 30

# Check pod status
print_step "Step 9: Checking pod status"
kubectl get pods -n $NAMESPACE

echo ""
read -p "Do you want to initialize the database schema now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Step 10: Initializing database schema"

    # Get MySQL password from secret
    MYSQL_PWD=$(kubectl get secret cadence-mysql -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)

    # Create schema initialization job
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: cadence-schema-init
  namespace: $NAMESPACE
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
          value: "$MYSQL_USER"
        - name: MYSQL_HOST
          value: "$MYSQL_HOST"
        - name: DB_PORT
          value: "$MYSQL_PORT"
        - name: KEYSPACE
          value: "$DB_NAME"
        - name: VISIBILITY_KEYSPACE
          value: "$VISIBILITY_DB"
        command:
        - /bin/bash
        - -c
        - |
          set -ex
          echo "Initializing Cadence schema..."

          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$KEYSPACE setup-schema -v 0.0
          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$KEYSPACE update-schema -d /etc/cadence/schema/mysql/v8/cadence/versioned

          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$VISIBILITY_KEYSPACE setup-schema -v 0.0
          cadence-sql-tool --ep \$MYSQL_HOST -p \$DB_PORT -u \$MYSQL_USER --pw \$MYSQL_PWD --db \$VISIBILITY_KEYSPACE update-schema -d /etc/cadence/schema/mysql/v8/visibility/versioned

          echo "Schema initialization complete!"
EOF

    print_success "Schema initialization job created"
    echo ""
    echo "Monitor job progress with:"
    echo "  kubectl logs -n $NAMESPACE -l job-name=cadence-schema-init -f"
else
    print_warning "Skipping database schema initialization"
    echo "You can initialize it later with:"
    echo "  kubectl apply -f <schema-init-job.yaml>"
fi

# Print summary
echo ""
echo "========================================"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo "========================================"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Monitor deployment:"
echo "   kubectl get pods -n $NAMESPACE -w"
echo ""
echo "2. Check ArgoCD application:"
echo "   argocd app get cadence"
echo ""
echo "3. View logs:"
echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=frontend --tail=50"
echo ""
echo "4. Access Cadence Web UI:"
echo "   kubectl port-forward -n $NAMESPACE svc/cadence-web 8088:8088"
echo "   Then open: http://localhost:8088"
echo ""
echo "5. Test Cadence CLI:"
echo "   kubectl port-forward -n $NAMESPACE svc/cadence-frontend 7933:7933"
echo "   cadence --address localhost:7933 domain list"
echo ""
echo -e "${YELLOW}For troubleshooting, see QUICKSTART.md${NC}"
echo ""
