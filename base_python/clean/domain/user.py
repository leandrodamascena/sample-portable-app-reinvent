import re
from typing import Dict


class User:
    """User entity with business rules"""

    def __init__(self, id: str, name: str, email: str):
        self.id = id
        self.name = name
        self.email = email
        self._validate()

    def _validate(self) -> None:
        """Validate user data"""
        if not self.id:
            raise ValueError("User ID is required")

        if not self.name or len(self.name.strip()) < 2:
            raise ValueError("Name must be at least 2 characters long")

        if not self._is_valid_email():
            raise ValueError("Invalid email format")

    def _is_valid_email(self) -> bool:
        """Check if email is valid"""
        email_regex = r"^[^\s@]+@[^\s@]+\.[^\s@]+$"
        return re.match(email_regex, self.email) is not None

    def to_dict(self) -> Dict:
        """Convert user to dictionary"""
        return {"id": self.id, "name": self.name, "email": self.email}
