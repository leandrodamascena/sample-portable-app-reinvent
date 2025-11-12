from fastapi import HTTPException
from help_dynamodb import save_to_dynamodb, get_from_dynamodb


def save_user(data: dict):
    save_to_dynamodb("Users", data)
    return data


def get_user(user_id: str):
    user = get_from_dynamodb("Users", {"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user
