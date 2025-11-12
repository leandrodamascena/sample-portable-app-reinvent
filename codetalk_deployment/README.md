# Clean Architecture App Deployment Scripts

This directory contains deployment scripts for the clean architecture Python application to various AWS services: ECS, EKS, and Lambda.

## Prerequisites

- AWS CLI installed and configured
- Docker installed and running (with buildx support for cross-platform builds)
- kubectl installed (for EKS deployment)
- Appropriate AWS permissions for the services you want to deploy to

**Note for Apple Silicon (M1/M2/M3) Macs**: The scripts automatically build for `linux/amd64` architecture using Docker buildx to ensure compatibility with AWS services. Docker buildx is included with Docker Desktop by default.

## Environment Variables

Set these environment variables before running the scripts:

```bash
export AWS_ACCOUNT_NUMBER="123456789012"  # Your AWS account number
export AWS_REGION="us-east-1"             # Your preferred AWS region
```

## Quick Start

For the fastest deployment experience:

```bash
# From the codetalk_deployment directory:
cd codetalk_deployment

# Deploy to all services (ECS, EKS, and Lambda)
./deploy-all.sh

# Or deploy to specific services
./deploy-all.sh ecs    # ECS only
./deploy-all.sh eks    # EKS only  
./deploy-all.sh lambda # Lambda only
```

**Alternative**: You can also run from the workspace root:
```bash
# From workspace root:
codetalk_deployment/deploy-all.sh
```

The `deploy-all.sh` script automatically:
1. Builds and pushes the Docker image to ECR
2. Sets the IMAGE_URI automatically 
3. Deploys to your chosen service(s)

**No manual IMAGE_URI export needed!** 🎉

## 1. Build and Push Docker Image

First, build and push the Docker image to Amazon ECR:

```bash
# From codetalk_deployment directory:
./build-and-push.sh

# Or from workspace root:
codetalk_deployment/build-and-push.sh
```

This script will:
- Create an ECR repository if it doesn't exist
- Build the Docker image using the Dockerfile
- Tag and push the image to ECR
- **Automatically export IMAGE_URI** and save it for other scripts to use

The IMAGE_URI is automatically set and saved to `.image_uri` file. No manual export needed!

**Note**: Individual deployment scripts (in `ecs/`, `eks/`, `lambda/` directories) will automatically load the IMAGE_URI if you've run the build script first. If not, they'll provide helpful instructions.

## 2. Deploy to ECS (Managed Instances)

Deploy the containerized application to Amazon ECS with the new ECS Managed Instances feature:

```bash
cd ecs
./deploy-ecs.sh
```

This script follows the official AWS documentation and will:
- **Create IAM Roles**: Infrastructure role, task execution role, and instance profile
- **Create ECS Cluster**: Standard ECS cluster to host managed instances
- **Create Managed Instances Capacity Provider**: With proper configuration including:
  - Infrastructure role ARN for ECS to manage instances
  - Instance profile with ecsInstanceRole for container agent permissions
  - Network configuration (subnets and security groups)
  - Storage configuration (100GB storage)
  - Basic monitoring enabled
- **Configure Cluster Strategy**: Set managed instances as cluster's default capacity provider
- **Register Task Definition**: With `"requiresCompatibilities": ["MANAGED_INSTANCES"]`
- **Create ECS Service**: Using the managed instances capacity provider

## 3. Deploy to EKS (Auto Mode)

Deploy the application to Amazon EKS with Auto Mode. This is split into two steps due to the ~15 minute cluster creation time:

### Option A: Automatic (Recommended)
```bash
cd eks
./deploy-eks.sh  # Automatically creates cluster if needed
```

### Option B: Manual (For Better Control)
```bash
cd eks
# Step 1: Create cluster (takes ~15 minutes)
./create-cluster.sh

# Step 2: Deploy application (takes ~2 minutes)
./deploy-eks.sh
```

**Cluster Creation Script** (`create-cluster.sh`) will:
- **Create IAM Roles**: Cluster role with all Auto Mode policies, Node role with minimal policies
- **Create EKS Auto Mode Cluster**: With proper configuration including:
  - Kubernetes version 1.31
  - VPC subnets (uses default VPC)
  - Compute automation with "general-purpose" and "system" node pools
  - Elastic load balancing automation enabled
  - Block storage automation enabled
  - Authentication mode set to "API"
  - Both public and private endpoint access

**Deployment Script** (`deploy-eks.sh`) will:
- Verify cluster is active and accessible
- Update kubeconfig for kubectl access
- Deploy application using Kubernetes manifests (nodes created automatically on-demand)
- Wait for Auto Mode to provision nodes for pending pods
- Create LoadBalancer service for external access
- Set up health checks and resource limits

**Note**: In Auto Mode, nodes are created automatically when pods are scheduled and go into pending status. No pre-existing nodes are required!

## 4. Deploy to Lambda

Deploy the application to AWS Lambda:

```bash
cd lambda
./deploy-lambda.sh
```

This script will **automatically**:
- **Build Lambda-optimized image** using the Lambda base image and proper entry point
- **Create Lambda ECR repository** for the Lambda-specific image
- **Push Lambda image** to its own ECR repository
- **Create necessary IAM roles** for Lambda execution
- **Create or update Lambda function** using the Lambda-optimized container image
- **Configure function URL with AWS_IAM authentication** for secure access
- **Set up appropriate timeout and memory settings**

### Accessing Lambda Function with IAM Authentication

The Lambda function uses **AWS_IAM authentication** by default for security. To access it:

**Recommended: Use awscurl for testing:**
```bash
# Install awscurl
pip install awscurl

# Make signed requests
awscurl --service lambda --region us-west-2 'https://your-function-url/health'
```

**For Applications:**
Use AWS SDK with your credentials to make signed requests to the function URL.

**For Quick Testing Only:**
```bash
cd lambda
./toggle-auth.sh NONE    # Temporarily disable auth
# Test in browser, then:
./toggle-auth.sh AWS_IAM # Re-enable security
```

**Note**: Lambda deployment is completely self-contained and builds its own optimized image. No need to run the main build script first!

## Application Endpoints

Once deployed, the application exposes these endpoints:

- `GET /health` - Health check
- `POST /users` - Create user
- `GET /users` - Get all users
- `GET /users/{id}` - Get user by ID
- `DELETE /users/{id}` - Delete user
- `POST /orders` - Create order
- `GET /orders` - Get all orders
- `GET /orders/{id}` - Get order by ID
- `DELETE /orders/{id}` - Delete order

## Customization

You can customize the deployment by setting additional environment variables:

### ECS Deployment
```bash
export CLUSTER_NAME="my-cluster"
export SERVICE_NAME="my-service"
export DESIRED_COUNT="3"
export INSTANCE_TYPE="m5.large"  # Instance type for managed instances (minimum m5.large recommended)
export CAPACITY_PROVIDER_NAME="my-cluster-managed-instances"  # Optional: custom capacity provider name
```

### EKS Deployment
```bash
export CLUSTER_NAME="my-eks-cluster"
export NAMESPACE="my-namespace"
export KUBERNETES_VERSION="1.31"  # Kubernetes version for Auto Mode
```

### Lambda Deployment
```bash
export FUNCTION_NAME="my-lambda-function"
export ROLE_NAME="my-lambda-role"
```

## Monitoring and Troubleshooting

### ECS
```bash
# Check service status
aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}

# Check capacity provider status
aws ecs describe-capacity-providers --capacity-providers ${CLUSTER_NAME}-managed-instances

# List container instances
aws ecs list-container-instances --cluster ${CLUSTER_NAME}

# View container instance details
aws ecs describe-container-instances --cluster ${CLUSTER_NAME} --container-instances $(aws ecs list-container-instances --cluster ${CLUSTER_NAME} --query 'containerInstanceArns[0]' --output text)

# View logs
aws logs tail /ecs/${TASK_FAMILY} --follow
```

### EKS
```bash
# Check cluster status
aws eks describe-cluster --name clean-architecture-eks --region ${AWS_REGION}

# Check nodes (Auto Mode node pools)
kubectl get nodes -o wide

# Check pods
kubectl get pods

# View logs
kubectl logs -l app=clean-architecture-app

# Get service URL
kubectl get service clean-architecture-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check node pools and compute resources
kubectl get pods -A  # See all system pods
```

### Lambda
```bash
# Invoke function
aws lambda invoke --function-name ${FUNCTION_NAME} --payload '{}' response.json

# View logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow
```

## Cleanup

**Quick Cleanup (Recommended):**

```bash
# Clean up all services
./cleanup-all.sh

# Or clean up specific services
./cleanup-all.sh ecs    # ECS only
./cleanup-all.sh eks    # EKS only  
./cleanup-all.sh lambda # Lambda only
```

**Manual Cleanup:**

To clean up resources manually:

### ECS
```bash
# Scale down service
aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --desired-count 0

# Delete service
aws ecs delete-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME}

# Delete capacity provider
aws ecs delete-capacity-provider --capacity-provider ${CLUSTER_NAME}-managed-instances

# Delete cluster
aws ecs delete-cluster --cluster ${CLUSTER_NAME}

# Clean up IAM roles (optional)
aws iam remove-role-from-instance-profile --instance-profile-name ecsInstanceProfile-${CLUSTER_NAME} --role-name ecsInstanceRole-${CLUSTER_NAME}
aws iam delete-instance-profile --instance-profile-name ecsInstanceProfile-${CLUSTER_NAME}
aws iam detach-role-policy --role-name ecsInstanceRole-${CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
aws iam delete-role --role-name ecsInstanceRole-${CLUSTER_NAME}
```

### EKS
```bash
# Delete application
kubectl delete deployment clean-architecture-app
kubectl delete service clean-architecture-app-service

# Delete cluster (this also cleans up Auto Mode resources)
aws eks delete-cluster --name clean-architecture-eks

# Clean up IAM roles (optional)
aws iam detach-role-policy --role-name eksClusterRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam detach-role-policy --role-name eksClusterRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEKSComputePolicy
aws iam detach-role-policy --role-name eksClusterRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy
aws iam detach-role-policy --role-name eksClusterRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy
aws iam detach-role-policy --role-name eksClusterRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy
aws iam delete-role --role-name eksClusterRole-clean-architecture-eks

aws iam detach-role-policy --role-name eksNodeRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy
aws iam detach-role-policy --role-name eksNodeRole-clean-architecture-eks --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly
aws iam delete-role --role-name eksNodeRole-clean-architecture-eks
```

## Cleanup Scripts Details

The cleanup scripts provide comprehensive resource cleanup with safety prompts:

### `cleanup-all.sh`
- **Safety confirmation** before deletion
- **Selective cleanup** (all, ecs, eks, lambda)
- **ECR repository cleanup** (when cleaning all)
- **Temporary files cleanup**

### Individual Service Cleanup:
- **`ecs/cleanup-ecs.sh`**: Services → Capacity Providers → Clusters → Task Definitions → Logs → Security Groups → IAM Roles
- **`eks/cleanup-eks.sh`**: Applications → Clusters → IAM Roles → Kubeconfig entries
- **`lambda/cleanup-lambda.sh`**: Function URLs → Functions → Log Groups → IAM Roles

### Safety Features:
- ✅ **Confirmation prompts** for destructive operations
- ✅ **Graceful handling** of missing resources
- ✅ **Optional IAM cleanup** (asks before deleting roles)
- ✅ **Progress feedback** with clear status messages
- ✅ **Error handling** continues cleanup even if some resources fail

### Lambda
```bash
aws lambda delete-function --function-name ${FUNCTION_NAME}
```

## Notes

- The ECS deployment uses the new **ECS Managed Instances** feature where AWS fully manages the EC2 instances for you
- ECS Managed Instances automatically handle instance provisioning, patching, and scaling without requiring Auto Scaling Groups or launch templates
- The ECS setup uses awsvpc networking mode for better security and network isolation
- The EKS deployment uses Auto Mode for simplified cluster management
- The Lambda deployment includes function URLs for easy HTTP access
- All deployments include health checks and proper logging configuration
- Security groups and IAM roles are created automatically with minimal required permissions
- ECS Managed Instances provide a serverless-like experience while running on EC2 instances
- The managed instances will automatically scale based on task demand and AWS handles all the underlying infrastructure