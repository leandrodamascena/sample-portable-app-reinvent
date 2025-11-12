from application.ports.user_repository import UserRepository


class DeleteUserUseCase:
    """Use case for deleting users"""

    def __init__(self, user_repository: UserRepository):
        self._user_repository = user_repository

    async def execute(self, id: str) -> None:
        """Execute user deletion"""
        user = await self._user_repository.find_by_id(id)

        if not user:
            raise ValueError("User not found")

        await self._user_repository.delete(id)
