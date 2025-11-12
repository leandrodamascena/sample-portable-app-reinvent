#!/bin/bash

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi
IMAGE_NAME="clean-architecture-app"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Derived variables
ECR_REPOSITORY_URI="${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

echo "🚀 Building and pushing Docker image to ECR..."
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Repository: ${ECR_REPOSITORY_URI}"
echo "📍 Tag: ${IMAGE_TAG}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Create ECR repository if it doesn't exist
echo "📦 Creating ECR repository if it doesn't exist..."
aws ecr describe-repositories --repository-names ${IMAGE_NAME} --region ${AWS_REGION} &> /dev/null || \
aws ecr create-repository --repository-name ${IMAGE_NAME} --region ${AWS_REGION}

if [ $? -ne 0 ]; then
    echo "❌ Failed to create ECR repository"
    exit 1
fi

# Get ECR login token
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com

if [ $? -ne 0 ]; then
    echo "❌ Failed to login to ECR"
    exit 1
fi

# Determine correct paths based on current directory
CURRENT_DIR=$(basename "$PWD")
if [ "$CURRENT_DIR" == "codetalk_deployment" ]; then
    # Running from inside codetalk_deployment directory
    DOCKERFILE_PATH="./Dockerfile"
    BUILD_CONTEXT=".."
    IMAGE_URI_FILE="./.image_uri"
else
    # Running from workspace root
    DOCKERFILE_PATH="codetalk_deployment/Dockerfile"
    BUILD_CONTEXT="."
    IMAGE_URI_FILE="codetalk_deployment/.image_uri"
fi

# Build multi-architecture Docker image
echo "🔨 Building multi-architecture Docker image..."
echo "📍 Build context: ${BUILD_CONTEXT}"
echo "📍 Dockerfile: ${DOCKERFILE_PATH}"
echo "📍 Detected architecture: $(uname -m)"
echo "📍 Target platforms: linux/amd64,linux/arm64"

# Ensure Docker buildx is available for multi-arch builds
if ! docker buildx version &>/dev/null; then
    echo "❌ Docker buildx is required for multi-architecture builds"
    echo "💡 Please enable Docker buildx or update Docker Desktop"
    exit 1
fi

# Create or use existing buildx builder
echo "🔧 Setting up multi-architecture builder..."
docker buildx create --name multi-arch-builder --use 2>/dev/null || docker buildx use multi-arch-builder 2>/dev/null || true

# Build and push multi-architecture image directly to ECR
echo "🏗️  Building and pushing multi-architecture image..."
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --push \
    -t ${ECR_REPOSITORY_URI}:${IMAGE_TAG} \
    -f ${DOCKERFILE_PATH} \
    ${BUILD_CONTEXT}

if [ $? -ne 0 ]; then
    echo "❌ Failed to build and push multi-architecture image"
    exit 1
fi

echo ""
echo "✅ Successfully built and pushed multi-architecture image!"
echo "📍 Image URI: ${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
echo "📍 Architectures: linux/amd64, linux/arm64"

# Automatically export IMAGE_URI and save to file for other scripts
export IMAGE_URI="${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
echo "export IMAGE_URI=\"${ECR_REPOSITORY_URI}:${IMAGE_TAG}\"" > ${IMAGE_URI_FILE}

echo ""
echo "✅ IMAGE_URI automatically set and saved!"
echo "💡 Multi-architecture image works on both Intel/AMD and ARM-based AWS services"