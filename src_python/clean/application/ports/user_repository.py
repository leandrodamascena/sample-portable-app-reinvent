from abc import ABC, abstractmethod
from typing import List, Optional
from domain.user import User


class UserRepository(ABC):
    """Interface for user persistence operations"""

    @abstractmethod
    async def create(self, user: User) -> None:
        """Create a new user"""
        pass

    @abstractmethod
    async def find_by_id(self, id: str) -> Optional[User]:
        """Find user by ID"""
        pass

    @abstractmethod
    async def find_all(self) -> List[User]:
        """Get all users"""
        pass

    @abstractmethod
    async def delete(self, id: str) -> None:
        """Delete user by ID"""
        pass
