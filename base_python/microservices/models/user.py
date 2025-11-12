import re
import logging
from typing import Dict

logger = logging.getLogger(__name__)

class User:
    """
    Represents a user entity in the domain.
    Implements business rules and validations related to users.
    """
    
    def __init__(self, id: str, name: str, email: str):
        self.id = id
        self.name = name
        self.email = email
        self._validate()
    
    def _validate(self) -> None:
        """Validate user data"""
        logger.info('Validating user data')
        
        if not self.id:
            raise ValueError('User ID is required')
        
        if not self.name or len(self.name.strip()) < 2:
            raise ValueError('Name must be at least 2 characters long')
        
        logger.info(f'Checking email format: {self.email}')
        if not self.is_valid_email():
            raise ValueError('Invalid email format')
        
        logger.info('User validation completed successfully')
    
    def is_valid_email(self) -> bool:
        """Check if email format is valid"""
        email_regex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$'
        return re.match(email_regex, self.email) is not None
    
    def to_dict(self) -> Dict[str, str]:
        """Convert user to dictionary for JSON serialization"""
        return {
            'id': self.id,
            'name': self.name,
            'email': self.email
        }
