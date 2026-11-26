"""
Production AI Agent — Part 6 Final Project

Luồng của POST /ask:
    API key (401) → rate limit (429) → budget (402) → gọi LLM → ghi chi phí

Chạy:      AGENT_API_KEY=<key> uvicorn app.main:app
Kiểm tra:  python check_production_ready.py
"""
import json
import logging
import signal
import sys
import threading
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import redis
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from app.auth import verify_api_key
from app.config import settings
from app.cost_guard import check_budget, estimate_tokens, record_cost
from app.rate_limiter import check_rate_limit
from app.redis_client import r, redis_healthy
from utils.mock_llm import ask as llm_ask


# ── Structured logging ───────────────────────────────────
class JsonFormatter(logging.Formatter):
    """Mỗi bản ghi log thành đúng 1 dòng JSON."""

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "event": record.getMessage(),
        }
        entry.update(getattr(record, "fields", {}))
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        # json.dumps cho CẢ bản ghi nên dấu " và xuống dòng được escape đúng
        return json.dumps(entry, ensure_ascii=False, default=str)


_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(JsonFormatter())
# force=True: cấu hình vẫn có hiệu lực kể cả khi trước đó đã có lệnh gọi logging
logging.basicConfig(level=settings.log_level, handlers=[_handler], force=True)
logger = logging.getLogger("agent")


def log(event: str, level: int = logging.INFO, **fields) -> None:
    logger.log(level, event, extra={"fields": fields})


# ── Vòng đời và graceful shutdown ────────────────────────
shutting_down = threading.Event()


def install_sigterm_handler() -> None:
    """Ghi log và đánh dấu khi nhận SIGTERM, rồi chuyển tiếp cho handler của uvicorn."""
    if threading.current_thread() is not threading.main_thread():
        return  # signal.signal chỉ gọi được từ main thread
    previous = signal.getsignal(signal.SIGTERM)
    if not callable(previous):
        return  # không có handler để chuyển tiếp: giữ nguyên hành vi mặc định

    def on_sigterm(signum, frame):
        shutting_down.set()
        log("sigterm_received")
        previous(signum, frame)  # uvicorn ngừng nhận request mới và chờ request đang chạy

    signal.signal(signal.SIGTERM, on_sigterm)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Chạy sau khi uvicorn đã đăng ký handler của nó, nên chuyển tiếp được
    install_sigterm_handler()
    if not settings.agent_api_key:
        log("agent_api_key_missing", logging.WARNING, effect="every /ask request returns 401")
    log("startup", environment=settings.environment)
    yield
    # Tới đây uvicorn đã xử lý xong các request đang chạy
    r.close()
    log("shutdown_complete")


app = FastAPI(title="Production AI Agent", lifespan=lifespan)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    started = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        # Không log header, body hay query string: tránh lộ key và dữ liệu người dùng
        log(
            "request",
            method=request.method,
            path=request.url.path,
            status=status,
            ms=round((time.perf_counter() - started) * 1000, 1),
        )


# ── Xử lý lỗi: trả thông báo rõ ràng, không lộ stack trace ─
@app.exception_handler(redis.RedisError)
async def redis_error_handler(request: Request, exc: redis.RedisError):
    log("redis_error", logging.ERROR, error=type(exc).__name__)
    return JSONResponse(status_code=503, content={"detail": "Service temporarily unavailable"})


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception):
    logger.error("unhandled_error", exc_info=exc)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


# ── Endpoints ────────────────────────────────────────────
class AskRequest(BaseModel):
    # Cắt khoảng trắng trước khi kiểm tra độ dài: câu hỏi toàn dấu cách bị từ chối
    model_config = ConfigDict(str_strip_whitespace=True)

    question: str = Field(..., min_length=1, max_length=2000)


@app.get("/health")
def health():
    """Liveness: process còn chạy là 200. Cố ý KHÔNG kiểm tra Redis."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """Readiness: 503 khi đang tắt hoặc không kết nối được Redis."""
    if shutting_down.is_set():
        raise HTTPException(status_code=503, detail="Shutting down")
    if not redis_healthy():
        raise HTTPException(status_code=503, detail="Redis is not available")
    return {"status": "ready"}


# `def` (không async): FastAPI chạy trong threadpool nên lệnh chặn không treo event loop
@app.post("/ask")
def ask(body: AskRequest, api_key: str = Depends(verify_api_key)):
    check_rate_limit(api_key)
    check_budget()
    answer = llm_ask(body.question)
    cost = record_cost(estimate_tokens(body.question), estimate_tokens(answer))
    log("ask_completed", question_chars=len(body.question), cost_usd=round(cost, 8))
    return {"question": body.question, "answer": answer}
