#!/bin/bash

# Force cleanup ECS resources - handles stuck capacity providers

AWS_REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-clean-architecture-cluster}"

echo "🧹 Force cleaning up ECS cluster: ${CLUSTER_NAME}"
echo ""

# Step 1: Stop all tasks
echo "🛑 Step 1: Stopping all tasks..."
TASK_ARNS=$(aws ecs list-tasks --cluster ${CLUSTER_NAME} --region ${AWS_REGION} --query 'taskArns' --output text 2>/dev/null)
if [ ! -z "$TASK_ARNS" ] && [ "$TASK_ARNS" != "None" ]; then
    for TASK_ARN in $TASK_ARNS; do
        echo "   Stopping task: $(basename $TASK_ARN)"
        aws ecs stop-task --cluster ${CLUSTER_NAME} --task $TASK_ARN --region ${AWS_REGION} >/dev/null 2>&1 || true
    done
    echo "⏳ Waiting for tasks to stop..."
    sleep 30
fi

# Step 2: Delete all services
echo "🗑️  Step 2: Deleting all services..."
SERVICE_ARNS=$(aws ecs list-services --cluster ${CLUSTER_NAME} --region ${AWS_REGION} --query 'serviceArns' --output text 2>/dev/null)
if [ ! -z "$SERVICE_ARNS" ] && [ "$SERVICE_ARNS" != "None" ]; then
    for SERVICE_ARN in $SERVICE_ARNS; do
        SERVICE_NAME=$(basename $SERVICE_ARN)
        echo "   Deleting service: ${SERVICE_NAME}"
        aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --desired-count 0 --region ${AWS_REGION} >/dev/null 2>&1 || true
        sleep 5
        aws ecs delete-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --force --region ${AWS_REGION} >/dev/null 2>&1 || true
    done
    echo "⏳ Waiting for services to be deleted..."
    sleep 30
fi

# Step 3: Clear capacity provider strategy
echo "🔗 Step 3: Clearing capacity provider strategy..."
aws ecs put-cluster-capacity-providers \
    --cluster ${CLUSTER_NAME} \
    --capacity-providers [] \
    --default-capacity-provider-strategy [] \
    --region ${AWS_REGION} >/dev/null 2>&1 || true

echo "⏳ Waiting for capacity providers to detach..."
sleep 15

# Step 4: Delete Auto Scaling Groups and EC2 instances
echo "🖥️  Step 4: Deleting Auto Scaling Groups and EC2 instances..."
ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups --region ${AWS_REGION} --query "AutoScalingGroups[?contains(AutoScalingGroupName, '${CLUSTER_NAME}')].AutoScalingGroupName" --output text 2>/dev/null)
if [ ! -z "$ASG_NAMES" ] && [ "$ASG_NAMES" != "None" ]; then
    for ASG_NAME in $ASG_NAMES; do
        echo "   Deleting Auto Scaling Group: ${ASG_NAME}"
        # Set desired capacity to 0
        aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${ASG_NAME} --min-size 0 --max-size 0 --desired-capacity 0 --region ${AWS_REGION} 2>/dev/null || true
        sleep 10
        # Force delete with instances
        aws autoscaling delete-auto-scaling-group --auto-scaling-group-name ${ASG_NAME} --force-delete --region ${AWS_REGION} 2>/dev/null || true
    done
    echo "⏳ Waiting for Auto Scaling Groups to be deleted..."
    sleep 30
fi

# Step 5: Delete all capacity providers
echo "🗑️  Step 5: Deleting capacity providers..."
CP_NAMES=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} --include ATTACHMENTS --query 'clusters[0].capacityProviders' --output text 2>/dev/null)
if [ ! -z "$CP_NAMES" ] && [ "$CP_NAMES" != "None" ]; then
    for CP_NAME in $CP_NAMES; do
        echo "   Deleting capacity provider: ${CP_NAME}"
        aws ecs delete-capacity-provider --capacity-provider ${CP_NAME} --region ${AWS_REGION} 2>&1 | grep -v "INACTIVE" || true
        sleep 5
    done
fi

# Step 6: Delete cluster
echo "📦 Step 6: Deleting cluster..."
aws ecs delete-cluster --cluster ${CLUSTER_NAME} --region ${AWS_REGION} 2>&1 | grep -v "ClientException" || true

echo ""
echo "✅ Force cleanup completed!"
echo ""
echo "🔍 Verifying cleanup..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} --query 'clusters[0].status' --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" == "INACTIVE" ] || [ -z "$CLUSTER_STATUS" ] || [ "$CLUSTER_STATUS" == "None" ]; then
    echo "✅ Cluster successfully deleted"
else
    echo "⚠️  Cluster status: ${CLUSTER_STATUS}"
    echo "💡 If cluster is still active, wait a few minutes and run this script again"
fi
