"""
Rate limiting — sliding window 60 giây bằng Redis sorted set.

Mỗi request được lưu thành một phần tử, score = thời điểm gọi. State nằm trong
Redis nên mọi worker / instance dùng chung và vẫn còn sau khi restart agent.
"""
import hashlib
import uuid

from fastapi import HTTPException

from app.config import settings
from app.redis_client import r

WINDOW_SECONDS = 60

# Lua script chạy nguyên khối trong Redis: không request nào chen được vào giữa
# bước đếm và bước ghi. Trả về 0 nếu được phép, ngược lại là số giây cần chờ.
_SLIDING_WINDOW = """
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000000 + tonumber(t[2])
local window = tonumber(ARGV[1]) * 1000000
local limit = tonumber(ARGV[2])

redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now - window)

if redis.call('ZCARD', KEYS[1]) >= limit then
  local oldest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
  if oldest[2] then
    return math.ceil((tonumber(oldest[2]) + window - now) / 1000000)
  end
  return tonumber(ARGV[1])
end

redis.call('ZADD', KEYS[1], now, ARGV[3])
redis.call('EXPIRE', KEYS[1], ARGV[1])
return 0
"""

_sliding_window = r.register_script(_SLIDING_WINDOW)


def check_rate_limit(key: str) -> None:
    """Vượt RATE_LIMIT_PER_MINUTE request trong 60 giây → HTTP 429."""
    # Không lưu API key gốc vào Redis, chỉ lưu mã băm
    bucket = "ratelimit:" + hashlib.sha256(key.encode()).hexdigest()[:16]
    retry_after = _sliding_window(
        keys=[bucket],
        # uuid4: mỗi phần tử là duy nhất, hai request cùng thời điểm vẫn được đếm đủ
        args=[WINDOW_SECONDS, settings.rate_limit_per_minute, uuid.uuid4().hex],
    )
    if retry_after:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded",
            headers={"Retry-After": str(max(1, int(retry_after)))},
        )
