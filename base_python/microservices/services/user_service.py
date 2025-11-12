import uuid
import logging
from typing import List, Dict, Any
from ..models.user import User
from ..repositories.user_repository import UserRepository

logger = logging.getLogger(__name__)

class CreateUserDTO:
    """Data Transfer Object for creating users"""
    
    def __init__(self, name: str, email: str):
        self.name = name
        self.email = email

class UserService:
    """Service layer for user operations"""
    
    def __init__(self, user_repository: UserRepository):
        self._user_repository = user_repository
    
    async def create_user(self, user_data: Dict[str, Any]) -> User:
        """Create a new user"""
        logger.info('Creating new user')
        
        name = user_data.get('name')
        email = user_data.get('email')
        
        logger.info(f'Creating new user with input: name={name}, email={email}')
        
        user_id = str(uuid.uuid4())
        logger.info(f'Generated UUID: {user_id}')
        
        logger.info(f'Creating new User instance with: id={user_id}, name={name}, email={email}')
        user = User(user_id, name, email)
        
        logger.info(f'User instance created successfully: {user_id}')
        logger.info(f'User entity created successfully: {user}')
        
        created_user = await self._user_repository.create(user)
        logger.info(f'User created successfully: {user_id}')
        
        return created_user
    
    async def get_user(self, user_id: str) -> User:
        """Get user by ID"""
        logger.info(f'Retrieving user by id: {user_id}')
        
        user = await self._user_repository.find_by_id(user_id)
        
        if not user:
            raise ValueError('User not found')
        
        return user
    
    async def list_users(self) -> List[User]:
        """List all users"""
        logger.info('Retrieving all users')
        users = await self._user_repository.find_all()
        logger.info(f'Users retrieved successfully. Count: {len(users)}')
        return users
    
    async def delete_user(self, user_id: str) -> None:
        """Delete user by ID"""
        logger.info(f'Checking if user exists: {user_id}')
        
        deleted = await self._user_repository.delete(user_id)
        
        if not deleted:
            raise ValueError('User not found')
