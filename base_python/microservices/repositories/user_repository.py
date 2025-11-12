from abc import ABC, abstractmethod
from typing import List, Optional
import logging
from ..models.user import User

logger = logging.getLogger(__name__)

class UserRepository(ABC):
    """Abstract base class for user repositories"""
    
    @abstractmethod
    async def create(self, user: User) -> User:
        """Create a new user"""
        pass
    
    @abstractmethod
    async def find_by_id(self, user_id: str) -> Optional[User]:
        """Find user by ID"""
        pass
    
    @abstractmethod
    async def find_all(self) -> List[User]:
        """Find all users"""
        pass
    
    @abstractmethod
    async def delete(self, user_id: str) -> bool:
        """Delete user by ID. Returns True if deleted, False if not found"""
        pass
    
    @abstractmethod
    def clear(self) -> None:
        """Clear all users (for testing)"""
        pass

class InMemoryUserRepository(UserRepository):
    """In-memory implementation of UserRepository"""
    
    def __init__(self):
        self._users: List[User] = []
    
    async def create(self, user: User) -> User:
        """Create a new user"""
        logger.info(f'Attempting to create user: {user.id}')
        self._users.append(user)
        logger.info(f'User created successfully. Total users: {len(self._users)}')
        logger.info(f'User persisted successfully: {user.id}')
        return user
    
    async def find_by_id(self, user_id: str) -> Optional[User]:
        """Find user by ID"""
        logger.info(f'Finding user by id: {user_id}')
        user = next((u for u in self._users if u.id == user_id), None)
        
        if user:
            logger.info(f'User found: {user_id}')
        else:
            logger.info(f'User not found: {user_id}')
        
        return user
    
    async def find_all(self) -> List[User]:
        """Find all users"""
        logger.info('Retrieving all users')
        logger.info(f'Retrieved users count: {len(self._users)}')
        return self._users.copy()
    
    async def delete(self, user_id: str) -> bool:
        """Delete user by ID"""
        logger.info(f'Finding user by id: {user_id}')
        
        for i, user in enumerate(self._users):
            if user.id == user_id:
                logger.info(f'User found: {user_id}')
                logger.info(f'Attempting to delete user: {user_id}')
                self._users.pop(i)
                logger.info(f'User deleted successfully: {user_id}')
                return True
        
        logger.info(f'User not found when attempting to delete: {user_id}')
        return False
    
    def clear(self) -> None:
        """Clear all users (for testing)"""
        self._users.clear()
    
    async def clear(self) -> None:
        """Clear all users (for testing) - async version"""
        self._users.clear()
