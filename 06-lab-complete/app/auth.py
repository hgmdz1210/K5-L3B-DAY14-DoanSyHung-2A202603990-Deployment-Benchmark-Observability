"""
API Key authentication.

  • Client gửi header  X-API-Key: <key>
  • Key phải trùng biến môi trường AGENT_API_KEY
  • Thiếu hoặc sai key → HTTP 401
"""
import secrets

from fastapi import HTTPException, Security
from fastapi.security.api_key import APIKeyHeader

from app.config import settings

# auto_error=False: tự trả 401 thay vì để FastAPI trả mã mặc định khi thiếu header
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def verify_api_key(api_key: str | None = Security(api_key_header)) -> str:
    """Dependency cho FastAPI — dùng trong /ask: Depends(verify_api_key)."""
    expected = settings.agent_api_key
    # compare_digest so sánh với thời gian không đổi, tránh đoán key qua thời gian phản hồi.
    # `not expected`: server chưa cấu hình key thì từ chối tất cả.
    if (
        not expected
        or not api_key
        or not secrets.compare_digest(api_key.encode(), expected.encode())
    ):
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return api_key
