#!/bin/bash

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi
FUNCTION_NAME="${FUNCTION_NAME:-clean-architecture-lambda}"
IMAGE_URI="${IMAGE_URI}"
ROLE_NAME="${ROLE_NAME:-lambda-execution-role}"

echo "🚀 Deploying to AWS Lambda..."
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Function: ${FUNCTION_NAME}"
echo "📍 Image: ${IMAGE_URI}"
echo ""

# Lambda requires a specific image - build Lambda-optimized image
echo "🔨 Building Lambda-optimized Docker image..."

# Determine correct paths based on current directory
CURRENT_DIR=$(basename "$PWD")
if [ "$CURRENT_DIR" == "lambda" ]; then
    # Running from inside lambda directory
    DOCKERFILE_PATH="./Dockerfile.lambda"
    BUILD_CONTEXT="../.."
elif [ "$CURRENT_DIR" == "codetalk_deployment" ]; then
    # Running from codetalk_deployment directory
    DOCKERFILE_PATH="lambda/Dockerfile.lambda"
    BUILD_CONTEXT=".."
else
    # Running from workspace root
    DOCKERFILE_PATH="codetalk_deployment/lambda/Dockerfile.lambda"
    BUILD_CONTEXT="."
fi

# Build Lambda-specific image
LAMBDA_IMAGE_NAME="clean-architecture-app-lambda"
LAMBDA_IMAGE_TAG="latest"
LAMBDA_ECR_URI="${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/${LAMBDA_IMAGE_NAME}"

echo "📍 Build context: ${BUILD_CONTEXT}"
echo "📍 Dockerfile: ${DOCKERFILE_PATH}"
echo "📍 Lambda image: ${LAMBDA_ECR_URI}:${LAMBDA_IMAGE_TAG}"

# Create ECR repository for Lambda image if it doesn't exist
echo "📦 Creating Lambda ECR repository if it doesn't exist..."
aws ecr describe-repositories --repository-names ${LAMBDA_IMAGE_NAME} --region ${AWS_REGION} &> /dev/null || \
aws ecr create-repository --repository-name ${LAMBDA_IMAGE_NAME} --region ${AWS_REGION}

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Force x86_64/amd64 architecture for Lambda compatibility
echo "🔍 Detected architecture: $(uname -m)"
echo "🔨 Building Lambda image for linux/amd64 (required by AWS Lambda)..."

# Always use buildx for cross-platform builds
if ! docker buildx version &>/dev/null; then
    echo "❌ Docker buildx is required for cross-platform builds"
    echo "💡 Please enable Docker buildx or use an x86_64 machine"
    exit 1
fi

# Create buildx builder if it doesn't exist
docker buildx create --name lambda-builder --use 2>/dev/null || docker buildx use lambda-builder 2>/dev/null || true

# Build for linux/amd64 platform specifically
docker buildx build \
    --platform linux/amd64 \
    --load \
    -t ${LAMBDA_IMAGE_NAME}:${LAMBDA_IMAGE_TAG} \
    -f ${DOCKERFILE_PATH} \
    ${BUILD_CONTEXT}

if [ $? -ne 0 ]; then
    echo "❌ Failed to build Lambda Docker image"
    exit 1
fi

echo "✅ Lambda image built successfully"

# Inspect the image to verify it's correct
echo "🔍 Inspecting Lambda image..."
docker inspect ${LAMBDA_IMAGE_NAME}:${LAMBDA_IMAGE_TAG} --format='{{.Architecture}}' || true

# Tag and push Lambda image
echo "🏷️  Tagging Lambda image for ECR..."
docker tag ${LAMBDA_IMAGE_NAME}:${LAMBDA_IMAGE_TAG} ${LAMBDA_ECR_URI}:${LAMBDA_IMAGE_TAG}

echo "📤 Pushing Lambda image to ECR..."
docker push ${LAMBDA_ECR_URI}:${LAMBDA_IMAGE_TAG}

if [ $? -ne 0 ]; then
    echo "❌ Failed to push Lambda image to ECR"
    exit 1
fi

echo "✅ Lambda image pushed successfully"

# Set IMAGE_URI to Lambda-specific image
IMAGE_URI="${LAMBDA_ECR_URI}:${LAMBDA_IMAGE_TAG}"
echo "✅ Lambda image built and pushed: ${IMAGE_URI}"

# Verify the image exists in ECR and get its details
echo "🔍 Verifying image in ECR..."
IMAGE_DETAILS=$(aws ecr describe-images --repository-name ${LAMBDA_IMAGE_NAME} --image-ids imageTag=${LAMBDA_IMAGE_TAG} --region ${AWS_REGION} 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "✅ Image verified in ECR"
    # Show image size and architecture
    echo "📊 Image details:"
    echo "$IMAGE_DETAILS" | jq -r '.imageDetails[0] | "Size: \(.imageSizeInBytes) bytes, Pushed: \(.imagePushedAt)"' 2>/dev/null || echo "Image found in ECR"
else
    echo "❌ Failed to verify image in ECR"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Create Lambda execution role if it doesn't exist
echo "🔐 Creating Lambda execution role..."
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text 2>/dev/null)

if [ -z "$ROLE_ARN" ] || [ "$ROLE_ARN" == "None" ]; then
    echo "Creating ${ROLE_NAME}..."
    
    # Create trust policy
    cat > /tmp/trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --region ${AWS_REGION}
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        --region ${AWS_REGION}
    
    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_NUMBER}:role/${ROLE_NAME}"
    
    echo "⏳ Waiting for role to be available..."
    sleep 10
fi

echo "✅ Using role: ${ROLE_ARN}"

# Check if Lambda function exists
echo "🔍 Checking if Lambda function exists..."
FUNCTION_EXISTS=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.FunctionName' --output text 2>/dev/null)

if [ "$FUNCTION_EXISTS" == "${FUNCTION_NAME}" ]; then
    echo "🔄 Updating existing Lambda function..."
    aws lambda update-function-code \
        --function-name ${FUNCTION_NAME} \
        --image-uri ${IMAGE_URI} \
        --region ${AWS_REGION}
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update Lambda function"
        exit 1
    fi
    
    # Update function configuration
    aws lambda update-function-configuration \
        --function-name ${FUNCTION_NAME} \
        --timeout 30 \
        --memory-size 512 \
        --environment Variables='{PYTHONUNBUFFERED=1}' \
        --region ${AWS_REGION}
        
else
    echo "🆕 Creating new Lambda function..."
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --package-type Image \
        --code ImageUri=${IMAGE_URI} \
        --role ${ROLE_ARN} \
        --timeout 30 \
        --memory-size 512 \
        --environment Variables='{PYTHONUNBUFFERED=1}' \
        --region ${AWS_REGION}
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create Lambda function"
        exit 1
    fi
fi

# Wait for function to be active
echo "⏳ Waiting for function to be active..."
aws lambda wait function-active --function-name ${FUNCTION_NAME} --region ${AWS_REGION}

# Create or update function URL configuration with AWS_IAM auth
echo "🌐 Creating function URL with AWS_IAM authentication..."
FUNCTION_URL=$(aws lambda create-function-url-config \
    --function-name ${FUNCTION_NAME} \
    --auth-type AWS_IAM \
    --cors 'AllowCredentials=true,AllowHeaders=["authorization","content-type","x-amz-date","x-amz-security-token"],AllowMethods=["*"],AllowOrigins=["*"]' \
    --region ${AWS_REGION} \
    --query 'FunctionUrl' \
    --output text 2>/dev/null)

# Add IAM permission for authenticated access
if [ $? -eq 0 ] && [ ! -z "$FUNCTION_URL" ]; then
    echo "🔐 Adding IAM permission for authenticated access..."
    aws lambda add-permission \
        --function-name ${FUNCTION_NAME} \
        --statement-id FunctionURLAllowIAMAccess \
        --action lambda:InvokeFunctionUrl \
        --principal "*" \
        --function-url-auth-type AWS_IAM \
        --region ${AWS_REGION} > /dev/null 2>&1 || echo "   (Permission may already exist)"
fi

if [ -z "$FUNCTION_URL" ]; then
    # Function URL might already exist, get it
    FUNCTION_URL=$(aws lambda get-function-url-config \
        --function-name ${FUNCTION_NAME} \
        --region ${AWS_REGION} \
        --query 'FunctionUrl' \
        --output text 2>/dev/null)
fi

# Test the function
echo "🧪 Testing Lambda function..."
TEST_RESPONSE=$(aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"httpMethod": "GET", "path": "/health", "headers": {}}' \
    --region ${AWS_REGION} \
    /tmp/response.json 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "✅ Function test successful!"
    cat /tmp/response.json
else
    echo "⚠️  Function test failed, but deployment completed"
fi

echo ""
echo "✅ Lambda deployment completed!"
echo "📍 Function Name: ${FUNCTION_NAME}"
echo "📍 Function ARN: arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_NUMBER}:function:${FUNCTION_NAME}"
if [ ! -z "$FUNCTION_URL" ]; then
    echo "📍 Function URL: ${FUNCTION_URL}"
    echo "🔐 Authentication: AWS_IAM (requires signed requests)"
    echo ""
    echo "🌐 To access in browser, generate a signed URL:"
    echo "   ./get-signed-url.sh /health"
    echo "   ./get-signed-url.sh /users"
    echo ""
    echo "🔧 For programmatic access with AWS SDK:"
    echo "   Use AWS credentials to sign requests to: ${FUNCTION_URL}"
fi
echo ""
echo "💡 Useful commands:"
echo "   aws lambda invoke --function-name ${FUNCTION_NAME} --payload '{}' response.json --region ${AWS_REGION}"
echo "   aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION}"
echo "   aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"