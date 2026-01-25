# Wanderlust Kubernetes Production Deployment Guide

## Overview
This directory contains production-ready Kubernetes manifests for the Wanderlust application stack.

## Prerequisites
- Kubernetes cluster (1.24+)
- **NGINX Ingress Controller installed** (See [INGRESS-INSTALLATION.md](./INGRESS-INSTALLATION.md))
- **For AWS EKS: LoadBalancer configured** (See [AWS-EKS-LOADBALANCER.md](./AWS-EKS-LOADBALANCER.md))
- kubectl configured
- Persistent storage provisioned (or hostPath volumes configured)

## File Structure

```
kubernetes/
├── namespace.yaml              # Namespace definition
├── resource-quota.yaml         # Resource quotas for namespace limits
├── limit-range.yaml            # Default resource limits
├── persistentVolume.yaml       # Persistent volumes for MongoDB and Redis
├── persistentVolumeClaim.yaml  # PVCs for MongoDB and Redis
├── mongodb.yaml                # MongoDB deployment, service, config, secrets
├── redis.yaml                  # Redis deployment, service, secrets
├── backend.yaml                # Backend API deployment, service, HPA, PDB
├── frontend.yaml               # Frontend deployment, service, HPA, PDB
├── ingress.yaml                # Ingress resource for external access
├── network-policy.yaml         # Network policies for security
├── DEPLOYMENT.md               # Deployment guide
├── INGRESS-INSTALLATION.md     # Ingress Controller installation
├── AWS-EKS-LOADBALANCER.md     # AWS EKS LoadBalancer guide
└── README.md                   # Overview and summary
```

## Deployment Order

### 0. Install NGINX Ingress Controller (REQUIRED FIRST STEP!)
**⚠️ IMPORTANT: Install Ingress Controller before deploying the application!**

See detailed instructions in [INGRESS-INSTALLATION.md](./INGRESS-INSTALLATION.md)

**For AWS EKS users:** See [AWS-EKS-LOADBALANCER.md](./AWS-EKS-LOADBALANCER.md) for LoadBalancer setup instructions.

Quick install (using Helm):
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.replicaCount=2
```

**For AWS EKS with NLB:**
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
  --set controller.replicaCount=2
```

Verify installation:
```bash
kubectl get pods -n ingress-nginx
kubectl get ingressclass
kubectl get svc -n ingress-nginx  # Get LoadBalancer DNS name
```

### 1. Create Namespace and Resource Management
```bash
kubectl apply -f namespace.yaml
kubectl apply -f resource-quota.yaml
kubectl apply -f limit-range.yaml
```

### 2. Create Persistent Volumes and Claims
```bash
kubectl apply -f persistentVolume.yaml
kubectl apply -f persistentVolumeClaim.yaml
```

### 3. Update Secrets (IMPORTANT!)
Before deploying, update all secrets with production values:

```bash
# MongoDB Secret
kubectl create secret generic mongo-secret \
  --from-literal=username=admin \
  --from-literal=password=YOUR_STRONG_MONGODB_PASSWORD \
  -n wanderlust \
  --dry-run=client -o yaml | kubectl apply -f -

# Redis Secret
kubectl create secret generic redis-secret \
  --from-literal=password=YOUR_STRONG_REDIS_PASSWORD \
  -n wanderlust \
  --dry-run=client -o yaml | kubectl apply -f -

# Backend Secret
kubectl create secret generic backend-secret \
  --from-literal=JWT_SECRET=YOUR_JWT_SECRET_KEY \
  --from-literal=MONGODB_URI="mongodb://admin:YOUR_MONGODB_PASSWORD@mongo-service:27017/wanderlust?authSource=admin" \
  --from-literal=REDIS_URL="redis://:YOUR_REDIS_PASSWORD@redis-service:6379" \
  -n wanderlust \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4. Deploy Database Services
```bash
kubectl apply -f mongodb.yaml
kubectl apply -f redis.yaml
```

Wait for databases to be ready:
```bash
kubectl wait --for=condition=ready pod -l app=mongo -n wanderlust --timeout=300s
kubectl wait --for=condition=ready pod -l app=redis -n wanderlust --timeout=300s
```

### 5. Deploy Application Services
```bash
kubectl apply -f backend.yaml
kubectl apply -f frontend.yaml
```

### 6. Configure Ingress
Update `ingress.yaml` with your domain names:
- Replace `wanderlust.example.com` with your frontend domain
- Replace `api.wanderlust.example.com` with your API domain

Then apply:
```bash
kubectl apply -f ingress.yaml
```

### 7. Apply Network Policies (Optional but Recommended)
```bash
kubectl apply -f network-policy.yaml
```

## Configuration

### Ingress Configuration
1. Update domain names in `ingress.yaml`
2. For TLS/SSL:
   - Create TLS secret: `kubectl create secret tls wanderlust-tls-secret --cert=path/to/cert.crt --key=path/to/key.key -n wanderlust`
   - Uncomment TLS section in `ingress.yaml`

### Resource Limits
Adjust resource requests/limits in deployment files based on your cluster capacity:
- **Backend**: 256Mi-512Mi memory, 100m-500m CPU
- **Frontend**: 64Mi-128Mi memory, 50m-100m CPU
- **MongoDB**: 512Mi-1Gi memory, 250m-500m CPU
- **Redis**: 128Mi-256Mi memory, 100m-200m CPU

### Auto-scaling
HPA is configured for backend and frontend:
- **Min replicas**: 2
- **Max replicas**: 5
- **CPU threshold**: 70%
- **Memory threshold**: 80%

## Monitoring

### Check Pod Status
```bash
kubectl get pods -n wanderlust
kubectl get pods -n wanderlust -l app=backend
kubectl get pods -n wanderlust -l app=frontend
```

### Check Services
```bash
kubectl get svc -n wanderlust
```

### Check Ingress
```bash
kubectl get ingress -n wanderlust
```

### View Logs
```bash
# Backend logs
kubectl logs -f deployment/backend-deployment -n wanderlust

# Frontend logs
kubectl logs -f deployment/frontend-deployment -n wanderlust

# MongoDB logs
kubectl logs -f deployment/mongo-deployment -n wanderlust

# Redis logs
kubectl logs -f deployment/redis-deployment -n wanderlust
```

## Health Checks

All services have liveness and readiness probes configured:
- **Backend**: HTTP GET on `/` port 8080
- **Frontend**: HTTP GET on `/` port 80
- **MongoDB**: `mongosh` ping command
- **Redis**: `redis-cli` ping command

## Security Features

1. **Non-root containers**: All containers run as non-root users
2. **Read-only filesystems**: Where possible
3. **Dropped capabilities**: Minimal Linux capabilities
4. **Network policies**: Restrictive network access
5. **Secrets management**: Sensitive data in Kubernetes secrets
6. **Internal services**: Databases not exposed externally

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n wanderlust
kubectl logs <pod-name> -n wanderlust
```

### PVC not binding
```bash
kubectl get pv
kubectl get pvc -n wanderlust
kubectl describe pvc <pvc-name> -n wanderlust
```

### Ingress not working
```bash
# Check if Ingress Controller is installed
kubectl get pods -n ingress-nginx
kubectl get ingressclass

# Check ingress resource
kubectl describe ingress wanderlust-ingress -n wanderlust

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100

# If Ingress Controller is not installed, see INGRESS-INSTALLATION.md
```

### Database connection issues
- Verify MongoDB and Redis services are running
- Check connection strings in backend-secret
- Verify network policies allow backend to connect to databases

## Production Checklist

- [ ] NGINX Ingress Controller installed
- [ ] Namespace created
- [ ] Resource quotas and limit ranges applied
- [ ] All secrets updated with strong passwords
- [ ] Domain names configured in ingress.yaml
- [ ] TLS certificates configured (if using HTTPS)
- [ ] Resource limits adjusted for your cluster
- [ ] Persistent volumes created and bound
- [ ] Network policies reviewed and applied
- [ ] Monitoring and alerting configured
- [ ] Backup strategy implemented for databases
- [ ] Disaster recovery plan documented
- [ ] LoadBalancer DNS configured (for AWS EKS)

## GitOps Integration

These manifests are automatically updated by the GitOps pipeline:
- Backend image tag updated in `backend.yaml`
- Frontend image tag updated in `frontend.yaml`

The GitOps pipeline (GitOps/Jenkinsfile) automatically:
1. Updates image tags in manifests
2. Commits changes to Git
3. ArgoCD syncs changes to cluster

## Support

For issues or questions, check:
- Kubernetes cluster logs
- Application logs
- ArgoCD sync status (if using GitOps)
