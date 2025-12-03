#!/bin/bash

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.34}"

# Check if cluster name is already saved from previous run
if [ -z "$CLUSTER_NAME" ] && [ -f "../.eks_cluster_name" ]; then
    echo "🔄 Loading existing cluster name from previous run..."
    source ../.eks_cluster_name
    echo "✅ Using cluster: ${CLUSTER_NAME}"
else
    # Add random hash to avoid conflicts with existing resources
    RANDOM_HASH=$(date +%s | md5sum | head -c 8)
    CLUSTER_NAME="${CLUSTER_NAME:-clean-architecture-eks-${RANDOM_HASH}}"
fi

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi

echo "🚀 Creating EKS Auto Mode Cluster with eksctl..."
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Kubernetes Version: ${KUBERNETES_VERSION}"
echo "📍 Mode: Auto Mode (serverless compute)"
echo ""

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo "❌ eksctl is not installed. Please install it first."
    echo "💡 Install with: brew install weaveworks/tap/eksctl"
    exit 1
fi

# Check if cluster already exists
echo "📦 Checking if EKS cluster exists..."
CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null)

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo "✅ Cluster ${CLUSTER_NAME} already exists and is active"
    exit 0
elif [ "$CLUSTER_STATUS" == "CREATING" ]; then
    echo "⏳ Cluster ${CLUSTER_NAME} is already being created."
    echo "💡 Check progress with: eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}"
    exit 0
fi

# Create EKS Auto Mode cluster with eksctl
echo "🆕 Creating EKS Auto Mode cluster..."
echo "⚠️  This will take approximately 15-20 minutes. Please be patient..."
echo "💡 Auto Mode will automatically provision compute resources as needed"

eksctl create cluster \
    --name ${CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --version ${KUBERNETES_VERSION} \
    --enable-auto-mode

if [ $? -ne 0 ]; then
    echo "❌ Failed to create EKS Auto Mode cluster"
    exit 1
fi

# Save cluster name for other scripts to use
echo "export CLUSTER_NAME=${CLUSTER_NAME}" > ../.eks_cluster_name
echo "export AWS_REGION=${AWS_REGION}" >> ../.eks_cluster_name
echo "💾 Cluster name saved to ../.eks_cluster_name"

echo ""
echo "✅ EKS Auto Mode cluster created successfully!"
echo "📍 Cluster Name: ${CLUSTER_NAME}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Kubernetes Version: ${KUBERNETES_VERSION}"
echo "📍 Mode: Auto Mode (serverless compute)"
echo ""
echo "🔧 Cluster is ready! You can now:"
echo "1. Check cluster info: eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}"
echo "2. Deploy applications using: ./deploy-eks.sh"
echo "3. Auto Mode will provision nodes automatically when pods are scheduled"
echo ""
echo "💡 Useful commands:"
echo "   kubectl get nodes -o wide (nodes will appear when pods are scheduled)"
echo "   kubectl get pods -A"
echo "   aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}"