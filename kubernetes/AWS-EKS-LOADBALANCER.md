# AWS EKS LoadBalancer Quick Reference

## Quick Setup Commands

### Prerequisites Check
```bash
# Set variables
export CLUSTER_NAME=your-eks-cluster-name
export AWS_REGION=us-west-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Verify cluster access
kubectl cluster-info
aws eks describe-cluster --name $CLUSTER_NAME
```

## Option 1: NGINX Ingress with NLB (Simpler, Recommended)

### Installation
```bash
# Install NGINX Ingress with NLB
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"="ip" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true" \
  --set controller.replicaCount=2

# Wait for NLB
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Get NLB DNS
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

### Configure DNS
```bash
# Get NLB DNS name
export LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update Route53 or DNS provider
# wanderlust.example.com → CNAME → $LB_DNS
# api.wanderlust.example.com → CNAME → $LB_DNS
```

## Option 2: AWS Load Balancer Controller with ALB (Native AWS)

### Step 1: Create IAM Policy
```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

### Step 2: Create IAM Service Account
```bash
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
```

### Step 3: Install AWS Load Balancer Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
```

### Step 4: Create IngressClass
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

### Step 5: Tag Subnets (Required for ALB)
```bash
# Get subnet IDs
export PUBLIC_SUBNETS=$(aws eks describe-cluster --name $CLUSTER_NAME \
  --query "cluster.resourcesVpcConfig.subnetIds" --output text)

# Tag subnets for internet-facing ALB
for subnet in $PUBLIC_SUBNETS; do
  aws ec2 create-tags \
    --resources $subnet \
    --tags Key=kubernetes.io/role/elb,Value=1
done
```

## Verification Commands

### Check LoadBalancer Status
```bash
# NLB (NGINX Ingress)
kubectl get svc -n ingress-nginx
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `ingress`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'

# ALB (AWS Load Balancer Controller)
kubectl get ingress -n wanderlust
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-wanderlust`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'
```

### Check Security Groups
```bash
export CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
aws ec2 describe-security-group-rules --group-ids $CLUSTER_SG --query 'SecurityGroupRules[?IsEgress==`false`]'
```

## Troubleshooting Commands

### LoadBalancer Stuck in Pending
```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check IAM role
kubectl describe sa aws-load-balancer-controller -n kube-system

# Check events
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'
kubectl get events -n wanderlust --sort-by='.lastTimestamp'
```

### DNS Not Resolving
```bash
# Test DNS resolution
nslookup wanderlust.example.com
dig wanderlust.example.com

# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id YOUR_HOSTED_ZONE_ID
```

## Cost Considerations

- **NLB**: ~$0.0225/hour + data transfer
- **ALB**: ~$0.0225/hour + LCU (varies by traffic)
- **NGINX Ingress**: Free (runs on cluster nodes)

## Recommendation

For Wanderlust project:
- **Use NGINX Ingress with NLB** (Option 1) - simpler, cost-effective, works with existing ingress.yaml
- **Use AWS Load Balancer Controller** (Option 2) - if you need advanced AWS features (WAF, advanced routing)
