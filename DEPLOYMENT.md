# Deployment Information

## Public URL

https://day14-agent-f7qk.onrender.com

> Service dùng gói **free** của Render nên ngủ khi không có request. Request đầu tiên sau đó có thể chậm khoảng 1 phút, hãy chờ rồi thử lại.

## Platform

Render, deploy bằng Blueprint từ [`06-lab-complete/render.yaml`](06-lab-complete/render.yaml) (Blueprint Path: `06-lab-complete/render.yaml`).

| Service | Loại | Region | Gói |
|---|---|---|---|
| `day14-agent` | Web service, Docker | Singapore | free |
| `day14-redis` | Key Value (dashboard ghi runtime Valkey 8) | Singapore | free |

## Test Commands

Đặt biến trước khi chạy. Key không được ghi trong repo; lấy ở Render Dashboard → `day14-agent` → Environment.

```bash
BASE=https://day14-agent-f7qk.onrender.com
read -rsp "AGENT_API_KEY: " AGENT_API_KEY; echo
```

### Health check

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$BASE/health"     # 200
```

### Readiness (agent kết nối được Redis)

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$BASE/ready"      # 200
```

### Không có API key

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/ask" \
  -H 'Content-Type: application/json' -d '{"question":"Hello"}'   # 401
```

### Có API key

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE/ask" \
  -H 'Content-Type: application/json' -H "X-API-Key: $AGENT_API_KEY" \
  -d '{"question":"Hello"}'                                       # 200
```

Kết quả đã chạy: `200`, `200`, `401`, `200` (ảnh [test.png](screenshots/test.png)).

## Environment Variables Set

| Biến | Giá trị / nguồn |
|---|---|
| `PORT` | Render tự cấp, không đặt trong `render.yaml` |
| `ENVIRONMENT` | `production` |
| `LOG_LEVEL` | `INFO` |
| `RATE_LIMIT_PER_MINUTE` | `10` |
| `DAILY_BUDGET_USD` | `1.0` |
| `REDIS_URL` | Render điền từ connection string của `day14-redis` |
| `AGENT_API_KEY` | Secret đặt trên Render (`generateValue`), không ghi trong code |

## Hạn chế của gói free

- Web service ngủ khi không có request trong một thời gian.
- Key Value free không lưu dữ liệu xuống đĩa: khi nó khởi động lại, số đếm rate limit và tổng chi phí trong ngày bị mất.

## Screenshots

- [Deployment dashboard](screenshots/dashboard.png)
- [Service running](screenshots/running.png)
- [Test results](screenshots/test.png)
