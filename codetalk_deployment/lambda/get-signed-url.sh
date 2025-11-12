#!/bin/bash

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"
FUNCTION_NAME="${FUNCTION_NAME:-clean-architecture-lambda}"
API_PATH="${1:-/health}"

echo "🔗 Lambda Function URL Access Helper"
echo "📍 Function: ${FUNCTION_NAME}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Path: ${API_PATH}"
echo ""

# Get function URL and auth type
FUNCTION_URL=$(aws lambda get-function-url-config --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'FunctionUrl' --output text 2>/dev/null)
AUTH_TYPE=$(aws lambda get-function-url-config --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'AuthType' --output text 2>/dev/null)

if [ -z "$FUNCTION_URL" ] || [ "$FUNCTION_URL" == "None" ]; then
    echo "❌ Function URL not found"
    exit 1
fi

echo "✅ Function URL: ${FUNCTION_URL}"
echo "🔐 Auth Type: ${AUTH_TYPE}"
echo ""

if [ "$AUTH_TYPE" == "AWS_IAM" ]; then
    echo "🔒 This function uses AWS_IAM authentication (recommended for production)."
    echo ""
    echo "📋 Access options:"
    echo ""
    echo "   Option 1: Use awscurl for signed requests"
    echo "   pip install awscurl"
    echo "   awscurl --service lambda --region ${AWS_REGION} '${FUNCTION_URL%/}${API_PATH}'"
    echo ""
    echo "   Option 2: Use AWS SDK in your application"
    echo "   (Recommended for production applications)"
    echo ""
    echo "   Option 3: Temporarily disable auth for quick testing"
    echo "   ./toggle-auth.sh NONE  # Test, then ./toggle-auth.sh AWS_IAM"
    echo ""
elif [ "$AUTH_TYPE" == "NONE" ]; then
    echo "⚠️  WARNING: Function has NO authentication (not recommended for production)"
    echo ""
    echo "🌐 Direct browser access available:"
    echo "   ${FUNCTION_URL%/}${API_PATH}"
    echo ""
    echo "🔧 Test with curl:"
    echo "   curl '${FUNCTION_URL%/}${API_PATH}'"
    echo ""
    echo "🔒 Enable IAM auth for production security:"
    echo "   ./toggle-auth.sh AWS_IAM"
fi