#!/bin/bash

# EKS cleanup script for Clean Architecture App

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"
NAMESPACE="${NAMESPACE:-default}"
APP_NAME="clean-architecture-app"

# Load cluster name from create-cluster.sh if not set
if [ -z "$CLUSTER_NAME" ]; then
    if [ -f "../.eks_cluster_name" ]; then
        echo "🔄 Loading cluster name from create-cluster.sh..."
        source ../.eks_cluster_name
        echo "✅ Using cluster: ${CLUSTER_NAME}"
    else
        echo "⚠️  Cluster name not found in .eks_cluster_name file."
        echo "💡 If you know the cluster name, set it with: export CLUSTER_NAME=your-cluster-name"
        # Use default without hash for cleanup attempts
        CLUSTER_NAME="${CLUSTER_NAME:-clean-architecture-eks}"
    fi
fi

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi

echo "🧹 Cleaning up EKS resources..."
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Namespace: ${NAMESPACE}"
echo "📍 Application: ${APP_NAME}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "⚠️  kubectl not found. Will skip application cleanup and proceed with cluster deletion."
    SKIP_APP_CLEANUP=true
else
    SKIP_APP_CLEANUP=false
fi

# Step 1: Delete Kubernetes application resources
if [ "$SKIP_APP_CLEANUP" == "false" ]; then
    echo "🚀 Step 1: Deleting Kubernetes application resources..."
    
    # Update kubeconfig if cluster exists
    CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null)
    
    if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
        echo "🔧 Updating kubeconfig..."
        aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null 2>&1
        
        # Check if we can connect to the cluster
        kubectl cluster-info &>/dev/null
        if [ $? -eq 0 ]; then
            echo "🗑️  Deleting application deployment..."
            kubectl delete deployment ${APP_NAME} -n ${NAMESPACE} 2>/dev/null && echo "✅ Deployment deleted" || echo "ℹ️  Deployment not found"
            
            echo "🗑️  Deleting application service..."
            kubectl delete service ${APP_NAME}-service -n ${NAMESPACE} 2>/dev/null && echo "✅ Service deleted" || echo "ℹ️  Service not found"
            
            # Wait for LoadBalancer to be cleaned up
            echo "⏳ Waiting for LoadBalancer cleanup..."
            sleep 30
            
            # Delete namespace if it's not default
            if [ "$NAMESPACE" != "default" ]; then
                echo "🗑️  Deleting namespace ${NAMESPACE}..."
                kubectl delete namespace ${NAMESPACE} 2>/dev/null && echo "✅ Namespace deleted" || echo "ℹ️  Namespace not found"
            fi
        else
            echo "⚠️  Cannot connect to cluster. Proceeding with cluster deletion."
        fi
    else
        echo "ℹ️  Cluster not active or not found. Skipping application cleanup."
    fi
else
    echo "ℹ️  Step 1: Skipping application cleanup (kubectl not available)"
fi

# Step 2: Delete EKS Auto Mode cluster
echo "📦 Step 2: Deleting EKS Auto Mode cluster..."
CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null)

if [ "$CLUSTER_STATUS" == "ACTIVE" ] || [ "$CLUSTER_STATUS" == "FAILED" ]; then
    echo "🗑️  Deleting EKS Auto Mode cluster ${CLUSTER_NAME}..."
    echo "⏳ This may take 10-15 minutes..."
    echo "💡 Auto Mode will automatically clean up all compute resources"
    
    # Use eksctl to delete the cluster (handles Auto Mode cleanup better)
    if command -v eksctl &> /dev/null; then
        eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}
        if [ $? -eq 0 ]; then
            echo "✅ Cluster deletion completed"
        else
            echo "❌ Failed to delete cluster with eksctl, trying AWS CLI..."
            aws eks delete-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null
            if [ $? -eq 0 ]; then
                echo "✅ Cluster deletion initiated with AWS CLI"
            else
                echo "❌ Failed to initiate cluster deletion"
            fi
        fi
    else
        aws eks delete-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null
        if [ $? -eq 0 ]; then
            echo "✅ Cluster deletion initiated"
            echo "💡 You can check progress with: aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}"
        else
            echo "❌ Failed to initiate cluster deletion"
        fi
    fi
elif [ "$CLUSTER_STATUS" == "DELETING" ]; then
    echo "ℹ️  Cluster is already being deleted"
else
    echo "ℹ️  Cluster ${CLUSTER_NAME} not found or already deleted"
fi

# Step 3: Clean up IAM roles (Auto Mode creates fewer roles)
echo ""
echo "🔐 Step 3: IAM roles cleanup..."
echo "💡 Auto Mode clusters use managed IAM roles, but some custom roles may exist"

# Check if any custom roles exist
CUSTOM_ROLES_EXIST=false
CLUSTER_ROLE_NAME="eksClusterRole-${CLUSTER_NAME}"
NODE_ROLE_NAME="eksNodeRole-${CLUSTER_NAME}"

aws iam get-role --role-name ${CLUSTER_ROLE_NAME} >/dev/null 2>&1 && CUSTOM_ROLES_EXIST=true
aws iam get-role --role-name ${NODE_ROLE_NAME} >/dev/null 2>&1 && CUSTOM_ROLES_EXIST=true

if [ "$CUSTOM_ROLES_EXIST" == "true" ]; then
    echo "The following custom IAM roles were found and can be deleted:"
    aws iam get-role --role-name ${CLUSTER_ROLE_NAME} >/dev/null 2>&1 && echo "   - ${CLUSTER_ROLE_NAME}"
    aws iam get-role --role-name ${NODE_ROLE_NAME} >/dev/null 2>&1 && echo "   - ${NODE_ROLE_NAME}"
    echo ""
    read -p "Do you want to delete these IAM roles? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Deleting custom IAM roles..."
        
        # Delete cluster role if it exists
        if aws iam get-role --role-name ${CLUSTER_ROLE_NAME} >/dev/null 2>&1; then
            echo "🗑️  Deleting cluster role ${CLUSTER_ROLE_NAME}..."
            aws iam detach-role-policy --role-name ${CLUSTER_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>/dev/null || true
            aws iam delete-role --role-name ${CLUSTER_ROLE_NAME} 2>/dev/null && echo "✅ Cluster role deleted" || echo "ℹ️  Failed to delete cluster role"
        fi
        
        # Delete node role if it exists
        if aws iam get-role --role-name ${NODE_ROLE_NAME} >/dev/null 2>&1; then
            echo "🗑️  Deleting node role ${NODE_ROLE_NAME}..."
            aws iam detach-role-policy --role-name ${NODE_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy 2>/dev/null || true
            aws iam detach-role-policy --role-name ${NODE_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly 2>/dev/null || true
            aws iam delete-role --role-name ${NODE_ROLE_NAME} 2>/dev/null && echo "✅ Node role deleted" || echo "ℹ️  Failed to delete node role"
        fi
        
        echo "✅ Custom IAM roles cleaned up"
    else
        echo "ℹ️  Custom IAM roles preserved"
    fi
else
    echo "ℹ️  No custom IAM roles found (Auto Mode uses managed roles)"
fi

# Step 4: Clean up kubeconfig entry
echo ""
echo "🔧 Step 4: Cleaning up kubeconfig..."
read -p "Do you want to remove the cluster from your kubeconfig? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v kubectl &> /dev/null; then
        kubectl config delete-context arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_NUMBER}:cluster/${CLUSTER_NAME} 2>/dev/null || true
        kubectl config delete-cluster arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_NUMBER}:cluster/${CLUSTER_NAME} 2>/dev/null || true
        echo "✅ Kubeconfig cleaned up"
    else
        echo "ℹ️  kubectl not available, skipping kubeconfig cleanup"
    fi
else
    echo "ℹ️  Kubeconfig preserved"
fi

echo ""
echo "✅ EKS cleanup completed!"
echo "📍 All EKS resources for ${CLUSTER_NAME} have been removed or are being removed"
echo ""
echo "💡 Note: Auto Mode will automatically clean up all associated node groups and resources"