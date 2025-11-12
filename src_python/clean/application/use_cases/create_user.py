import uuid
from typing import Dict, Any
from domain.user import User
from application.ports.user_repository import UserRepository


class CreateUserUseCase:
    """Use case for creating users"""

    def __init__(self, user_repository: UserRepository):
        self._user_repository = user_repository

    async def execute(self, input_data: Dict[str, Any]) -> User:
        """Execute user creation"""
        name = input_data.get("name")
        email = input_data.get("email")

        user_id = str(uuid.uuid4())
        user = User(user_id, name, email)

        await self._user_repository.create(user)
        return user
