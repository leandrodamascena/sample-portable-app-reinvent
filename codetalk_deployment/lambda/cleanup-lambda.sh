#!/bin/bash

# Lambda cleanup script for Clean Architecture App

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi
FUNCTION_NAME="${FUNCTION_NAME:-clean-architecture-lambda}"
ROLE_NAME="${ROLE_NAME:-lambda-execution-role}"

echo "🧹 Cleaning up Lambda resources..."
echo "📍 Function: ${FUNCTION_NAME}"
echo "📍 Role: ${ROLE_NAME}"
echo ""

# Step 1: Delete Lambda function URL configuration and permissions
echo "🌐 Step 1: Deleting Lambda function URL and permissions..."

# Remove IAM permission
aws lambda remove-permission --function-name ${FUNCTION_NAME} --statement-id FunctionURLAllowIAMAccess --region ${AWS_REGION} 2>/dev/null || true

# Remove public permission (if exists)
aws lambda remove-permission --function-name ${FUNCTION_NAME} --statement-id FunctionURLAllowPublicAccess --region ${AWS_REGION} 2>/dev/null || true

# Delete function URL
aws lambda delete-function-url-config --function-name ${FUNCTION_NAME} --region ${AWS_REGION} 2>/dev/null && echo "✅ Function URL deleted" || echo "ℹ️  Function URL not found"

# Step 2: Delete Lambda function
echo "⚡ Step 2: Deleting Lambda function..."
FUNCTION_EXISTS=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.FunctionName' --output text 2>/dev/null)

if [ "$FUNCTION_EXISTS" == "${FUNCTION_NAME}" ]; then
    echo "🗑️  Deleting function ${FUNCTION_NAME}..."
    aws lambda delete-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} >/dev/null
    echo "✅ Lambda function deleted"
else
    echo "ℹ️  Lambda function ${FUNCTION_NAME} not found"
fi

# Step 3: Delete CloudWatch log group
echo "📝 Step 3: Deleting CloudWatch log group..."
aws logs delete-log-group --log-group-name /aws/lambda/${FUNCTION_NAME} --region ${AWS_REGION} 2>/dev/null && echo "✅ Log group deleted" || echo "ℹ️  Log group not found"

# Step 4: Clean up IAM role (optional - ask user)
echo ""
echo "🔐 Step 4: IAM role cleanup..."
echo "The following IAM role was created and can be deleted:"
echo "   - ${ROLE_NAME}"
echo ""
read -p "Do you want to delete this IAM role? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Deleting IAM role..."
    
    # Detach policies and delete role
    aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role --role-name ${ROLE_NAME} 2>/dev/null && echo "✅ IAM role deleted" || echo "ℹ️  IAM role not found"
else
    echo "ℹ️  IAM role preserved"
fi

# Step 5: Clean up Lambda ECR repository (optional)
echo ""
echo "📦 Step 5: Lambda ECR repository cleanup..."
LAMBDA_IMAGE_NAME="clean-architecture-app-lambda"
echo "The Lambda-specific ECR repository was created: ${LAMBDA_IMAGE_NAME}"
echo ""
read -p "Do you want to delete the Lambda ECR repository? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Deleting Lambda ECR repository..."
    
    # Delete all images first
    aws ecr list-images --repository-name ${LAMBDA_IMAGE_NAME} --region ${AWS_REGION} --query 'imageIds[*]' --output json > /tmp/lambda-images.json 2>/dev/null || echo "[]" > /tmp/lambda-images.json
    
    if [ "$(cat /tmp/lambda-images.json)" != "[]" ]; then
        aws ecr batch-delete-image --repository-name ${LAMBDA_IMAGE_NAME} --image-ids file:///tmp/lambda-images.json --region ${AWS_REGION} 2>/dev/null || true
    fi
    
    # Delete repository
    aws ecr delete-repository --repository-name ${LAMBDA_IMAGE_NAME} --region ${AWS_REGION} 2>/dev/null && echo "✅ Lambda ECR repository deleted" || echo "ℹ️  Repository not found"
else
    echo "ℹ️  Lambda ECR repository preserved"
fi

echo ""
echo "✅ Lambda cleanup completed!"
echo "📍 All Lambda resources for ${FUNCTION_NAME} have been removed"