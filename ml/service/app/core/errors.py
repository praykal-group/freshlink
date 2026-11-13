"""Error type rendered as {"error": {"code", "message", "details"}} by the app's exception handler."""

from typing import Any, Dict, Optional


class MlError(Exception):
    def __init__(self, code: str, message: str, status: int = 400, details: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.details = details or {}
