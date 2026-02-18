#!/bin/bash

# Deploy Node.js Fullstack to AKS
# Usage: ./deploy-to-aks.sh RESOURCE_GROUP CLUSTER_NAME ACR_NAME

set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: Missing required parameters"
  echo "Usage: ./deploy-to-aks.sh RESOURCE_GROUP CLUSTER_NAME ACR_NAME"
  echo ""
  echo "Example: ./deploy-to-aks.sh myResourceGroup myAKSCluster myACR"
  exit 1
fi

RESOURCE_GROUP=$1
CLUSTER_NAME=$2
ACR_NAME=$3
LOCATION="eastus"
NODE_COUNT=1
VM_SIZE="Standard_DC2as_v5"

echo "🚀 Deploying to Azure Kubernetes Service (AKS)..."
echo "Resource Group: $RESOURCE_GROUP"
echo "Cluster Name: $CLUSTER_NAME"
echo "ACR Name: $ACR_NAME"
echo "Location: $LOCATION"
echo "Node Count: $NODE_COUNT"
echo "VM Size: $VM_SIZE"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first:"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
echo "🔐 Checking Azure login status..."
if ! az account show &> /dev/null; then
    echo "Please login to Azure..."
    az login
fi

echo ""
echo "📦 Step 1: Creating Resource Group (if not exists)..."
az group create --name $RESOURCE_GROUP --location $LOCATION || true

echo ""
echo "🐳 Step 2: Creating Azure Container Registry (if not exists)..."
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --location $LOCATION || echo "ACR already exists or creation skipped"

echo ""
echo "🔧 Step 3: Building and pushing Docker images to ACR..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first:"
    echo "   https://docs.docker.com/get-docker/"
    exit 1
fi

# Login to ACR
az acr login --name $ACR_NAME

ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

# Build and push backend
echo "Building backend locally..."
docker build -t ${ACR_LOGIN_SERVER}/nodejs-fullstack/backend:latest ./backend
echo "Pushing backend to ACR..."
docker push ${ACR_LOGIN_SERVER}/nodejs-fullstack/backend:latest

# Build and push frontend
echo "Building frontend locally..."
docker build -t ${ACR_LOGIN_SERVER}/nodejs-fullstack/frontend:latest ./frontend
echo "Pushing frontend to ACR..."
docker push ${ACR_LOGIN_SERVER}/nodejs-fullstack/frontend:latest

echo "✅ Images pushed successfully to ACR"
echo ""

echo "☸️  Step 4: Creating AKS cluster (this may take 5-10 minutes)..."
echo "Configuration:"
echo "   - 1 node with $VM_SIZE"
echo "   - Auto-scaling disabled"
echo "   - Basic networking"
echo ""
# Register required providers first
echo "Registering Azure providers (if not already registered)..."
az provider register --namespace Microsoft.ContainerService --wait || true
az provider register --namespace Microsoft.Network --wait || true

# Create AKS cluster with available VM size
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --node-count $NODE_COUNT \
  --node-vm-size $VM_SIZE \
  --location $LOCATION \
  --attach-acr $ACR_NAME \
  --enable-managed-identity \
  --generate-ssh-keys \
  --network-plugin kubenet \
  --yes || echo "Cluster might already exist, continuing..."
  --network-policy azure || echo "Cluster might already exist, continuing..."

echo ""
echo "✅ AKS cluster created/verified"

echo ""
echo "🔑 Step 5: Getting AKS credentials..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing

echo ""
echo "🔧 Step 6: Updating K8s manifests with ACR name..."
# Update image paths in deployment file
sed "s|ACR_NAME|${ACR_NAME}|g" k8s/deployment-aks.yaml > k8s/deployment-aks-temp.yaml

echo ""
echo "🔐 Step 7: Creating secrets..."
if [ ! -f "k8s/secret-aks.yaml" ]; then
  echo "⚠️  WARNING: k8s/secret-aks.yaml not found!"
  echo "Please create it from k8s/secret-aks.yaml.template"
  echo ""
  echo "Steps:"
  echo "1. cp k8s/secret-aks.yaml.template k8s/secret-aks.yaml"
  echo "2. Edit k8s/secret-aks.yaml with your MongoDB URI and JWT secret"
  echo "3. Run: kubectl apply -f k8s/secret-aks.yaml"
  echo ""
  echo "Then re-run this script or continue manually with:"
  echo "  kubectl apply -f k8s/configmap.yaml"
  echo "  kubectl apply -f k8s/deployment-aks-temp.yaml"
  echo "  kubectl apply -f k8s/service-aks.yaml"
  exit 1
else
  kubectl apply -f k8s/secret-aks.yaml
  echo "✅ Secrets created"
fi

echo ""
echo "📋 Step 8: Applying ConfigMaps..."
kubectl apply -f k8s/configmap.yaml

echo ""
echo "🚀 Step 9: Deploying applications..."
kubectl apply -f k8s/deployment-aks-temp.yaml
kubectl apply -f k8s/service-aks.yaml

echo ""
echo "⏳ Step 10: Waiting for deployments to be ready..."
kubectl rollout status deployment/task-manager-backend --timeout=5m
kubectl rollout status deployment/task-manager-frontend --timeout=5m

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Checking cluster status..."
kubectl get nodes
echo ""
kubectl get pods
echo ""
kubectl get services

echo ""
echo "🌐 Getting external IP address..."
echo "Waiting for LoadBalancer to assign external IP (this may take 1-2 minutes)..."
sleep 10

EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
    EXTERNAL_IP=$(kubectl get service task-manager-frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$EXTERNAL_IP" ]; then
        echo "⏳ Waiting for external IP..."
        sleep 10
    fi
done

echo ""
echo "🎉 SUCCESS! Your application is deployed!"
echo ""
echo "📱 Access your application at:"
echo "   Frontend: http://$EXTERNAL_IP"
echo ""
echo "🛠️  Useful commands:"
echo "   View logs: kubectl logs -l app=task-manager-backend"
echo "   Scale app: kubectl scale deployment/task-manager-backend --replicas=2"
echo "   Delete app: kubectl delete -f k8s/deployment-aks-temp.yaml -f k8s/service-aks.yaml"
echo "   Delete cluster: az aks delete --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --yes"
echo ""

# Clean up temp file
rm -f k8s/deployment-aks-temp.yaml
