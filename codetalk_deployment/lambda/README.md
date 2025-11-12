# Lambda Deployment

This directory contains all files needed for AWS Lambda deployment of the clean architecture application.

## Files

### Core Deployment Files
- **`deploy-lambda.sh`** - Main deployment script (builds image, creates function, configures URL)
- **`Dockerfile.lambda`** - Lambda-optimized Dockerfile with proper base image and handler
- **`lambda_handler.py`** - Lambda handler that wraps FastAPI app using Mangum

### Access & Management
- **`get-signed-url.sh`** - Access helper with options for AWS_IAM auth
- **`toggle-auth.sh`** - Toggle between AWS_IAM and NONE authentication
- **`cleanup-lambda.sh`** - Clean up all Lambda resources

## Quick Usage

```bash
# Deploy Lambda function (with AWS_IAM auth by default)
./deploy-lambda.sh

# Check access options
./get-signed-url.sh /health

# For testing: temporarily disable auth
./toggle-auth.sh NONE
# Test in browser, then re-enable:
./toggle-auth.sh AWS_IAM

# Clean up resources
./cleanup-lambda.sh
```

## Authentication

The Lambda function uses **AWS_IAM authentication** by default for security. Use `awscurl` for testing or AWS SDK for production applications.