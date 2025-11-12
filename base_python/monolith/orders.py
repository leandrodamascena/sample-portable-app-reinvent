from fastapi import HTTPException
from help_dynamodb import save_to_dynamodb, get_from_dynamodb


def save_order(data: dict):
    save_to_dynamodb("Orders", data)
    return data


def get_order(order_id: str):
    order = get_from_dynamodb("Orders", {"id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order
