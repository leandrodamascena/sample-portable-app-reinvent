#!/bin/bash

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-clean-architecture-eks}"
IMAGE_URI="${IMAGE_URI}"
NAMESPACE="${NAMESPACE:-default}"
APP_NAME="clean-architecture-app"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi

echo "🚀 Deploying application to EKS Auto Mode..."
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Image: ${IMAGE_URI}"
echo "📍 Namespace: ${NAMESPACE}"
echo ""

# Check if IMAGE_URI is provided, if not try to source it automatically
if [ -z "$IMAGE_URI" ]; then
    if [ -f "../.image_uri" ]; then
        echo "🔄 IMAGE_URI not set, loading from build script..."
        source ../.image_uri
        echo "✅ Loaded IMAGE_URI: ${IMAGE_URI}"
    else
        echo "❌ IMAGE_URI is required. Either:"
        echo "   1. Run the build script first: ../build-and-push.sh"
        echo "   2. Or set manually: export IMAGE_URI=${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/clean-architecture-app:latest"
        exit 1
    fi
fi

# Check if required tools are installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first."
    exit 1
fi

# Step 1: Check if EKS cluster exists and is active
echo "📦 Step 1: Checking EKS cluster status..."
CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null)

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo "❌ EKS cluster '${CLUSTER_NAME}' is not active (status: ${CLUSTER_STATUS})"
    echo "💡 Please create the cluster first:"
    echo "   ./create-cluster.sh"
    exit 1
fi

echo "✅ Cluster ${CLUSTER_NAME} is active"

# Step 2: Update kubeconfig
echo "🔧 Step 2: Updating kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}

if [ $? -ne 0 ]; then
    echo "❌ Failed to update kubeconfig"
    exit 1
fi

echo "✅ Kubeconfig updated"

# Step 3: Verify cluster connectivity
echo "🔍 Step 3: Verifying cluster connectivity..."
kubectl cluster-info &>/dev/null
if [ $? -ne 0 ]; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Connected to cluster"

# Note about Auto Mode node provisioning
echo "🤖 EKS Auto Mode will create nodes automatically when pods are scheduled"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -gt 0 ]; then
    echo "✅ Found ${NODE_COUNT} existing node(s)"
    kubectl get nodes
else
    echo "📋 No nodes currently running (this is normal for Auto Mode)"
    echo "   Nodes will be created automatically when the application is deployed"
fi

# Step 4: Create namespace if it doesn't exist
echo "📁 Step 4: Creating namespace if needed..."
kubectl create namespace ${NAMESPACE} 2>/dev/null || echo "Namespace ${NAMESPACE} already exists"

# Step 5: Create Kubernetes manifests
echo "📝 Step 5: Creating Kubernetes manifests..."

cat > /tmp/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: app
        image: ${IMAGE_URI}
        ports:
        - containerPort: 9000
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-service
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  selector:
    app: ${APP_NAME}
  ports:
  - port: 80
    targetPort: 9000
    protocol: TCP
  type: LoadBalancer
EOF

# Step 6: Deploy application
echo "🚀 Step 6: Deploying application to Kubernetes..."
echo "💡 Auto Mode will provision nodes automatically for pending pods..."
kubectl apply -f /tmp/deployment.yaml

if [ $? -ne 0 ]; then
    echo "❌ Failed to deploy to Kubernetes"
    exit 1
fi

echo "✅ Application manifests applied"

# Step 7: Wait for deployment to be ready (Auto Mode will create nodes as needed)
echo "⏳ Step 7: Waiting for deployment to be ready (Auto Mode provisioning nodes)..."
# Show pod status during Auto Mode provisioning
echo "📋 Checking pod status (Auto Mode will provision nodes for pending pods):"
kubectl get pods -n ${NAMESPACE} 2>/dev/null || echo "Pods are being created..."

kubectl wait --for=condition=available --timeout=600s deployment/${APP_NAME} -n ${NAMESPACE}

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed to become ready within 10 minutes"
    echo "💡 Auto Mode node provisioning may take longer. Check status with:"
    echo "   kubectl get pods -n ${NAMESPACE}"
    echo "   kubectl get nodes"
    echo "   kubectl describe deployment ${APP_NAME} -n ${NAMESPACE}"
    exit 1
fi

echo "✅ Deployment is ready"

# Step 8: Get service information
echo "🔍 Step 8: Getting service information..."
kubectl get service ${APP_NAME}-service -n ${NAMESPACE}

# Wait for LoadBalancer to get external IP
echo "⏳ Waiting for LoadBalancer to get external IP..."
for i in {1..12}; do
    EXTERNAL_IP=$(kubectl get service ${APP_NAME}-service -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ ! -z "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
        break
    fi
    echo "   Waiting for external IP... (${i}/12)"
    sleep 10
done

echo ""
echo "✅ EKS deployment completed!"
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Namespace: ${NAMESPACE}"
echo "📍 Application: ${APP_NAME}"
echo "📍 Replicas: 2"

if [ ! -z "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
    echo "📍 LoadBalancer URL: http://${EXTERNAL_IP}"
    echo ""
    echo "🌐 Test your application:"
    echo "   curl http://${EXTERNAL_IP}/health"
else
    echo "⚠️  LoadBalancer external IP not yet available"
    echo "💡 Get it later with:"
    echo "   kubectl get service ${APP_NAME}-service -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
fi

echo ""
echo "💡 Useful commands:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo "   kubectl get services -n ${NAMESPACE}"
echo "   kubectl logs -l app=${APP_NAME} -n ${NAMESPACE}"
echo "   kubectl describe deployment ${APP_NAME} -n ${NAMESPACE}"