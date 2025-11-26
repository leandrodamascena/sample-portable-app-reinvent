#!/bin/bash

# ECS cleanup script for Clean Architecture App

# Configuration variables
AWS_REGION="${AWS_REGION:-us-west-2}"

# Get AWS account number dynamically
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
    echo "❌ Unable to get AWS account number. Please check your AWS credentials."
    exit 1
fi
CLUSTER_NAME="${CLUSTER_NAME:-clean-architecture-cluster}"
SERVICE_NAME="${SERVICE_NAME:-clean-architecture-service}"
TASK_FAMILY="${TASK_FAMILY:-clean-architecture-task}"
CAPACITY_PROVIDER_NAME="${CAPACITY_PROVIDER_NAME:-${CLUSTER_NAME}-managed-instances}"

echo "🧹 Cleaning up ECS resources..."
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Service: ${SERVICE_NAME}"
echo "📍 Capacity Provider: ${CAPACITY_PROVIDER_NAME}"
echo ""

# Step 1: Scale down and delete ECS service
echo "🔄 Step 1: Scaling down and deleting ECS service..."
SERVICE_EXISTS=$(aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION} --query 'services[0].status' --output text 2>/dev/null)

if [ "$SERVICE_EXISTS" == "ACTIVE" ] || [ "$SERVICE_EXISTS" == "DRAINING" ]; then
    echo "📉 Scaling service to 0 tasks..."
    aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --desired-count 0 --region ${AWS_REGION} >/dev/null 2>&1 || true
    
    echo "⏳ Stopping all running tasks..."
    TASK_ARNS=$(aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --region ${AWS_REGION} --query 'taskArns' --output text 2>/dev/null)
    if [ ! -z "$TASK_ARNS" ] && [ "$TASK_ARNS" != "None" ]; then
        for TASK_ARN in $TASK_ARNS; do
            echo "🛑 Stopping task: $(basename $TASK_ARN)"
            aws ecs stop-task --cluster ${CLUSTER_NAME} --task $TASK_ARN --region ${AWS_REGION} >/dev/null 2>&1 || true
        done
    fi
    
    echo "⏳ Waiting for all tasks to stop (this may take a minute)..."
    sleep 30
    
    echo "🗑️  Deleting service..."
    aws ecs delete-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --force --region ${AWS_REGION} >/dev/null 2>&1 || true
    echo "✅ Service deleted"
else
    echo "ℹ️  Service ${SERVICE_NAME} not found or already deleted"
fi

# Step 2: Remove capacity provider association and delete it
echo "🖥️  Step 2: Removing capacity provider from cluster..."
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} --query 'clusters[0].status' --output text 2>/dev/null)

if [ "$CLUSTER_EXISTS" == "ACTIVE" ]; then
    echo "🔗 Clearing capacity provider strategy from cluster..."
    aws ecs put-cluster-capacity-providers \
        --cluster ${CLUSTER_NAME} \
        --capacity-providers [] \
        --default-capacity-provider-strategy [] \
        --region ${AWS_REGION} >/dev/null 2>&1 || true
    
    echo "⏳ Waiting for capacity provider to detach..."
    sleep 10
fi

echo "🗑️  Deleting managed instances capacity provider..."
CP_EXISTS=$(aws ecs describe-capacity-providers --capacity-providers ${CAPACITY_PROVIDER_NAME} --region ${AWS_REGION} --query 'capacityProviders[0].name' --output text 2>/dev/null)

if [ "$CP_EXISTS" == "${CAPACITY_PROVIDER_NAME}" ]; then
    aws ecs delete-capacity-provider --capacity-provider ${CAPACITY_PROVIDER_NAME} --region ${AWS_REGION} >/dev/null 2>&1 || true
    echo "✅ Managed instances capacity provider deleted"
else
    echo "ℹ️  Capacity provider ${CAPACITY_PROVIDER_NAME} not found"
fi

# Step 3: Delete ECS cluster
echo "📦 Step 3: Deleting ECS cluster..."
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} --query 'clusters[0].status' --output text 2>/dev/null)

if [ "$CLUSTER_EXISTS" == "ACTIVE" ]; then
    echo "🗑️  Deleting cluster..."
    aws ecs delete-cluster --cluster ${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null
    echo "✅ Cluster deleted"
else
    echo "ℹ️  Cluster ${CLUSTER_NAME} not found or already deleted"
fi

# Step 4: Clean up task definitions (deregister active revisions)
echo "📋 Step 4: Deregistering task definitions..."
TASK_ARNS=$(aws ecs list-task-definitions --family-prefix ${TASK_FAMILY} --status ACTIVE --region ${AWS_REGION} --query 'taskDefinitionArns' --output text 2>/dev/null)

if [ ! -z "$TASK_ARNS" ] && [ "$TASK_ARNS" != "None" ]; then
    for TASK_ARN in $TASK_ARNS; do
        echo "🗑️  Deregistering task definition: $(basename $TASK_ARN)"
        aws ecs deregister-task-definition --task-definition $TASK_ARN --region ${AWS_REGION} >/dev/null
    done
    echo "✅ Task definitions deregistered"
else
    echo "ℹ️  No active task definitions found for family ${TASK_FAMILY}"
fi

# Step 5: Delete CloudWatch log group
echo "📝 Step 5: Deleting CloudWatch log group..."
aws logs delete-log-group --log-group-name /ecs/${TASK_FAMILY} --region ${AWS_REGION} 2>/dev/null && echo "✅ Log group deleted" || echo "ℹ️  Log group not found"

# Step 6: Delete Load Balancer resources
echo "⚖️  Step 6: Deleting Load Balancer resources..."
ALB_NAME="${SERVICE_NAME}-alb"
TG_NAME="${SERVICE_NAME}-tg"

# Delete ALB
ALB_ARN=$(aws elbv2 describe-load-balancers --names ${ALB_NAME} --query 'LoadBalancers[0].LoadBalancerArn' --output text --region ${AWS_REGION} 2>/dev/null)
if [ "$ALB_ARN" != "None" ] && [ ! -z "$ALB_ARN" ]; then
    echo "🗑️  Deleting Application Load Balancer..."
    aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} --region ${AWS_REGION} 2>/dev/null && echo "✅ ALB deleted" || echo "ℹ️  ALB not found"
fi

# Delete Target Group
TG_ARN=$(aws elbv2 describe-target-groups --names ${TG_NAME} --query 'TargetGroups[0].TargetGroupArn' --output text --region ${AWS_REGION} 2>/dev/null)
if [ "$TG_ARN" != "None" ] && [ ! -z "$TG_ARN" ]; then
    echo "🗑️  Deleting Target Group..."
    aws elbv2 delete-target-group --target-group-arn ${TG_ARN} --region ${AWS_REGION} 2>/dev/null && echo "✅ Target Group deleted" || echo "ℹ️  Target Group not found"
fi

# Step 7: Delete security groups
echo "🔒 Step 7: Deleting security groups..."

# Delete ECS service security group
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SERVICE_NAME}-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${AWS_REGION} 2>/dev/null)
if [ "$SG_ID" != "None" ] && [ ! -z "$SG_ID" ]; then
    echo "🗑️  Deleting ECS service security group ${SG_ID}..."
    aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION} 2>/dev/null && echo "✅ ECS security group deleted" || echo "⚠️  ECS security group may be in use"
fi

# Delete ALB security group
ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SERVICE_NAME}-alb-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${AWS_REGION} 2>/dev/null)
if [ "$ALB_SG_ID" != "None" ] && [ ! -z "$ALB_SG_ID" ]; then
    echo "🗑️  Deleting ALB security group ${ALB_SG_ID}..."
    sleep 30  # Wait for ALB to be fully deleted
    aws ec2 delete-security-group --group-id ${ALB_SG_ID} --region ${AWS_REGION} 2>/dev/null && echo "✅ ALB security group deleted" || echo "⚠️  ALB security group may be in use"
fi

# Step 8: Clean up IAM roles (optional - ask user)
echo ""
echo "🔐 Step 8: IAM roles cleanup..."
echo "The following IAM roles were created and can be deleted:"
echo "   - ecsTaskExecutionRole"
echo "   - ecsInfrastructureRole" 
echo "   - ecsInstanceRole-${CLUSTER_NAME}"
echo "   - Instance profile: ecsInstanceProfile-${CLUSTER_NAME}"
echo ""
read -p "Do you want to delete these IAM roles? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Deleting IAM roles..."
    
    # Delete instance profile and role
    INSTANCE_PROFILE_NAME="ecsInstanceProfile-${CLUSTER_NAME}"
    INSTANCE_ROLE_NAME="ecsInstanceRole-${CLUSTER_NAME}"
    
    aws iam remove-role-from-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} --role-name ${INSTANCE_ROLE_NAME} 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} 2>/dev/null || true
    aws iam detach-role-policy --role-name ${INSTANCE_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role 2>/dev/null || true
    aws iam delete-role --role-name ${INSTANCE_ROLE_NAME} 2>/dev/null || true
    
    # Delete infrastructure role
    aws iam detach-role-policy --role-name ecsInfrastructureRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicy 2>/dev/null || true
    aws iam delete-role --role-name ecsInfrastructureRole 2>/dev/null || true
    
    # Note: We don't delete ecsTaskExecutionRole as it might be used by other services
    echo "✅ IAM roles cleaned up"
    echo "ℹ️  Note: ecsTaskExecutionRole was preserved as it may be used by other ECS services"
else
    echo "ℹ️  IAM roles preserved"
fi

echo ""
echo "✅ ECS cleanup completed!"
echo "📍 All ECS resources for ${CLUSTER_NAME} have been removed"