import boto3
from typing import Optional
from botocore.exceptions import ClientError

# DynamoDB client
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
