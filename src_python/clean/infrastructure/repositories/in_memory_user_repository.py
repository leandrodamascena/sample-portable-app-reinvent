from typing import Dict, List, Optional
from domain.user import User
from application.ports.user_repository import UserRepository


class InMemoryUserRepository(UserRepository):
    """In-memory implementation of UserRepository"""

    def __init__(self):
        self._users: Dict[str, User] = {}

    async def create(self, user: User) -> None:
        """Create a new user"""
        self._users[user.id] = user

    async def find_by_id(self, id: str) -> Optional[User]:
        """Find user by ID"""
        return self._users.get(id)

    async def find_all(self) -> List[User]:
        """Get all users"""
        return list(self._users.values())

    async def delete(self, id: str) -> None:
        """Delete user by ID"""
        if id not in self._users:
            raise ValueError("User not found")
        del self._users[id]
