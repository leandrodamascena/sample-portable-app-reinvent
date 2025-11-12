#!/bin/bash

# Toggle Lambda Function URL authentication between NONE and AWS_IAM

AWS_REGION="${AWS_REGION:-us-west-2}"
FUNCTION_NAME="${FUNCTION_NAME:-clean-architecture-lambda}"
AUTH_TYPE="${1}"

echo "🔐 Lambda Function URL Authentication Toggle"
echo "📍 Function: ${FUNCTION_NAME}"
echo "📍 Region: ${AWS_REGION}"
echo ""

# Get current auth type
CURRENT_AUTH=$(aws lambda get-function-url-config --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'AuthType' --output text 2>/dev/null)

if [ -z "$CURRENT_AUTH" ] || [ "$CURRENT_AUTH" == "None" ]; then
    echo "❌ Function URL not found"
    exit 1
fi

echo "📋 Current auth type: ${CURRENT_AUTH}"

# Determine target auth type
if [ -z "$AUTH_TYPE" ]; then
    if [ "$CURRENT_AUTH" == "AWS_IAM" ]; then
        TARGET_AUTH="NONE"
    else
        TARGET_AUTH="AWS_IAM"
    fi
else
    TARGET_AUTH="$AUTH_TYPE"
fi

echo "🎯 Target auth type: ${TARGET_AUTH}"
echo ""

# Validate auth type
if [ "$TARGET_AUTH" != "NONE" ] && [ "$TARGET_AUTH" != "AWS_IAM" ]; then
    echo "❌ Invalid auth type. Use 'NONE' or 'AWS_IAM'"
    exit 1
fi

# Update function URL config
echo "🔄 Updating function URL authentication..."

if [ "$TARGET_AUTH" == "NONE" ]; then
    aws lambda update-function-url-config \
        --function-name ${FUNCTION_NAME} \
        --auth-type NONE \
        --cors 'AllowCredentials=false,AllowHeaders=["*"],AllowMethods=["*"],AllowOrigins=["*"]' \
        --region ${AWS_REGION} > /dev/null
    
    # Add permission for public access
    echo "🔓 Adding public access permission..."
    aws lambda add-permission \
        --function-name ${FUNCTION_NAME} \
        --statement-id FunctionURLAllowPublicAccess \
        --action lambda:InvokeFunctionUrl \
        --principal "*" \
        --function-url-auth-type NONE \
        --region ${AWS_REGION} > /dev/null 2>&1 || echo "   (Permission may already exist)"
        
else
    aws lambda update-function-url-config \
        --function-name ${FUNCTION_NAME} \
        --auth-type AWS_IAM \
        --cors 'AllowCredentials=true,AllowHeaders=["authorization","content-type","x-amz-date","x-amz-security-token"],AllowMethods=["*"],AllowOrigins=["*"]' \
        --region ${AWS_REGION} > /dev/null
    
    # Remove public access permission
    echo "🔒 Removing public access permission..."
    aws lambda remove-permission \
        --function-name ${FUNCTION_NAME} \
        --statement-id FunctionURLAllowPublicAccess \
        --region ${AWS_REGION} > /dev/null 2>&1 || echo "   (Permission may not exist)"
fi

if [ $? -eq 0 ]; then
    echo "✅ Authentication updated successfully!"
    
    # Get the function URL
    FUNCTION_URL=$(aws lambda get-function-url-config --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'FunctionUrl' --output text)
    
    echo "📍 Function URL: ${FUNCTION_URL}"
    echo "🔐 Auth Type: ${TARGET_AUTH}"
    echo ""
    
    if [ "$TARGET_AUTH" == "NONE" ]; then
        echo "🌐 You can now access directly in browser:"
        echo "   ${FUNCTION_URL}health"
        echo "   ${FUNCTION_URL}users"
        echo ""
        echo "⚠️  Remember to change back to AWS_IAM for production:"
        echo "   ./toggle-auth.sh AWS_IAM"
    else
        echo "🔒 Function now requires AWS IAM authentication"
        echo "💡 Use AWS SDK or signed requests for access"
    fi
else
    echo "❌ Failed to update authentication"
    exit 1
fi