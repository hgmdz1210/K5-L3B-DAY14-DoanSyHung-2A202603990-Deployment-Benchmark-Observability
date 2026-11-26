"""
Kết nối Redis dùng chung cho rate limiter và cost guard.

from_url() chỉ tạo client, chưa mở kết nối, nên app vẫn khởi động được
khi Redis chưa sẵn sàng.
"""
import redis

from app.config import settings

r = redis.Redis.from_url(
    settings.redis_url,
    decode_responses=True,
    socket_connect_timeout=2,  # Redis chết thì báo lỗi nhanh, không treo request
    socket_timeout=2,
)


def redis_healthy() -> bool:
    """Dùng cho GET /ready: ping được Redis → True."""
    try:
        return bool(r.ping())
    except redis.RedisError:
        return False
