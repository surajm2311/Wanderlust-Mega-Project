# NGINX Ingress Controller Installation Guide

## Overview
The Wanderlust application uses NGINX Ingress Controller to route external traffic to frontend and backend services. This guide covers installation and configuration.

## Prerequisites
- Kubernetes cluster (1.24+)
- kubectl configured and connected to your cluster
- Admin/Cluster Admin permissions

## Installation Methods

### Method 1: Using Helm (Recommended)

#### 1. Add NGINX Ingress Helm Repository
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

#### 2. Install NGINX Ingress Controller
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux
```

#### 3. Verify Installation
```bash
# Check pods
kubectl get pods -n ingress-nginx

# Check service (get EXTERNAL-IP)
kubectl get svc -n ingress-nginx

# Check ingress class
kubectl get ingressclass
```

### Method 2: Using kubectl (Manifests)

#### 1. Install NGINX Ingress Controller
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

#### 2. Wait for Installation
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
```

#### 3. Verify Installation
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### Method 3: For AWS EKS (Using LoadBalancer)

#### Option A: NGINX Ingress with AWS NLB (Recommended for NGINX)

##### 1. Install NGINX Ingress Controller with AWS NLB
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"="ip" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true" \
  --set controller.replicaCount=2
```

##### 2. Wait for NLB Creation
```bash
# Wait for service to get external hostname
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Get NLB DNS name
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

##### 3. Configure Security Groups
Ensure your EKS node security groups allow:
- **Inbound**: Port 80 (HTTP) and 443 (HTTPS) from 0.0.0.0/0
- **Outbound**: All traffic

```bash
# Get security group ID from NLB
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `ingress`)].{Name:LoadBalancerName,SG:SecurityGroups}' \
  --output table
```

#### Option B: AWS Load Balancer Controller (Native AWS Solution)

##### Prerequisites
1. **AWS CLI configured** with appropriate permissions
2. **eksctl** or **kubectl** configured
3. **IAM permissions** for Load Balancer Controller

##### 1. Create IAM Policy for AWS Load Balancer Controller

```bash
# Download IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

##### 2. Create IAM Role and Service Account

**Using eksctl (Recommended):**
```bash
# Get your cluster name and region
export CLUSTER_NAME=your-eks-cluster-name
export AWS_REGION=us-west-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
```

**Using kubectl (Manual):**
```bash
# Create service account
kubectl create serviceaccount aws-load-balancer-controller -n kube-system

# Annotate service account with IAM role ARN
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-load-balancer-controller-role
```

##### 3. Install AWS Load Balancer Controller using Helm

```bash
# Add EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
```

##### 4. Verify Installation
```bash
# Check pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

##### 5. Create IngressClass for AWS Load Balancer Controller
```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
spec:
  controller: ingress.k8s.aws/alb
EOF
```

##### 6. Update Ingress to Use AWS ALB (Alternative Configuration)

If using AWS Load Balancer Controller, update `ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wanderlust-ingress
  namespace: wanderlust
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
spec:
  ingressClassName: alb
  # ... rest of configuration
```

## AWS EKS LoadBalancer Configuration

### NLB (Network Load Balancer) Configuration

#### Advantages:
- Lower latency
- Preserves source IP
- TCP/UDP support
- Better for high throughput

#### Service Annotations for NLB:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "TCP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "80"
spec:
  type: LoadBalancer
  # ...
```

### ALB (Application Load Balancer) Configuration

#### Advantages:
- Path-based routing
- Host-based routing
- SSL termination
- WAF integration
- Better for HTTP/HTTPS

#### Ingress Annotations for ALB:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-port: traffic-port
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
```

### DNS Configuration with Route53

#### 1. Get Load Balancer DNS Name
```bash
# For NLB (NGINX Ingress)
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# For ALB (AWS Load Balancer Controller)
kubectl get ingress wanderlust-ingress -n wanderlust -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

#### 2. Create Route53 Records
```bash
# Get hosted zone ID
export HOSTED_ZONE_ID=your-route53-hosted-zone-id
export LB_DNS_NAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create A record (Alias) for frontend
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "wanderlust.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z1D633PJN98FT9",
          "DNSName": "'$LB_DNS_NAME'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'

# Create A record for API subdomain
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.wanderlust.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z1D633PJN98FT9",
          "DNSName": "'$LB_DNS_NAME'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

**Note:** HostedZoneId for NLB: `Z1D633PJN98FT9` (us-east-1), varies by region

### Security Groups Configuration

#### 1. Get EKS Cluster Security Groups
```bash
export CLUSTER_NAME=your-eks-cluster-name
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text
```

#### 2. Configure Security Group Rules
```bash
# Get security group ID
export CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Allow HTTP from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $CLUSTER_SG \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Allow HTTPS from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $CLUSTER_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

### SSL/TLS Certificate Setup (ACM)

#### 1. Request Certificate in ACM
```bash
# Request certificate
aws acm request-certificate \
  --domain-name wanderlust.example.com \
  --subject-alternative-names api.wanderlust.example.com \
  --validation-method DNS \
  --region us-west-1

# Get certificate ARN
export CERT_ARN=$(aws acm list-certificates --region us-west-1 --query 'CertificateSummaryList[?DomainName==`wanderlust.example.com`].CertificateArn' --output text)
```

#### 2. Validate Certificate
```bash
# Get DNS validation records
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-west-1 \
  --query 'Certificate.DomainValidationOptions'

# Add CNAME records to Route53 for validation
```

#### 3. Update Ingress with Certificate ARN
```yaml
# For ALB
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id

# For NLB (requires cert-manager or manual cert import)
# Use cert-manager with AWS ACM issuer
```

## Post-Installation Configuration

### 1. Get Ingress Controller External IP/URL
```bash
# For LoadBalancer
kubectl get svc ingress-nginx-controller -n ingress-nginx

# For NodePort (if using)
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'
```

### 2. Update DNS Records

#### For NLB (NGINX Ingress):
```bash
# Get NLB DNS name
export LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update Route53 (see DNS Configuration section above)
# Or manually update DNS:
# wanderlust.example.com → CNAME → $LB_DNS
# api.wanderlust.example.com → CNAME → $LB_DNS
```

#### For ALB (AWS Load Balancer Controller):
```bash
# Get ALB DNS name
export LB_DNS=$(kubectl get ingress wanderlust-ingress -n wanderlust -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update Route53 records
```

### 3. Verify Ingress Class
```bash
kubectl get ingressclass
```

You should see `nginx` as the ingress class name.

### 4. Test Ingress Controller
```bash
# Create a test ingress
kubectl create ingress test-ingress \
  --class=nginx \
  --rule="test.example.com/*=test-service:80" \
  -n default

# Check ingress
kubectl get ingress -A
```

## Configuration for Wanderlust

### 1. Ensure Ingress Class Name Matches
The `ingress.yaml` file uses `ingressClassName: nginx`. Verify this matches:
```bash
kubectl get ingressclass nginx
```

### 2. Apply Wanderlust Ingress
After installing the Ingress Controller, apply your ingress:
```bash
kubectl apply -f kubernetes/ingress.yaml
```

### 3. Verify Ingress
```bash
kubectl get ingress -n wanderlust
kubectl describe ingress wanderlust-ingress -n wanderlust
```

## Troubleshooting

### Ingress Controller Not Starting
```bash
# Check pods
kubectl get pods -n ingress-nginx

# Check logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Check events
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'
```

### Ingress Not Routing Traffic
```bash
# Check ingress status
kubectl describe ingress wanderlust-ingress -n wanderlust

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100

# Verify backend services
kubectl get svc -n wanderlust
```

### No External IP Assigned (LoadBalancer)

#### For AWS EKS NLB:
```bash
# Check service
kubectl describe svc ingress-nginx-controller -n ingress-nginx

# Check if NLB is created in AWS
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `ingress`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
  --output table

# Check NLB target health
export NLB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `ingress`)].LoadBalancerArn' \
  --output text)

aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups \
  --load-balancer-arn $NLB_ARN \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)
```

#### For AWS EKS ALB:
```bash
# Check ingress status
kubectl describe ingress wanderlust-ingress -n wanderlust

# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check if ALB is created
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-wanderlust`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
  --output table
```

#### Common AWS EKS Issues:

**Issue: LoadBalancer stuck in "Pending"**
```bash
# Check IAM permissions
kubectl describe sa aws-load-balancer-controller -n kube-system

# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify VPC and subnet tags (for ALB)
# Subnets must be tagged:
# kubernetes.io/role/internal-elb=1 (for internal)
# kubernetes.io/role/elb=1 (for internet-facing)
aws ec2 describe-subnets --filters "Name=tag:Name,Values=*eks*" --query 'Subnets[*].{ID:SubnetId,Tags:Tags[?Key==`kubernetes.io/role/elb`]}'
```

**Issue: Security Group not allowing traffic**
```bash
# Check security group rules
export CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
aws ec2 describe-security-group-rules --group-ids $CLUSTER_SG
```

### Ingress Class Not Found
```bash
# List ingress classes
kubectl get ingressclass

# If nginx class doesn't exist, create it:
kubectl create ingressclass nginx \
  --controller=k8s.io/ingress-nginx
```

## Uninstallation

### Using Helm
```bash
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

### Using kubectl
```bash
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

## Production Recommendations

1. **High Availability**: Use at least 2 replicas
2. **Resource Limits**: Set appropriate CPU/memory limits
3. **Monitoring**: Enable Prometheus metrics
4. **TLS**: Configure SSL/TLS certificates (Let's Encrypt with cert-manager)
5. **Rate Limiting**: Configure rate limiting (already in ingress.yaml)
6. **WAF**: Consider Web Application Firewall for additional security

## Additional Resources

- [NGINX Ingress Controller Docs](https://kubernetes.github.io/ingress-nginx/)
- [Helm Chart Values](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx)
- [AWS EKS Ingress Setup](https://docs.aws.amazon.com/eks/latest/userguide/load-balancing.html)
