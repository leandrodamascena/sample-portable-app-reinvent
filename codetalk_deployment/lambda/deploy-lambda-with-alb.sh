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
ALB_NAME="${ALB_NAME:-clean-architecture-lambda-alb}"
TG_NAME="${TG_NAME:-clean-architecture-lambda-tg}"
IMAGE_URI="${IMAGE_URI}"
ROLE_NAME="${ROLE_NAME:-lambda-execution-role}"

echo "🚀 Deploying Lambda with Application Load Balancer..."
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Function: ${FUNCTION_NAME}"
echo "📍 ALB: ${ALB_NAME}"
echo ""

# First, run the standard Lambda deployment
echo "📦 Step 1: Deploying Lambda function..."
CURRENT_DIR=$(basename "$PWD")
if [ "$CURRENT_DIR" == "lambda" ]; then
    ./deploy-lambda.sh
else
    ./lambda/deploy-lambda.sh
fi

if [ $? -ne 0 ]; then
    echo "❌ Lambda deployment failed"
    exit 1
fi

echo ""
echo "🌐 Step 2: Setting up Application Load Balancer..."

# Get VPC and network configuration
echo "🔍 Getting VPC and network configuration..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region ${AWS_REGION})
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[].SubnetId' --output text --region ${AWS_REGION})
SUBNET_ARRAY=(${SUBNET_IDS})

echo "✅ VPC: ${VPC_ID}"
echo "✅ Subnets: ${SUBNET_ARRAY[@]}"

# Create ALB Security Group
echo "🔒 Creating ALB security group..."
ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${ALB_NAME}-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${AWS_REGION} 2>/dev/null)

if [ "$ALB_SG_ID" == "None" ] || [ -z "$ALB_SG_ID" ]; then
    ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name ${ALB_NAME}-sg \
        --description "ALB Security group for Lambda ${FUNCTION_NAME}" \
        --vpc-id ${VPC_ID} \
        --region ${AWS_REGION} \
        --query 'GroupId' \
        --output text)
    
    # Allow HTTP traffic from internet to ALB
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region ${AWS_REGION}
    
    echo "✅ ALB security group created: ${ALB_SG_ID}"
else
    echo "✅ Using existing ALB security group: ${ALB_SG_ID}"
fi

# Create Application Load Balancer
echo "⚖️  Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names ${ALB_NAME} --query 'LoadBalancers[0].LoadBalancerArn' --output text --region ${AWS_REGION} 2>/dev/null)

if [ "$ALB_ARN" == "None" ] || [ -z "$ALB_ARN" ]; then
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name ${ALB_NAME} \
        --subnets ${SUBNET_ARRAY[0]} ${SUBNET_ARRAY[1]} \
        --security-groups ${ALB_SG_ID} \
        --region ${AWS_REGION} \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    echo "✅ ALB created: ${ALB_ARN}"
else
    echo "✅ Using existing ALB: ${ALB_ARN}"
fi

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns ${ALB_ARN} --query 'LoadBalancers[0].DNSName' --output text --region ${AWS_REGION})

# Get Lambda function ARN and ensure it's ready
echo "🔍 Getting Lambda function details..."
LAMBDA_ARN=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.FunctionArn' --output text)
LAMBDA_STATE=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.State' --output text)
LAMBDA_UPDATE_STATUS=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.LastUpdateStatus' --output text)

echo "   Lambda ARN: ${LAMBDA_ARN}"
echo "   Lambda State: ${LAMBDA_STATE}"
echo "   Lambda Update Status: ${LAMBDA_UPDATE_STATUS}"

# Wait for Lambda to be fully ready
if [ "$LAMBDA_STATE" != "Active" ] || [ "$LAMBDA_UPDATE_STATUS" != "Successful" ]; then
    echo "⏳ Waiting for Lambda function to be fully ready..."
    for i in {1..30}; do
        sleep 5
        LAMBDA_STATE=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.State' --output text)
        LAMBDA_UPDATE_STATUS=$(aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.LastUpdateStatus' --output text)
        echo "   Attempt ${i}/30: State=${LAMBDA_STATE}, UpdateStatus=${LAMBDA_UPDATE_STATUS}"
        
        if [ "$LAMBDA_STATE" == "Active" ] && [ "$LAMBDA_UPDATE_STATUS" == "Successful" ]; then
            echo "✅ Lambda function is ready"
            break
        fi
    done
    
    if [ "$LAMBDA_STATE" != "Active" ] || [ "$LAMBDA_UPDATE_STATUS" != "Successful" ]; then
        echo "⚠️  Lambda function may not be fully ready, but continuing..."
    fi
fi

# Create Target Group for Lambda
echo "🎯 Creating Target Group for Lambda..."
TG_ARN=$(aws elbv2 describe-target-groups --names ${TG_NAME} --query 'TargetGroups[0].TargetGroupArn' --output text --region ${AWS_REGION} 2>/dev/null)

if [ "$TG_ARN" == "None" ] || [ -z "$TG_ARN" ]; then
    echo "Creating new Lambda target group..."
    TG_ARN=$(aws elbv2 create-target-group \
        --name ${TG_NAME} \
        --target-type lambda \
        --region ${AWS_REGION} \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create target group: ${TG_ARN}"
        exit 1
    fi
    echo "✅ Target Group created: ${TG_ARN}"
    
    # Wait for target group to be ready
    sleep 3
else
    echo "✅ Using existing Target Group: ${TG_ARN}"
    # Verify it's a Lambda target group
    TG_TYPE=$(aws elbv2 describe-target-groups --target-group-arns ${TG_ARN} --query 'TargetGroups[0].TargetType' --output text --region ${AWS_REGION})
    if [ "$TG_TYPE" != "lambda" ]; then
        echo "⚠️  Existing target group is not Lambda type (${TG_TYPE}). Deleting and recreating..."
        aws elbv2 delete-target-group --target-group-arn ${TG_ARN} --region ${AWS_REGION}
        sleep 5
        TG_ARN=$(aws elbv2 create-target-group \
            --name ${TG_NAME} \
            --target-type lambda \
            --region ${AWS_REGION} \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
        echo "✅ New Lambda Target Group created: ${TG_ARN}"
        sleep 3
    fi
fi

# Add permission for ALB to invoke Lambda FIRST (before registration)
echo "🔐 Adding permission for ALB to invoke Lambda..."
# Remove old permission if exists
aws lambda remove-permission \
    --function-name ${FUNCTION_NAME} \
    --statement-id AllowALBInvoke \
    --region ${AWS_REGION} 2>/dev/null || true

# Add new permission
aws lambda add-permission \
    --function-name ${FUNCTION_NAME} \
    --statement-id AllowALBInvoke \
    --action lambda:InvokeFunction \
    --principal elasticloadbalancing.amazonaws.com \
    --source-arn ${TG_ARN} \
    --region ${AWS_REGION} 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Permission added successfully"
else
    echo "⚠️  Permission may already exist"
fi

# Wait for permission to propagate
sleep 5

# Register Lambda function with Target Group
echo "📝 Registering Lambda function with Target Group..."
echo "   Lambda ARN: ${LAMBDA_ARN}"
echo "   Target Group ARN: ${TG_ARN}"

# First, check current targets
echo "🔍 Checking current targets..."
CURRENT_TARGETS=$(aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION} 2>&1)
echo "   Current targets: ${CURRENT_TARGETS}"

# For Lambda targets, deregister any existing targets first
echo "🗑️  Deregistering any existing targets..."
aws elbv2 deregister-targets \
    --target-group-arn ${TG_ARN} \
    --targets Id=${LAMBDA_ARN} \
    --region ${AWS_REGION} 2>/dev/null || true

# Wait for deregistration
sleep 3

# Now register the Lambda - Lambda targets need the full ARN
echo "📝 Registering Lambda with full ARN..."
REGISTER_OUTPUT=$(aws elbv2 register-targets \
    --target-group-arn ${TG_ARN} \
    --targets Id=${LAMBDA_ARN} \
    --region ${AWS_REGION} 2>&1)

REGISTER_EXIT_CODE=$?
echo "   Registration exit code: ${REGISTER_EXIT_CODE}"
echo "   Registration output: ${REGISTER_OUTPUT}"

if [ $REGISTER_EXIT_CODE -eq 0 ]; then
    echo "✅ Lambda function registered with Target Group"
else
    echo "❌ Failed to register Lambda"
    echo "🔍 Debugging information:"
    echo "   Lambda ARN: ${LAMBDA_ARN}"
    echo "   Target Group ARN: ${TG_ARN}"
    echo "   Target Group Type: $(aws elbv2 describe-target-groups --target-group-arns ${TG_ARN} --query 'TargetGroups[0].TargetType' --output text --region ${AWS_REGION})"
    
    # Try to get more details about the error
    if [[ "$REGISTER_OUTPUT" == *"InvalidTarget"* ]]; then
        echo "⚠️  InvalidTarget error - checking Lambda function state..."
        aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} --query 'Configuration.[State,LastUpdateStatus]' --output text
    fi
    
    if [[ "$REGISTER_OUTPUT" == *"AccessDenied"* ]]; then
        echo "⚠️  AccessDenied error - checking Lambda permissions..."
        aws lambda get-policy --function-name ${FUNCTION_NAME} --region ${AWS_REGION} 2>&1 | jq '.' || echo "No policy found"
    fi
fi

# Create ALB Listener
echo "👂 Creating ALB Listener..."
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn ${ALB_ARN} --query 'Listeners[0].ListenerArn' --output text --region ${AWS_REGION} 2>/dev/null)

if [ "$LISTENER_ARN" == "None" ] || [ -z "$LISTENER_ARN" ]; then
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn ${ALB_ARN} \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
        --region ${AWS_REGION} \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    echo "✅ ALB Listener created: ${LISTENER_ARN}"
else
    echo "✅ Using existing ALB Listener: ${LISTENER_ARN}"
fi

# Verify target registration
echo ""
echo "🔍 Verifying Lambda target registration..."
sleep 5
TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION} 2>&1)

if [ $? -eq 0 ]; then
    echo "✅ Target health check:"
    echo "$TARGET_HEALTH" | jq -r '.TargetHealthDescriptions[] | "   Target: \(.Target.Id)\n   State: \(.TargetHealth.State)\n   Reason: \(.TargetHealth.Reason // "N/A")"' 2>/dev/null || echo "$TARGET_HEALTH"
else
    echo "⚠️  Could not verify target health: ${TARGET_HEALTH}"
fi

echo ""
echo "🎉 Lambda with ALB deployment completed!"
echo ""
echo "📋 Deployment Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚡ Lambda Function: ${FUNCTION_NAME}"
echo "   ARN: ${LAMBDA_ARN}"
echo ""
echo "⚖️  Application Load Balancer: ${ALB_NAME}"
echo "   ARN: ${ALB_ARN}"
echo "   DNS: ${ALB_DNS}"
echo ""
echo "🎯 Target Group: ${TG_NAME}"
echo "   ARN: ${TG_ARN}"
echo ""
echo "🌐 Access your application:"
echo "   http://${ALB_DNS}"
echo "   http://${ALB_DNS}/health"
echo "   http://${ALB_DNS}/users"
echo "   http://${ALB_DNS}/orders"
echo ""
echo "💡 The ALB provides:"
echo "   ✓ Public access without AWS credentials"
echo "   ✓ SSL/TLS termination (add HTTPS listener)"
echo "   ✓ Custom domain support (via Route 53)"
echo "   ✓ WAF integration for security"
echo "   ✓ Better monitoring and logging"
echo ""
echo "💡 Useful commands:"
echo "   aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION}"
echo "   aws elbv2 describe-load-balancers --load-balancer-arns ${ALB_ARN} --region ${AWS_REGION}"
echo "   aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"
