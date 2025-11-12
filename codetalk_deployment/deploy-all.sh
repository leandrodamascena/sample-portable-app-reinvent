#!/bin/bash

# Master deployment script for Clean Architecture App
# This script can deploy to ECS, EKS, and Lambda

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi
DEPLOY_TARGET="${1:-all}"  # all, ecs, eks, lambda

echo "🚀 Clean Architecture App - Multi-Service Deployment"
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Target: ${DEPLOY_TARGET}"
echo ""

# Validate target
case $DEPLOY_TARGET in
    all|ecs|eks|lambda)
        ;;
    *)
        echo "❌ Invalid deployment target: ${DEPLOY_TARGET}"
        echo "Valid options: all, ecs, eks, lambda"
        echo ""
        echo "Usage: $0 [target]"
        echo "  $0 all     # Deploy to all services"
        echo "  $0 ecs     # Deploy to ECS only"
        echo "  $0 eks     # Deploy to EKS only"
        echo "  $0 lambda  # Deploy to Lambda only"
        exit 1
        ;;
esac

# Step 1: Build and push Docker image
echo "🔨 Step 1: Building and pushing Docker image..."
./build-and-push.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to build and push image"
    exit 1
fi

# Automatically source the IMAGE_URI from build script
CURRENT_DIR=$(basename "$PWD")
if [ "$CURRENT_DIR" == "codetalk_deployment" ]; then
    IMAGE_URI_FILE="./.image_uri"
else
    IMAGE_URI_FILE="codetalk_deployment/.image_uri"
fi

if [ -f "${IMAGE_URI_FILE}" ]; then
    source ${IMAGE_URI_FILE}
    echo "✅ Image built and pushed: ${IMAGE_URI}"
else
    echo "❌ Failed to get IMAGE_URI from build script"
    exit 1
fi
echo ""

# Deploy to selected services
if [ "$DEPLOY_TARGET" == "all" ] || [ "$DEPLOY_TARGET" == "ecs" ]; then
    echo "🚢 Step 2a: Deploying to ECS with Managed Instances..."
    echo "⏳ Note: ECS Managed Instances may take a few minutes to provision..."
    cd ecs
    ./deploy-ecs.sh
    cd ..
    echo "✅ ECS deployment completed"
    echo ""
fi

if [ "$DEPLOY_TARGET" == "all" ] || [ "$DEPLOY_TARGET" == "eks" ]; then
    echo "☸️  Step 2b: Deploying to EKS Auto Mode..."
    cd eks
    
    # Check if cluster exists, create if needed
    CLUSTER_STATUS=$(aws eks describe-cluster --name clean-architecture-eks --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null)
    if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
        echo "🆕 EKS cluster not found. Creating cluster first (this takes ~15 minutes)..."
        ./create-cluster.sh
        if [ $? -ne 0 ]; then
            echo "❌ Failed to create EKS cluster"
            cd ..
            exit 1
        fi
    fi
    
    # Deploy application
    ./deploy-eks.sh
    cd ..
    echo "✅ EKS deployment completed"
    echo ""
fi

if [ "$DEPLOY_TARGET" == "all" ] || [ "$DEPLOY_TARGET" == "lambda" ]; then
    echo "⚡ Step 2c: Deploying to Lambda..."
    echo "💡 Lambda deployment will build its own optimized image..."
    cd lambda
    ./deploy-lambda.sh
    cd ..
    echo "✅ Lambda deployment completed"
    echo ""
fi

echo "🎉 All deployments completed successfully!"
echo ""
echo "📋 Deployment Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$DEPLOY_TARGET" == "all" ] || [ "$DEPLOY_TARGET" == "ecs" ]; then
    echo "🚢 ECS Service: clean-architecture-service (Managed Instances)"
    echo "   Cluster: clean-architecture-cluster"
    echo "   Capacity Provider: clean-architecture-cluster-managed-instances"
    echo "   Check status: aws ecs describe-services --cluster clean-architecture-cluster --services clean-architecture-service --region ${AWS_REGION}"
    echo "   Check capacity provider: aws ecs describe-capacity-providers --capacity-providers clean-architecture-cluster-managed-instances --region ${AWS_REGION}"
    echo ""
fi

if [ "$DEPLOY_TARGET" == "all" ] || [ "$DEPLOY_TARGET" == "eks" ]; then
    echo "☸️  EKS Deployment: clean-architecture-app"
    echo "   Cluster: clean-architecture-eks"
    echo "   Get URL: kubectl get service clean-architecture-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
    echo ""
fi

if [ "$DEPLOY_TARGET" == "all" ] || [ "$DEPLOY_TARGET" == "lambda" ]; then
    echo "⚡ Lambda Function: clean-architecture-lambda"
    echo "   Test: aws lambda invoke --function-name clean-architecture-lambda --payload '{}' response.json --region ${AWS_REGION}"
    echo ""
fi

echo "💡 All services expose the same API endpoints:"
echo "   GET    /health         - Health check"
echo "   POST   /users          - Create user"
echo "   GET    /users          - Get all users"
echo "   GET    /users/{id}     - Get user by ID"
echo "   DELETE /users/{id}     - Delete user"
echo "   POST   /orders         - Create order"
echo "   GET    /orders         - Get all orders"
echo "   GET    /orders/{id}    - Get order by ID"
echo "   DELETE /orders/{id}    - Delete order"