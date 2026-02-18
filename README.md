# Task Manager App

A full-stack task management application with user authentication and production deployment on Azure Kubernetes Service. Built with React, Node.js, Express, and MongoDB.

## Features

- User signup/login with JWT authentication
- Create, edit, and delete tasks
- Set priority levels and due dates
- Filter tasks by status
- View task statistics
- Production deployment on Azure AKS
- Mobile-responsive design

## Live Deployment

**Production URL**: http://13.92.67.123

The application is currently deployed on Azure Kubernetes Service with:
- Backend API: http://20.75.250.160:5000/api
- Frontend: Served via Azure LoadBalancer
- Database: MongoDB Atlas
- Cluster: Standard_DC2as_v5 (1 node)

## Run Locally with Docker

### Prerequisites

- Docker and Docker Compose installed on your machine
- MongoDB Atlas account or local MongoDB

### Steps

1. Clone the repository:
```bash
git clone https://github.com/mahmoudezzat8824/nodejs-fullstack.git
cd nodejs-fullstack
```

2. Set up environment variables:
```bash
# Copy example file and edit with your credentials
cp backend/.env.example backend/.env
# Edit backend/.env with your MongoDB connection string
```

3. Start the application:
```bash
docker compose up --build -d
```

4. Access the application:
   - **Frontend**: http://localhost:3000
   - **Backend API**: http://localhost:5000

5. To stop the application:
```bash
docker compose down
```

## CI/CD Pipeline

Automated deployment using GitHub Actions:

**Required GitHub Secrets:**
- `DOCKER_HUB_USERNAME` - Your Docker Hub username
- `DOCKER_HUB_PASSWORD` - Docker Hub access token
- `AZURE_CREDENTIALS` - Azure service principal JSON

**Workflow:**
- Push to `main` → Test → Build → Deploy to production AKS
- Push to `develop` → Test → Build staging images
- Pull requests → Test only

See [.github/workflows/pipeline.yaml](.github/workflows/pipeline.yaml) for details.

## Deploy to Azure Kubernetes Service (AKS)

### Prerequisites

1. Azure account with active subscription
2. Azure CLI installed and configured
3. Docker installed (for building images locally)
4. MongoDB Atlas account
5. kubectl installed

### Deployment Steps

1. **Prepare your configuration:**

```bash
# Copy the secret template and configure your credentials
cp k8s/secret-aks.yaml.example k8s/secret-aks.yaml

# Edit with your MongoDB URI and JWT secret
nano k8s/secret-aks.yaml
```

Add your MongoDB connection string and JWT secret:
```yaml
stringData:
  MONGO_URI: mongodb+srv://username:password@cluster.mongodb.net/database?retryWrites=true&w=majority
  JWT_SECRET: your-random-secure-string
```

2. **Run the deployment script:**

```bash
./deploy-to-aks.sh RESOURCE_GROUP CLUSTER_NAME ACR_NAME
```

Example:
```bash
./deploy-to-aks.sh rg1 my-cluster1 nodejsacr1771269726
```

The script will:
- Create Azure Container Registry (ACR)
- Build and push Docker images
- Create AKS cluster with available VM types
- Deploy backend and frontend
- Expose services via LoadBalancer

3. **Access your deployed application:**

After deployment completes, get the external IP:
```bash
kubectl get services
```

Access your app at the frontend LoadBalancer IP.

### Important Notes

**Mobile Access:**
- The application is configured to work on both desktop and mobile devices
- Backend is exposed via LoadBalancer for external API access
- Frontend build includes the backend API URL automatically

### Deployment Architecture

```
Azure Cloud
├── Container Registry (ACR)
│   ├── Backend Image
│   └── Frontend Image
└── AKS Cluster
    ├── Backend Pod (LoadBalancer Service)
    ├── Frontend Pod (LoadBalancer Service)
    └── MongoDB Atlas (External)
```

### Troubleshooting

**Pods not starting:**
```bash
kubectl get pods
kubectl describe pod POD_NAME
kubectl logs POD_NAME
```

**Check services:**
```bash
kubectl get services
kubectl describe service SERVICE_NAME
```

**Update application:**
```bash
# Rebuild and push images
docker build -t ACR_NAME.azurecr.io/nodejs-fullstack/backend:latest ./backend
docker push ACR_NAME.azurecr.io/nodejs-fullstack/backend:latest

# Restart deployment
kubectl rollout restart deployment/task-manager-backend
```

## Project Structure

```
├── backend/              # Node.js Express API
│   ├── src/
│   │   ├── server.js     # Entry point
│   │   ├── controllers/  # Route handlers
│   │   ├── models/       # MongoDB schemas
│   │   ├── routes/       # API routes
│   │   └── middleware/   # Auth middleware
│   └── Dockerfile
├── frontend/             # React application
│   ├── src/
│   │   ├── components/   # React components
│   │   ├── context/      # Auth context
│   │   └── services/     # API client
│   └── Dockerfile        # Multi-stage build with API URL
├── k8s/                  # Kubernetes manifests
│   ├── deployment-aks.yaml   # AKS deployments
│   ├── service-aks.yaml      # LoadBalancer services
│   ├── secret-aks.yaml       # Secrets (gitignored)
│   └── configmap.yaml        # Configuration
├── deploy-to-aks.sh      # AKS deployment script
└── docker-compose.yml    # Local development
```

## Technology Stack

- **Frontend**: React, Context API, Axios
- **Backend**: Node.js, Express, MongoDB (Mongoose)
- **Authentication**: JWT, bcryptjs
- **Containerization**: Docker (multi-stage builds)
- **Orchestration**: Azure Kubernetes Service (AKS)
- **Registry**: Azure Container Registry (ACR)
- **Database**: MongoDB Atlas (Free Tier)
- **Infrastructure**: Azure Cloud

## Key Implementation Details

### Frontend Build Configuration
The frontend Dockerfile uses build arguments to inject the backend API URL at build time:
```dockerfile
ARG REACT_APP_API_URL=http://localhost:5000/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL
```

This ensures the frontend works correctly on mobile and desktop devices.

### Kubernetes Services
- **Backend**: LoadBalancer service for external API access
- **Frontend**: LoadBalancer service for web access
- Both services expose public IPs for accessibility from any device

### Security
- Secrets managed via Kubernetes Secret objects
- MongoDB credentials and JWT secrets never committed to repository
- CORS configured for production domains

## License

MIT