#!/bin/bash

# Deploy Node.js Fullstack to AKS
# Usage: ./deploy-to-aks.sh RESOURCE_GROUP CLUSTER_NAME ACR_NAME [LOCATION] [VM_SIZE]

set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: Missing required parameters"
  echo "Usage: ./deploy-to-aks.sh RESOURCE_GROUP CLUSTER_NAME ACR_NAME [LOCATION] [VM_SIZE]"
  echo ""
  echo "Example: ./deploy-to-aks.sh myResourceGroup myAKSCluster myACR swedencentral Standard_D2as_v4"
  exit 1
fi

RESOURCE_GROUP=$1
CLUSTER_NAME=$2
ACR_NAME=$3
LOCATION="${4:-eastus}"
DEFAULT_VM_SIZE="Standard_D2as_v4"
VM_SIZE="${5:-$DEFAULT_VM_SIZE}"
NODE_COUNT=1

is_vm_size_available() {
  local location="$1"
  local size="$2"
  local count

  count=$(az vm list-skus \
    --location "$location" \
    --resource-type virtualMachines \
    --query "[?name=='$size' && length(restrictions)==\`0\`] | length(@)" \
    -o tsv 2>/dev/null || echo "0")

  [ "$count" != "0" ]
}

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

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SPENDING_LIMIT=$(az rest \
  --method get \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}?api-version=2020-01-01" \
  --query "subscriptionPolicies.spendingLimit" \
  -o tsv 2>/dev/null || echo "Unknown")

if [ "$SPENDING_LIMIT" = "On" ]; then
  echo "✅ Spending limit is ON for this subscription (hard cap enforced by Azure)."
else
  echo "⚠️  Spending limit status: $SPENDING_LIMIT"
  echo "   This script cannot guarantee zero overage if spending limit is off."
fi

echo ""
echo "🧩 Ensuring required Azure providers are registered..."
for PROVIDER in Microsoft.ContainerRegistry Microsoft.ContainerService Microsoft.Network Microsoft.Compute; do
  az provider register --namespace "$PROVIDER" --wait > /dev/null
done
echo "✅ Required providers are registered"

# If the resource group already exists, force its location to avoid InvalidResourceGroupLocation.
if [ "$(az group exists --name "$RESOURCE_GROUP")" = "true" ]; then
    EXISTING_RG_LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
    if [ "$LOCATION" != "$EXISTING_RG_LOCATION" ]; then
        echo "⚠️  Resource group '$RESOURCE_GROUP' exists in '$EXISTING_RG_LOCATION'. Using that location."
    fi
    LOCATION="$EXISTING_RG_LOCATION"
fi

# If selected VM size is unavailable in region/subscription, select a reasonable fallback.
if ! is_vm_size_available "$LOCATION" "$VM_SIZE"; then
  echo "⚠️  VM size '$VM_SIZE' is not available in '$LOCATION' for this subscription."

  for CANDIDATE_VM_SIZE in Standard_D2as_v4 Standard_D2s_v4 Standard_D2as_v5 Standard_D2s_v5 Standard_B2s Standard_B2ms Standard_B2ps_v2; do
    if is_vm_size_available "$LOCATION" "$CANDIDATE_VM_SIZE"; then
      VM_SIZE="$CANDIDATE_VM_SIZE"
      echo "✅ Using fallback VM size: $VM_SIZE"
      break
    fi
  done

  if ! is_vm_size_available "$LOCATION" "$VM_SIZE"; then
    echo "❌ No supported fallback VM size was found automatically."
    echo "   List available sizes with: az vm list-skus --location $LOCATION --resource-type virtualMachines -o table"
    echo "   Then re-run: ./deploy-to-aks.sh $RESOURCE_GROUP $CLUSTER_NAME $ACR_NAME $LOCATION <VM_SIZE>"
    exit 1
  fi
fi

echo "📍 Using deployment location: $LOCATION"
echo "🖥️  Using node VM size: $VM_SIZE"

echo ""
echo "📦 Step 1: Creating Resource Group (if not exists)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

echo ""
echo "🐳 Step 2: Creating Azure Container Registry (if not exists)..."
if az acr show --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" &> /dev/null; then
  echo "ACR already exists, skipping creation"
else
  az acr create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACR_NAME" \
    --sku Basic \
    --location "$LOCATION"
fi

if ! az acr show --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" &> /dev/null; then
  echo "❌ ACR '$ACR_NAME' was not found in resource group '$RESOURCE_GROUP'."
  echo "   Creation may have been blocked by a region policy in this subscription."
  echo "   Re-run with a policy-allowed location, for example:"
  echo "   ./deploy-to-aks.sh $RESOURCE_GROUP $CLUSTER_NAME $ACR_NAME westus2"
  exit 1
fi

echo ""
echo "🔧 Step 3: Building and pushing Docker images to ACR..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first:"
    echo "   https://docs.docker.com/get-docker/"
    exit 1
fi

# Login to ACR
az acr login --name "$ACR_NAME"

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
# Providers were registered earlier in the script.

# Create AKS cluster only if it does not exist.
if az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &> /dev/null; then
  echo "AKS cluster already exists, skipping creation"
else
  az aks create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --node-count "$NODE_COUNT" \
    --node-vm-size "$VM_SIZE" \
    --location "$LOCATION" \
    --attach-acr "$ACR_NAME" \
    --enable-managed-identity \
    --generate-ssh-keys \
    --network-plugin kubenet \
    --yes
fi

echo ""
echo "✅ AKS cluster created/verified"

echo ""
echo "🔑 Step 5: Getting AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo ""
echo "🔧 Step 6: Updating K8s manifests with ACR name..."
# Update image paths in deployment file
sed "s|ACR_NAME|${ACR_NAME}|g" k8s/deployment-aks.yaml > k8s/deployment-aks-temp.yaml

echo ""
echo "🍃 Step 7: Deploying in-cluster MongoDB (if manifest exists)..."
if [ -f "k8s/mongodb-aks.yaml" ]; then
  kubectl apply -f k8s/mongodb-aks.yaml
  kubectl rollout status deployment/task-manager-mongodb --timeout=5m
  echo "✅ MongoDB deployment ready"
else
  echo "k8s/mongodb-aks.yaml not found, skipping local MongoDB deployment"
fi

echo ""
echo "🔐 Step 8: Creating secrets..."
if [ ! -f "k8s/secret-aks.yaml" ]; then
  echo "⚠️  WARNING: k8s/secret-aks.yaml not found!"
  echo "Please create it from k8s/secret-aks.yaml.example"
  echo ""
  echo "Steps:"
  echo "1. cp k8s/secret-aks.yaml.example k8s/secret-aks.yaml"
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
echo "📋 Step 9: Applying ConfigMaps..."
kubectl apply -f k8s/configmap.yaml

echo ""
echo "🚀 Step 10: Deploying applications..."
kubectl apply -f k8s/deployment-aks-temp.yaml
kubectl apply -f k8s/service-aks.yaml

echo ""
echo "⏳ Step 11: Waiting for deployments to be ready..."
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
echo "🔒 Updating backend CORS origin to frontend URL..."
kubectl set env deployment/task-manager-backend FRONTEND_URL="http://$EXTERNAL_IP" > /dev/null
kubectl rollout status deployment/task-manager-backend --timeout=5m
echo "✅ Backend CORS origin set to http://$EXTERNAL_IP"

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
