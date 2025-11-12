"""
MONOLITH ARCHITECTURE - Single File Application
================================================

This file demonstrates a monolithic architecture where all business logic,
data access, and API endpoints are tightly coupled in a single application.

Key characteristics:
- All features (Users, Orders) in one codebase
- Shared database access layer
- Single deployment unit
- Tightly coupled components
- Difficult to scale individual features
"""

import boto3
import uvicorn
from typing import Optional
from fastapi import FastAPI, HTTPException
from botocore.exceptions import ClientError


# ============================================================================
# DATABASE LAYER - DynamoDB Helper Functions
# ============================================================================

dynamodb = boto3.resource("dynamodb")


def save_to_dynamodb(table_name: str, data: dict) -> dict:
    """Save data to DynamoDB table"""
    try:
        table = dynamodb.Table(table_name)
        table.put_item(Item=data)
        return data
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_message = e.response["Error"]["Message"]
        raise Exception(f"DynamoDB Error ({error_code}): {error_message}")
    except Exception as e:
        raise Exception(f"Failed to save to DynamoDB: {str(e)}")


def get_from_dynamodb(table_name: str, key: dict) -> Optional[dict]:
    """Get data from DynamoDB table by key"""
    try:
        table = dynamodb.Table(table_name)
        response = table.get_item(Key=key)
        return response.get("Item")
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_message = e.response["Error"]["Message"]
        raise Exception(f"DynamoDB Error ({error_code}): {error_message}")
    except Exception as e:
        raise Exception(f"Failed to get from DynamoDB: {str(e)}")


# ============================================================================
# BUSINESS LOGIC LAYER - User Operations
# ============================================================================

def save_user(data: dict):
    """Save user to database"""
    save_to_dynamodb("Users", data)
    return data


def get_user(user_id: str):
    """Retrieve user from database"""
    user = get_from_dynamodb("Users", {"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


# ============================================================================
# BUSINESS LOGIC LAYER - Order Operations
# ============================================================================

def save_order(data: dict):
    """Save order to database"""
    save_to_dynamodb("Orders", data)
    return data


def get_order(order_id: str):
    """Retrieve order from database"""
    order = get_from_dynamodb("Orders", {"id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


# ============================================================================
# API LAYER - FastAPI Application
# ============================================================================

app = FastAPI(
    title="Monolith Application",
    description="Single-file monolithic architecture demonstration",
    version="1.0.0"
)


# Health check endpoint
@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {"message": "health from monolith"}


# ============================================================================
# USER ENDPOINTS
# ============================================================================

@app.post("/users", status_code=201)
def create_user(data: dict):
    """Create a new user"""
    return save_user(data)


@app.get("/users/{user_id}")
def retrieve_user(user_id: str):
    """Retrieve a user by ID"""
    return get_user(user_id)


# ============================================================================
# ORDER ENDPOINTS
# ============================================================================

@app.post("/orders", status_code=201)
def create_order(data: dict):
    """Create a new order"""
    return save_order(data)


@app.get("/orders/{order_id}")
def retrieve_order(order_id: str):
    """Retrieve an order by ID"""
    return get_order(order_id)


# ============================================================================
# SERVER STARTUP
# ============================================================================

if __name__ == "__main__":
    print("🚀 Starting Monolith Server...")
    print("📡 Server running at http://localhost:9000")
    print("\n📍 Available endpoints:")
    print("  GET    /health       - Health check")
    print("  POST   /users        - Create user")
    print("  GET    /users/{id}   - Get user")
    print("  POST   /orders       - Create order")
    print("  GET    /orders/{id}  - Get order")
    print("\n⚠️  MONOLITH CHARACTERISTICS:")
    print("  ✗ All features tightly coupled")
    print("  ✗ Single deployment unit")
    print("  ✗ Shared database access")
    print("  ✗ Difficult to scale individual features")
    print()

    uvicorn.run(app, host="0.0.0.0", port=9000)
