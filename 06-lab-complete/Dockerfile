# ── Stage 1: builder — cài dependencies ──────────────────
FROM python:3.11-slim AS builder

WORKDIR /build
# Copy requirements trước code: sửa code thì layer pip install vẫn dùng lại cache
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime — chỉ chứa thứ cần để chạy ──────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --system app && useradd --system --gid app --no-create-home app

WORKDIR /app
# Cài vào /usr/local nên user non-root tìm thấy package, không cần PYTHONUSERBASE
COPY --from=builder /install /usr/local
COPY app/ ./app/
COPY utils/ ./utils/

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.getenv('PORT', '8000'), timeout=3)" || exit 1

# `exec` để uvicorn thay thế sh và làm PID 1, nhờ đó nhận được SIGTERM từ `docker stop`.
# Tắt access log của uvicorn vì app đã tự log mỗi request dạng JSON.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 2 --timeout-graceful-shutdown 8 --no-access-log"]
