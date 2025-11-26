from typing import Dict


class Order:
    """Order entity with business rules"""

    def __init__(self, id: str, user_id: str, product: str, quantity: int, status: str = "pending"):
        self.id = id
        self.user_id = user_id
        self.product = product
        self.quantity = quantity
        self.status = status
        self._validate()

    def _validate(self) -> None:
        """Validate order data"""
        if not self.id:
            raise ValueError("Order ID is required")

        if not self.user_id:
            raise ValueError("User ID is required")

        if not self.product or len(self.product.strip()) < 2:
            raise ValueError("Product must be at least 2 characters long")

        if self.quantity <= 0:
            raise ValueError("Quantity must be greater than 0")
        
        if self.status not in ["pending", "completed"]:
            raise ValueError("Status must be either 'pending' or 'completed'")

    def to_dict(self) -> Dict:
        """Convert order to dictionary"""
        return {
            "id": self.id,
            "user_id": self.user_id,
            "product": self.product,
            "quantity": self.quantity,
            "status": self.status,
        }
