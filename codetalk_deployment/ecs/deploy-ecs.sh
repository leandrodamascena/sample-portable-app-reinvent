#!/bin/bash

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
IMAGE_URI="${IMAGE_URI}"
DESIRED_COUNT="${DESIRED_COUNT:-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-m5.large}"
CAPACITY_PROVIDER_NAME="${CAPACITY_PROVIDER_NAME:-${CLUSTER_NAME}-instances}"

echo "� ADeploying to ECS..."
echo "📍 Account: ${AWS_ACCOUNT_NUMBER}"
echo "📍 Region: ${AWS_REGION}"
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Service: ${SERVICE_NAME}"
echo "📍 Image: ${IMAGE_URI}"
echo "📍 Instance Type: ${INSTANCE_TYPE}"
echo "📍 Capacity Provider: ${CAPACITY_PROVIDER_NAME}"
echo ""

# Check if IMAGE_URI is provided, if not try to source it automatically
if [ -z "$IMAGE_URI" ]; then
    if [ -f "../.image_uri" ]; then
        echo "🔄 IMAGE_URI not set, loading from build script..."
        source ../.image_uri
        echo "✅ Loaded IMAGE_URI: ${IMAGE_URI}"
    else
        echo "❌ IMAGE_URI is required. Either:"
        echo "   1. Run the build script first: ../build-and-push.sh"
        echo "   2. Or set manually: export IMAGE_URI=${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_REGION}.amazonaws.com/clean-architecture-app:latest"
        exit 1
    fi
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Step 1: Create IAM roles
echo "🔐 Step 1: Creating IAM roles..."

# Create task execution role
EXECUTION_ROLE_ARN=$(aws iam get-role --role-name ecsTaskExecutionRole --query 'Role.Arn' --output text 2>/dev/null)
if [ -z "$EXECUTION_ROLE_ARN" ] || [ "$EXECUTION_ROLE_ARN" == "None" ]; then
    echo "Creating ecsTaskExecutionRole..."
    aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ecs-tasks.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_NUMBER}:role/ecsTaskExecutionRole"
fi

# Create ECS infrastructure role for managed instances
INFRA_ROLE_NAME="ecsInfrastructureRole"
INFRA_ROLE_ARN=$(aws iam get-role --role-name ${INFRA_ROLE_NAME} --query 'Role.Arn' --output text 2>/dev/null)
if [ -z "$INFRA_ROLE_ARN" ] || [ "$INFRA_ROLE_ARN" == "None" ]; then
    echo "Creating ${INFRA_ROLE_NAME}..."
    aws iam create-role --role-name ${INFRA_ROLE_NAME} --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ecs.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    # Create custom infrastructure policy since the managed policy doesn't exist yet
    POLICY_NAME="ECSInfrastructureRolePolicy"
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_NUMBER}:policy/${POLICY_NAME}"
    
    # Check if policy exists
    aws iam get-policy --policy-arn ${POLICY_ARN} --region ${AWS_REGION} >/dev/null 2>&1 || {
        echo "Creating custom ECS Infrastructure policy..."
        cat > /tmp/ecs-infrastructure-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": [
                "arn:aws:iam::*:role/ecsInstanceRole*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DescribeImages",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeRouteTables",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs",
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "autoscaling:CreateAutoScalingGroup",
                "autoscaling:CreateLaunchConfiguration",
                "autoscaling:DeleteAutoScalingGroup",
                "autoscaling:DeleteLaunchConfiguration",
                "autoscaling:Describe*",
                "autoscaling:UpdateAutoScalingGroup",
                "ecs:CreateCluster",
                "ecs:DeregisterContainerInstance",
                "ecs:DescribeClusters",
                "ecs:DescribeContainerInstances",
                "ecs:RegisterContainerInstance",
                "ssm:GetParameters"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        aws iam create-policy --policy-name ${POLICY_NAME} --policy-document file:///tmp/ecs-infrastructure-policy.json --region ${AWS_REGION}
    }
    
    aws iam attach-role-policy --role-name ${INFRA_ROLE_NAME} --policy-arn ${POLICY_ARN} --region ${AWS_REGION}
    INFRA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_NUMBER}:role/${INFRA_ROLE_NAME}"
fi

# Create instance profile for container agent
INSTANCE_PROFILE_NAME="ecsInstanceProfile-${CLUSTER_NAME}"
INSTANCE_ROLE_NAME="ecsInstanceRole-${CLUSTER_NAME}"
INSTANCE_ROLE_ARN=$(aws iam get-role --role-name ${INSTANCE_ROLE_NAME} --query 'Role.Arn' --output text 2>/dev/null)
if [ -z "$INSTANCE_ROLE_ARN" ] || [ "$INSTANCE_ROLE_ARN" == "None" ]; then
    echo "Creating ${INSTANCE_ROLE_NAME}..."
    aws iam create-role --role-name ${INSTANCE_ROLE_NAME} --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    aws iam attach-role-policy --role-name ${INSTANCE_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
    
    # Create instance profile
    aws iam create-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} 2>/dev/null || true
    aws iam add-role-to-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} --role-name ${INSTANCE_ROLE_NAME} 2>/dev/null || true
fi

echo "⏳ Waiting for roles to propagate..."
sleep 15

# Verify roles exist
echo "🔍 Verifying IAM roles..."
aws iam get-role --role-name ecsInfrastructureRole --region ${AWS_REGION} >/dev/null 2>&1 && echo "✅ Infrastructure role exists" || echo "❌ Infrastructure role missing"
aws iam get-role --role-name ecsInstanceRole-${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null 2>&1 && echo "✅ Instance role exists" || echo "❌ Instance role missing"
aws iam get-instance-profile --instance-profile-name ecsInstanceProfile-${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null 2>&1 && echo "✅ Instance profile exists" || echo "❌ Instance profile missing"
echo ""

# Step 2: Get VPC and network configuration
echo "🌐 Step 2: Getting VPC and network configuration..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region ${AWS_REGION})
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[].SubnetId' --output text --region ${AWS_REGION})
SUBNET_ARRAY=(${SUBNET_IDS})

# Create security groups
echo "🔒 Creating security groups..."

# ALB Security Group
ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SERVICE_NAME}-alb-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${AWS_REGION} 2>/dev/null)
if [ "$ALB_SG_ID" == "None" ] || [ -z "$ALB_SG_ID" ]; then
    ALB_SG_ID=$(aws ec2 create-security-group --group-name ${SERVICE_NAME}-alb-sg --description "ALB Security group for ${SERVICE_NAME}" --vpc-id ${VPC_ID} --region ${AWS_REGION} --query 'GroupId' --output text)
    # Allow HTTP traffic from internet to ALB
    aws ec2 authorize-security-group-ingress --group-id ${ALB_SG_ID} --protocol tcp --port 80 --cidr 0.0.0.0/0 --region ${AWS_REGION}
    echo "✅ ALB security group created: ${ALB_SG_ID}"
fi

# ECS Service Security Group
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SERVICE_NAME}-sg" --query 'SecurityGroups[0].GroupId' --output text --region ${AWS_REGION} 2>/dev/null)
if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 create-security-group --group-name ${SERVICE_NAME}-sg --description "ECS Service security group for ${SERVICE_NAME}" --vpc-id ${VPC_ID} --region ${AWS_REGION} --query 'GroupId' --output text)
    # Allow traffic from ALB to ECS service on port 9000
    aws ec2 authorize-security-group-ingress --group-id ${SG_ID} --protocol tcp --port 9000 --source-group ${ALB_SG_ID} --region ${AWS_REGION}
    echo "✅ ECS service security group created: ${SG_ID}"
fi

# Create Application Load Balancer
echo "⚖️  Creating Application Load Balancer..."
ALB_NAME="${SERVICE_NAME}-alb"
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

# Create Target Group
echo "🎯 Creating Target Group..."
TG_NAME="${SERVICE_NAME}-tg"
TG_ARN=$(aws elbv2 describe-target-groups --names ${TG_NAME} --query 'TargetGroups[0].TargetGroupArn' --output text --region ${AWS_REGION} 2>/dev/null)

if [ "$TG_ARN" == "None" ] || [ -z "$TG_ARN" ]; then
    TG_ARN=$(aws elbv2 create-target-group \
        --name ${TG_NAME} \
        --protocol HTTP \
        --port 9000 \
        --vpc-id ${VPC_ID} \
        --target-type ip \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region ${AWS_REGION} \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    echo "✅ Target Group created: ${TG_ARN}"
else
    echo "✅ Using existing Target Group: ${TG_ARN}"
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

# Step 3: Create ECS cluster
echo "📦 Step 3: Creating ECS cluster..."
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} --query 'clusters[0].status' --output text 2>/dev/null)
if [ "$CLUSTER_EXISTS" != "ACTIVE" ]; then
    aws ecs create-cluster --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION}
    echo "✅ Cluster created: ${CLUSTER_NAME}"
else
    echo "✅ Using existing cluster: ${CLUSTER_NAME}"
fi

# Step 4: Create Managed Instances capacity provider
echo "🖥️  Step 4: Creating ECS Managed Instances capacity provider..."
CP_EXISTS=$(aws ecs describe-capacity-providers --capacity-providers ${CAPACITY_PROVIDER_NAME} --region ${AWS_REGION} --query 'capacityProviders[0].name' --output text 2>/dev/null)

if [ "$CP_EXISTS" != "${CAPACITY_PROVIDER_NAME}" ]; then
    echo "🆕 Creating Managed Instances capacity provider..."
    
    # Validate required variables
    echo "🔍 Validating configuration..."
    echo "   Cluster: ${CLUSTER_NAME}"
    echo "   Capacity Provider: ${CAPACITY_PROVIDER_NAME}"
    echo "   Infrastructure Role: ${INFRA_ROLE_ARN}"
    echo "   Instance Profile: ${INSTANCE_PROFILE_NAME}"
    echo "   Subnets: ${SUBNET_ARRAY[0]}, ${SUBNET_ARRAY[1]}"
    echo "   Security Group: ${SG_ID}"
    echo ""
    
    # Create JSON configuration for managed instances capacity provider
    cat > /tmp/managed-instances-cp.json <<EOF
{
    "name": "${CAPACITY_PROVIDER_NAME}",
    "managedInstancesProvider": {
        "infrastructureRoleArn": "${INFRA_ROLE_ARN}",
        "instanceLaunchTemplate": {
            "ec2InstanceProfileArn": "arn:aws:iam::${AWS_ACCOUNT_NUMBER}:instance-profile/${INSTANCE_PROFILE_NAME}",
            "networkConfiguration": {
                "subnets": [
                    "${SUBNET_ARRAY[0]}",
                    "${SUBNET_ARRAY[1]}"
                ],
                "securityGroups": [
                    "${SG_ID}"
                ]
            },
            "storageConfiguration": {
                "storageSizeGiB": 100
            },
            "monitoring": "BASIC"
        }
    }
}
EOF
    
    # Debug: Show the JSON configuration
    echo "📋 Capacity provider configuration:"
    cat /tmp/managed-instances-cp.json
    echo ""
    
    # Create capacity provider using JSON file with cluster parameter
    echo "🔧 Creating capacity provider..."
    aws ecs create-capacity-provider \
        --cluster ${CLUSTER_NAME} \
        --cli-input-json file:///tmp/managed-instances-cp.json \
        --region ${AWS_REGION}
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create managed instances capacity provider"
        echo "💡 Check the JSON configuration above for any issues"
        exit 1
    fi
    
    echo "✅ Managed Instances capacity provider created: ${CAPACITY_PROVIDER_NAME}"
else
    echo "✅ Using existing capacity provider: ${CAPACITY_PROVIDER_NAME}"
fi

# Step 5: Configure cluster capacity provider strategy
echo "⚙️  Step 5: Configuring cluster capacity provider strategy..."

# Create JSON configuration for cluster capacity provider strategy
cat > /tmp/cluster-cp-strategy.json <<EOF
{
    "cluster": "${CLUSTER_NAME}",
    "capacityProviders": ["${CAPACITY_PROVIDER_NAME}"],
    "defaultCapacityProviderStrategy": [
        {
            "capacityProvider": "${CAPACITY_PROVIDER_NAME}",
            "weight": 1
        }
    ]
}
EOF

# Configure cluster capacity provider strategy
aws ecs put-cluster-capacity-providers --cli-input-json file:///tmp/cluster-cp-strategy.json --region ${AWS_REGION}

echo "✅ Cluster capacity provider strategy configured"

# Step 7: Create CloudWatch log group
echo "📝 Step 7: Creating CloudWatch log group..."
aws logs create-log-group --log-group-name /ecs/${TASK_FAMILY} --region ${AWS_REGION} 2>/dev/null || true

# Step 6: Register task definition with MANAGED_INSTANCES compatibility
echo "📋 Step 6: Registering ECS task definition..."

# Create JSON configuration for task definition
cat > /tmp/managed-instances-task.json <<EOF
{
    "family": "${TASK_FAMILY}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["MANAGED_INSTANCES"],
    "cpu": "512",
    "memory": "1024",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "clean-architecture",
            "image": "${IMAGE_URI}",
            "portMappings": [
                {
                    "containerPort": 9000,
                    "hostPort": 9000,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "environment": [
                {
                    "name": "PYTHONUNBUFFERED",
                    "value": "1"
                }
            ],
            "healthCheck": {
                "command": [
                    "CMD-SHELL",
                    "curl -f http://localhost:9000/health || exit 1"
                ],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/${TASK_FAMILY}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            }
        }
    ]
}
EOF

# Register task definition using JSON file
TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json file:///tmp/managed-instances-task.json --region ${AWS_REGION} --query 'taskDefinition.taskDefinitionArn' --output text)

if [ $? -ne 0 ]; then
    echo "❌ Failed to register task definition"
    exit 1
fi

echo "✅ Task definition registered: ${TASK_DEF_ARN}"

# Step 8: Create or update ECS service
echo "🔍 Step 8: Creating/updating ECS service..."
SERVICE_EXISTS=$(aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION} --query 'services[0].status' --output text 2>/dev/null)

if [ "$SERVICE_EXISTS" == "ACTIVE" ]; then
    echo "🔄 Updating existing service..."
    aws ecs update-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --task-definition ${TASK_DEF_ARN} \
        --desired-count ${DESIRED_COUNT} \
        --region ${AWS_REGION}
else
    echo "🆕 Creating new service with managed instances and load balancer..."
    aws ecs create-service \
        --cluster ${CLUSTER_NAME} \
        --service-name ${SERVICE_NAME} \
        --task-definition ${TASK_DEF_ARN} \
        --desired-count ${DESIRED_COUNT} \
        --load-balancers targetGroupArn=${TG_ARN},containerName=clean-architecture,containerPort=9000 \
        --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ARRAY[0]},${SUBNET_ARRAY[1]}],securityGroups=[${SG_ID}]}" \
        --region ${AWS_REGION}
fi

if [ $? -ne 0 ]; then
    echo "❌ Failed to create/update ECS service"
    exit 1
fi

echo ""
echo "✅ ECS deployment with Managed Instances completed!"
echo "📍 Cluster: ${CLUSTER_NAME}"
echo "📍 Service: ${SERVICE_NAME}"
echo "📍 Task Definition: ${TASK_DEF_ARN}"
echo "📍 Capacity Provider: ${CAPACITY_PROVIDER_NAME}"
echo "📍 Load Balancer: ${ALB_NAME}"
echo "📍 Target Group: ${TG_NAME}"
echo ""
echo "🌐 Access your application:"
echo "   http://${ALB_DNS}"
echo "   http://${ALB_DNS}/health"
echo "   http://${ALB_DNS}/users"
echo ""
echo "💡 Useful commands:"
echo "   aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}"
echo "   aws elbv2 describe-load-balancers --load-balancer-arns ${ALB_ARN} --region ${AWS_REGION}"
echo "   aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION}"
echo "   aws logs tail /ecs/${TASK_FAMILY} --follow --region ${AWS_REGION}"