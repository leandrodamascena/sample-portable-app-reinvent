#!/bin/bash

# Master cleanup script for Clean Architecture App
# This script can clean up ECS, EKS, and Lambda deployments

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi
CLEANUP_TARGET="${1:-all}"  # all, ecs, eks, lambda

echo "🧹 Clean Architecture App - Multi-Service Cleanup"
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Target: ${CLEANUP_TARGET}"
echo ""

# Validate target
case $CLEANUP_TARGET in
    all|ecs|eks|lambda)
        ;;
    *)
        echo "❌ Invalid cleanup target: ${CLEANUP_TARGET}"
        echo "Valid options: all, ecs, eks, lambda"
        echo ""
        echo "Usage: $0 [target]"
        echo "  $0 all     # Clean up all services"
        echo "  $0 ecs     # Clean up ECS only"
        echo "  $0 eks     # Clean up EKS only"
        echo "  $0 lambda  # Clean up Lambda only"
        exit 1
        ;;
esac

# Confirmation prompt
echo "⚠️  WARNING: This will delete the following resources:"
if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "ecs" ]; then
    echo "   🚢 ECS: Services, tasks, capacity providers, clusters, IAM roles"
fi
if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "eks" ]; then
    echo "   ☸️  EKS: Applications, clusters, node groups, IAM roles"
fi
if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "lambda" ]; then
    echo "   ⚡ Lambda: Functions, function URLs, IAM roles"
fi
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "🧹 Starting cleanup process..."

# Clean up ECS
if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "ecs" ]; then
    echo "🚢 Cleaning up ECS resources..."
    cd ecs
    
    # Try force cleanup first (handles stuck capacity providers)
    if [ -f "./force-cleanup-ecs.sh" ]; then
        echo "Using force cleanup for better resource removal..."
        ./force-cleanup-ecs.sh
        
        # Wait a bit and run again if cluster still exists
        sleep 10
        CLUSTER_STATUS=$(aws ecs describe-clusters --clusters clean-architecture-cluster* --region ${AWS_REGION} --query 'clusters[0].status' --output text 2>/dev/null)
        if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
            echo "⏳ Cluster still active, running force cleanup again..."
            ./force-cleanup-ecs.sh
        fi
    else
        # Fallback to regular cleanup
        ./cleanup-ecs.sh
    fi
    
    cd ..
    echo "✅ ECS cleanup completed"
    echo ""
fi

# Clean up EKS
if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "eks" ]; then
    echo "☸️  Cleaning up EKS resources..."
    cd eks
    ./cleanup-eks.sh
    cd ..
    echo "✅ EKS cleanup completed"
    echo ""
fi

# Clean up Lambda
if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "lambda" ]; then
    echo "⚡ Cleaning up Lambda resources..."
    cd lambda
    ./cleanup-lambda.sh
    cd ..
    echo "✅ Lambda cleanup completed"
    echo ""
fi

# Clean up ECR repositories (only if cleaning all)
if [ "$CLEANUP_TARGET" == "all" ]; then
    echo "📦 Cleaning up ECR repositories..."
    
    # Clean up main repository
    IMAGE_NAME="clean-architecture-app"
    echo "🗑️  Cleaning up main ECR repository: ${IMAGE_NAME}"
    aws ecr list-images --repository-name ${IMAGE_NAME} --region ${AWS_REGION} --query 'imageIds[*]' --output json > /tmp/images.json 2>/dev/null || echo "[]" > /tmp/images.json
    
    if [ "$(cat /tmp/images.json)" != "[]" ]; then
        aws ecr batch-delete-image --repository-name ${IMAGE_NAME} --image-ids file:///tmp/images.json --region ${AWS_REGION} 2>/dev/null || true
    fi
    aws ecr delete-repository --repository-name ${IMAGE_NAME} --region ${AWS_REGION} 2>/dev/null || echo "Main repository may not exist"
    
    # Clean up Lambda repository
    LAMBDA_IMAGE_NAME="clean-architecture-app-lambda"
    echo "🗑️  Cleaning up Lambda ECR repository: ${LAMBDA_IMAGE_NAME}"
    aws ecr list-images --repository-name ${LAMBDA_IMAGE_NAME} --region ${AWS_REGION} --query 'imageIds[*]' --output json > /tmp/lambda-images.json 2>/dev/null || echo "[]" > /tmp/lambda-images.json
    
    if [ "$(cat /tmp/lambda-images.json)" != "[]" ]; then
        aws ecr batch-delete-image --repository-name ${LAMBDA_IMAGE_NAME} --image-ids file:///tmp/lambda-images.json --region ${AWS_REGION} 2>/dev/null || true
    fi
    aws ecr delete-repository --repository-name ${LAMBDA_IMAGE_NAME} --region ${AWS_REGION} 2>/dev/null || echo "Lambda repository may not exist"
    
    echo "✅ ECR cleanup completed"
    echo ""
fi

# Clean up temporary files
echo "🧹 Cleaning up temporary files..."
rm -f .image_uri
rm -f /tmp/task-definition.json
rm -f /tmp/managed-instances-task.json
rm -f /tmp/managed-instances-cp.json
rm -f /tmp/cluster-cp-strategy.json
rm -f /tmp/deployment.yaml
rm -f /tmp/cluster-trust-policy.json
rm -f /tmp/node-trust-policy.json
rm -f /tmp/trust-policy.json
rm -f /tmp/images.json
rm -f /tmp/lambda-images.json
rm -f /tmp/response.json
rm -f response.json

echo ""
echo "🎉 Cleanup completed successfully!"
echo ""
echo "📋 Cleanup Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "ecs" ]; then
    echo "🚢 ECS: All services, clusters, and capacity providers removed"
fi

if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "eks" ]; then
    echo "☸️  EKS: All applications and clusters removed"
fi

if [ "$CLEANUP_TARGET" == "all" ] || [ "$CLEANUP_TARGET" == "lambda" ]; then
    echo "⚡ Lambda: All functions and URLs removed"
fi

if [ "$CLEANUP_TARGET" == "all" ]; then
    echo "📦 ECR: Repository and images removed"
fi

echo ""
echo "💡 Your AWS account is now clean and ready for new deployments!"