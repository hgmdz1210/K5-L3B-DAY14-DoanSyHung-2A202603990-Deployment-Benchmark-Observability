# Day 14 Lab - Mission Answers

## Part 1: Localhost vs Production

### Exercise 1.1: Anti-patterns found

Số dòng tính theo `01-localhost-vs-production/develop/app.py`.

1. **Dòng 17 — API key ghi cứng trong code.** Ai đọc được repo là lấy được key và gọi API bằng tiền của mình. Xoá ở commit sau vẫn chưa đủ vì key còn trong lịch sử git, phải thu hồi và tạo key mới.
2. **Dòng 18 — Chuỗi kết nối database chứa user và mật khẩu.** Lộ repo là lộ thông tin đăng nhập database. Muốn đổi database giữa laptop và server cũng phải sửa code.
3. **Dòng 21–22 — `DEBUG` và `MAX_TOKENS` ghi cứng.** File có `import os` nhưng không đọc biến môi trường nào. Muốn đổi cấu hình phải sửa code và deploy lại, không đặt khác nhau cho từng môi trường được.
4. **Dòng 33 và 38 — Dùng `print` và in nguyên câu hỏi, câu trả lời.** Log không có thời gian, mức độ, hay cấu trúc cố định nên khó lọc và cảnh báo. Nội dung người dùng gửi có thể chứa dữ liệu riêng tư và bị lưu vào hệ thống log.
5. **Dòng 34 — In API key ra log.** Ai xem được log (đồng nghiệp, dịch vụ gom log) đều thấy key, kể cả khi key không còn nằm trong code.
6. **Dòng 25–39 — Không có health check.** Chỉ có route `/` và `/ask`; gọi `/health` trả 404. Nền tảng không có endpoint chuẩn để biết app còn sống mà restart, hay đã sẵn sàng để nhận traffic.
7. **Dòng 51 — `host="localhost"`.** App chỉ nghe trên loopback. Khi chạy trong container, request từ bên ngoài container không tới được app.
8. **Dòng 52 — Cổng cố định 8000.** Nền tảng như Railway hay Render cấp cổng qua biến `PORT`. App không đọc biến này nên nền tảng có thể không kết nối được tới app.
9. **Dòng 53 — `reload=True`.** Chế độ dành cho lúc viết code: chạy thêm một tiến trình theo dõi file (log hiện `Started reloader process`), tốn tài nguyên và có thể tự khởi động lại khi file thay đổi.
10. **Cả file — Không có code xử lý vòng đời.** Không có `lifespan` để dọn dẹp kết nối hay đánh dấu app chưa sẵn sàng khi tắt. App chỉ dựa vào hành vi mặc định của uvicorn.

### Exercise 1.2: Kết quả chạy bản develop

Chạy `python app.py` trong WSL2 (Python 3.11). Output đã lược bớt header HTTP, key đã được che.

```text
$ curl -i -X POST "http://localhost:8000/ask?question=Hello"
HTTP/1.1 200 OK
{"answer":"Agent đang hoạt động tốt! (mock response) Hỏi thêm câu hỏi đi nhé."}

$ curl -i http://localhost:8000/health
HTTP/1.1 404 Not Found
{"detail":"Not Found"}

$ curl -i -X POST http://localhost:8000/ask -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/1.1 422 Unprocessable Entity
{"detail":[{"type":"missing","loc":["query","question"],"msg":"Field required","input":null}]}
```

Log của server:

```text
INFO:     Started reloader process [1515] using WatchFiles
INFO:     Started server process [1522]
[DEBUG] Got question: Hello
[DEBUG] Using key: sk-***
[DEBUG] Response: Agent đang hoạt động tốt! (mock response) Hỏi thêm câu hỏi đi nhé.
INFO:     127.0.0.1:47822 - "POST /ask?question=Hello HTTP/1.1" 200 OK
```

Nhận xét:

- App chạy được trên máy local nhưng chưa sẵn sàng cho production: không có health check và key bị in ra log.
- `/ask` nhận `question` qua query string, gửi JSON thì bị 422. Câu hỏi nằm trên URL nên cũng xuất hiện trong access log.

### Exercise 1.3: Comparison table

| Feature | Develop | Production | Why Important? |
|---|---|---|---|
| Config | Ghi cứng trong `app.py` (dòng 17–22) | Gom vào `config.py`, đọc bằng `os.getenv` (dòng 14–50) | Cùng một code chạy được ở nhiều môi trường, đổi cấu hình không phải sửa code |
| Health check | Không có, `/health` trả 404 | `/health` (dòng 135–149) và `/ready` (dòng 152–161) | `/health` để nền tảng biết khi nào cần restart; `/ready` để load balancer biết khi nào được gửi traffic |
| Logging | `print` (dòng 33–38) | `logging` với format dạng JSON (dòng 27–32, 110–122), còn lỗi (xem bên dưới) | Log có cấu trúc thì lọc, tìm kiếm và cảnh báo tự động được |
| Shutdown | Không có code riêng | `lifespan` (dòng 39–67) và handler SIGTERM (dòng 180–189) | Khi deploy bản mới, nền tảng gửi SIGTERM; app cần ngừng nhận việc mới, xử lý xong việc đang dở rồi mới thoát |
| Secret | Key và mật khẩu database trong code, key bị in ra log | Đọc từ env (`config.py` dòng 27, 32); log chỉ ghi độ dài câu hỏi và IP client | Secret không đi vào git và log |
| Host/Port | `localhost`, 8000 cố định (dòng 51–52) | Mặc định `0.0.0.0`, đọc `HOST` và `PORT` (`config.py` dòng 17–18; `app.py` dòng 196–197) | Chạy được trong container và nhận đúng cổng nền tảng cấp |

Anti-pattern đã được sửa:

- `develop/app.py` dòng 34 in API key → `production/app.py` dòng 110–115 chỉ log `question_length` và `client_ip`, không log secret.
- `develop/app.py` dòng 51–52 ghi cứng host, port → `production/config.py` dòng 17–18 đọc từ biến môi trường.

#### Kết quả chạy bản production

```text
$ curl -i http://localhost:8000/health
HTTP/1.1 200 OK
{"status":"ok","uptime_seconds":0.6,"version":"1.0.0","environment":"development","timestamp":"2026-11-26T07:37:27.643626+00:00"}

$ curl -i http://localhost:8000/ready
HTTP/1.1 200 OK
{"ready":true}

$ curl -i -X POST http://localhost:8000/ask -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/1.1 200 OK
{"question":"Hello","answer":"Đây là câu trả lời từ AI agent (mock). Trong production, đây sẽ là response từ OpenAI/Anthropic.","model":"gpt-4o-mini"}

$ curl -i -X POST http://localhost:8000/ask -H "Content-Type: application/json" -d '{}'
HTTP/1.1 422 Unprocessable Entity
{"detail":"question field is required"}
```

Chạy lại với `PORT=9000 ENVIRONMENT=staging python app.py` thì `/health` trả lời ở cổng 9000 với `"environment":"staging"`, tức cấu hình được đọc từ biến môi trường.

Gửi SIGTERM bằng `kill -TERM <PID>`: tiến trình thoát với exit code 0. Thứ tự log (lần chạy có đặt `OPENAI_API_KEY` giả):

```text
INFO:     Shutting down
INFO:     Waiting for application shutdown.
{"time":"2026-11-26 14:37:42,919","level":"INFO","msg":"Agent shutting down gracefully — finishing in-flight requests..."}
{"time":"2026-11-26 14:37:43,020","level":"INFO","msg":"Shutdown complete"}
INFO:     Application shutdown complete.
INFO:     Finished server process [1606]
{"time":"2026-11-26 14:37:43,022","level":"INFO","msg":"Received SIGTERM — initiating graceful shutdown"}
```

Dòng `Received SIGTERM` của handler hiện ra sau cùng, khi uvicorn đã tắt xong. Phép thử này gửi SIGTERM lúc không có request nào đang chạy, nên chưa kiểm chứng việc chờ request dở dang.

#### Những điểm bản production vẫn còn lỗi

1. **File `.env` không được đọc.** `python-dotenv` có trong `requirements.txt` nhưng code không gọi `load_dotenv()`. Đã thử trên một bản sao của thư mục: `.env` đặt `PORT=9000`, app vẫn nghe cổng 8000, cổng 9000 không có gì.
2. **Mất toàn bộ log mức INFO khi `OPENAI_API_KEY` trống.** Lần chạy này chỉ thấy dòng `WARNING:root:OPENAI_API_KEY not set` và log của uvicorn, không có `agent_request`. Nguyên nhân: `config.py` dòng 45 gọi `logging.warning` trước khi `app.py` gọi `logging.basicConfig`; Python tự cấu hình root logger ở lần gọi đó, nên `basicConfig` sau đó không có tác dụng.
3. **Log có JSON lồng nhau bị hỏng.** Khi đặt `OPENAI_API_KEY` giả để log hiện ra, các dòng `startup`, `agent_request`, `agent_response` không phải JSON hợp lệ vì dấu `"` bên trong `msg` không được escape. Ví dụ:

   ```text
   {"time":"2026-11-26 14:37:42,600","level":"INFO","msg":"{"event": "agent_request", "question_length": 5, "client_ip": "127.0.0.1"}"}
   ```

   Cách sửa: viết formatter dùng `json.dumps` cho cả bản ghi.
4. **Chưa kiểm tra API key (nhận xét từ việc đọc code).** `config.py` có `api_key` nhưng `/ask` không dùng tới.

## Part 2: Docker

### Exercise 2.1: Dockerfile questions

Theo `02-docker/develop/Dockerfile`.

1. **Base image:** `python:3.11` (dòng 8), bản Python đầy đủ, có sẵn công cụ build như `gcc`.
2. **Working directory:** `/app` (dòng 11). Các lệnh `COPY`, `RUN`, `CMD` phía sau chạy tại thư mục này.
3. **Vì sao COPY `requirements.txt` trước (dòng 14–20):** Docker cache theo từng layer, khi một layer thay đổi thì các layer sau nó phải build lại. Chép `requirements.txt` và cài thư viện trước, chép code sau, thì khi chỉ sửa code Docker dùng lại layer `pip install`, build nhanh hơn nhiều. Nếu chép code trước, mỗi lần sửa code đều phải cài lại thư viện.
4. **CMD và ENTRYPOINT:** `CMD` là lệnh mặc định, bị thay hoàn toàn khi truyền lệnh khác vào `docker run <image> <lệnh>`. `ENTRYPOINT` là chương trình cố định của container; tham số của `docker run` được nối thêm vào sau, muốn thay phải dùng `--entrypoint`. Khi dùng cả hai, `CMD` làm tham số mặc định cho `ENTRYPOINT`. Dockerfile này chỉ dùng `CMD` dạng exec (dòng 30) nên `python app.py` là PID 1 và nhận trực tiếp SIGTERM.

### Exercise 2.2: Build và run

Build từ gốc repo vì Dockerfile `COPY` theo đường dẫn tính từ gốc. Do đó Docker dùng `.dockerignore` ở gốc repo, không dùng file trong `02-docker/develop/`.

```bash
docker build -f 02-docker/develop/Dockerfile -t my-agent:develop .
docker run -d --name k5-day14-docker-develop -p 8000:8000 my-agent:develop
```

Output (đã lược bớt header HTTP):

```text
$ curl -i http://localhost:8000/health
HTTP/1.1 200 OK
{"status":"ok","uptime_seconds":0.3,"container":true}

$ curl -i -X POST "http://localhost:8000/ask?question=What+is+Docker"
HTTP/1.1 200 OK
{"answer":"Container là cách đóng gói app để chạy ở mọi nơi. Build once, run anywhere!"}

$ curl -i -X POST http://localhost:8000/ask -H "Content-Type: application/json" -d '{"question":"What is Docker?"}'
HTTP/1.1 422 Unprocessable Entity
{"detail":[{"type":"missing","loc":["query","question"],"msg":"Field required","input":null}]}
```

Bản develop nhận `question` qua query, nên gửi JSON bị 422.

### Exercise 2.3: Multi-stage build

- **Stage 1 (`builder`, dòng 16–29):** từ `python:3.11-slim`, cài `gcc`, `libpq-dev`, rồi `pip install --user` vào `/root/.local`.
- **Stage 2 (`runtime`, dòng 36–72):** bắt đầu lại từ `python:3.11-slim` sạch, tạo user `appuser`, chỉ chép thư viện đã cài từ builder cùng code, thêm `HEALTHCHECK`, chạy uvicorn với 2 worker.
- **Vì sao image nhỏ hơn:** chủ yếu do đổi base từ bản đầy đủ sang `slim`. Multi-stage giúp `gcc`, `libpq-dev` và các file phát sinh lúc build không nằm trong image cuối.

Kích thước đo bằng `docker images my-agent` (cột DISK USAGE):

| Image | Disk usage | Content size |
|---|---|---|
| `my-agent:develop` | 1.67 GB (1670 MB) | 426 MB |
| `my-agent:advanced` | 240 MB | 57.4 MB |

**Chênh lệch:** (1670 − 240) / 1670 = **85.6%**, bản advanced nhỏ hơn.

Kiểm tra bên trong container:

| | develop | advanced |
|---|---|---|
| User | `root` (uid 0) | `appuser` (uid 999) |
| `gcc` | có (`/usr/bin/gcc`) | không có |
| PID 1 | `python app.py` | `uvicorn main:app ... --workers 2` |

Bản advanced chạy độc lập cũng trả lời được: `/health` và `POST /ask` (JSON) đều 200.

### Exercise 2.4: Docker Compose stack

```text
Máy host
  │  :80, :443
  ▼
┌──────────────── mạng bridge "internal" ────────────────┐
│  nginx ──HTTP──▶ agent:8000                            │
│                    ┆ (có REDIS_URL, QDRANT_URL)        │
│                    ├┄┄▶ redis:6379   (volume redis_data)│
│                    └┄┄▶ qdrant:6333  (volume qdrant_data)│
└────────────────────────────────────────────────────────┘
```

- **4 service:** `agent`, `redis`, `qdrant`, `nginx`.
- **Giao tiếp:** các service gọi nhau bằng tên service (Docker DNS) trong mạng `internal`. Chỉ `nginx` mở cổng ra host; gọi thẳng `localhost:8000` thì không kết nối được.
- **Thứ tự khởi động:** `redis` và `qdrant` phải healthy thì `agent` mới chạy; `nginx` chạy sau `agent`.
- Từ container `agent`, Redis trả `PONG` và cổng 6333 của Qdrant kết nối được. Đường nét đứt trong sơ đồ vì `main.py` hiện chưa dùng Redis hay Qdrant.

Lệnh chạy (trong `02-docker/production/`, sau khi `touch .env.local`):

```bash
docker compose -p k5-day14-docker up -d --build --wait
```

Trạng thái:

```text
NAME                       SERVICE   STATUS                    PORTS
k5-day14-docker-agent-1    agent     Up 5 seconds (healthy)    8000/tcp
k5-day14-docker-nginx-1    nginx     Up 5 seconds              0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
k5-day14-docker-qdrant-1   qdrant    Up 16 seconds (healthy)   6333-6334/tcp
k5-day14-docker-redis-1    redis     Up 16 seconds (healthy)   6379/tcp
```

Kết quả qua Nginx:

```text
$ curl -i http://localhost/health
HTTP/1.1 200 OK
Server: nginx
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
{"status":"ok","uptime_seconds":4.0,"version":"2.0.0","timestamp":"2026-11-26T07:56:15.136617"}

$ curl -i -X POST http://localhost/ask -H "Content-Type: application/json" -d '{"question":"Explain microservices"}'
HTTP/1.1 200 OK
Server: nginx
{"answer":"Tôi là AI agent được deploy lên cloud. Câu hỏi của bạn đã được nhận."}
```

Gửi 60 request song song tới `http://localhost/`: **21 request trả 200, 39 request trả 429**. Nginx giới hạn 10 request/giây mỗi IP với `burst=20`; log Nginx ghi `limiting requests ... by zone "api_limit"`.

Dọn dẹp: `docker compose -p k5-day14-docker down -v`.

#### Những điểm tài liệu và code chưa khớp

- Comment trong `docker-compose.yml` ghi agent có 2 replica, nhưng file không khai báo số replica và khi chạy chỉ có **1** container `agent`. Muốn Nginx chia tải thì phải scale thêm.
- Comment dòng 67 của Dockerfile production ghi Docker sẽ tự restart khi health check fail. Docker Engine chỉ đánh dấu container là `unhealthy`; `restart: unless-stopped` chỉ khởi động lại khi tiến trình thoát.
- Cổng 443 được mở nhưng `nginx.conf` chỉ `listen 80`.
- Log của `main.py` mắc lỗi JSON lồng nhau giống Part 1: `{"time":"...","level":"INFO","msg":"{"event": "request", "q_len": 15}"}`.
- Compose cảnh báo thuộc tính `version` đã lỗi thời.

## Part 3: Cloud Deployment

### Exercise 3.2: Deploy Render

Deploy chính agent của Part 6. Chi tiết ở [DEPLOYMENT.md](DEPLOYMENT.md).

- **URL:** https://day14-agent-f7qk.onrender.com
- **Cách deploy:** Render Blueprint, Blueprint Path `06-lab-complete/render.yaml`, tạo web service `day14-agent` (Docker) và Key Value `day14-redis`, cùng region Singapore.
- **Ảnh:** [dashboard.png](screenshots/dashboard.png), [running.png](screenshots/running.png), [test.png](screenshots/test.png)

Kết quả 4 lệnh tự kiểm:

```text
health    200
ready     200
no key    401
with key  200
```

### So sánh `railway.toml` và `render.yaml`

So hai file trong `06-lab-complete/`. Nền tảng đã deploy là Render; `railway.toml` chưa được deploy thử.

| Tiêu chí | `railway.toml` | `render.yaml` |
|---|---|---|
| Định dạng | TOML | YAML |
| Phạm vi | Cách build và deploy **một** service | Cả hạ tầng: web service **và** Redis (Key Value) |
| Build | `builder = "DOCKERFILE"`, `dockerfilePath` | `runtime: docker`, `rootDir`, `dockerfilePath`, `dockerContext` |
| Vị trí | Dùng khi chạy `railway up` trong `06-lab-complete/` | Mặc định tìm ở gốc repo; ở đây phải chỉ Blueprint Path |
| Health check | `healthcheckPath = "/health"`, `healthcheckTimeout = 60` | `healthCheckPath: /health` (viết hoa chữ C) |
| Restart | `restartPolicyType = "ON_FAILURE"`, tối đa 3 lần | Không khai báo |
| Biến môi trường | Không khai báo trong file; đặt bằng CLI hoặc dashboard | Khai báo trong `envVars` |
| Secret | Đặt ngoài file | `generateValue: true`: Render tự sinh, file không chứa giá trị |
| Nối Redis | Tự tạo Redis rồi đặt `REDIS_URL` | `fromService` lấy `connectionString` của `day14-redis` |
| Region, gói | File không khai báo | `region: singapore`, `plan: free` |

**Vì sao khác:** `railway.toml` là cấu hình cho một service, còn tài nguyên khác được tạo riêng trên Railway. Render Blueprint là dạng Infrastructure as Code mô tả nhiều tài nguyên và liên kết giữa chúng, nên một file dựng được cả agent lẫn Redis.

Hai file mẫu trong `03-cloud-deployment/` dùng cách build khác: `railway.toml` dùng Nixpacks với `startCommand`, `render.yaml` dùng `runtime: python` với `buildCommand`. Bản của Part 6 dùng Dockerfile ở cả hai, nên image trên cloud được build theo cùng công thức với ở local.

### Exercise 3.3: Pipeline CI/CD Cloud Run

Đọc `cloudbuild.yaml` và `service.yaml` trong `03-cloud-deployment/production-cloud-run/`, không deploy.

1. **Test:** cài dependencies và chạy `pytest tests/`; theo chú thích trong file, pipeline được kích hoạt khi push lên `main`.
2. **Build:** `docker build`, gắn tag `$COMMIT_SHA` và `latest`, dùng `--cache-from` image `latest`.
3. **Push:** đẩy cả hai tag lên Google Container Registry. Các bước nối nhau bằng `waitFor`, nên bước trước lỗi thì bước sau không chạy.
4. **Deploy:** `gcloud run deploy` image `$COMMIT_SHA` ở `asia-southeast1`, 1–10 instance, secret `OPENAI_API_KEY` lấy từ Secret Manager.
5. **`service.yaml`** mô tả service dạng khai báo (concurrency 80, CPU và RAM, liveness `/health`, startup probe `/ready`, secret từ Secret Manager); bước deploy của `cloudbuild.yaml` không dùng file này mà truyền tham số qua dòng lệnh.

## Part 4: API Security

Test chạy trong WSL2 ở **cổng 8010** (đặt `PORT=8010`) vì cổng 8000 đang bị tiến trình khác giữ. Bản production dùng môi trường riêng (fastapi 0.165.0, uvicorn 0.54.0, pydantic 2.14.4, PyJWT 2.15.1) vì `requirements.txt` yêu cầu `pydantic>=2.11`. Output đã bỏ header `date`, `content-length` và một số header không liên quan; key và token đã che.

### Exercise 4.1: API Key authentication

- **Key được kiểm tra ở đâu:** hàm `verify_api_key` (`develop/app.py` dòng 39–54), đọc header `X-API-Key` (dòng 36) và so với biến `AGENT_API_KEY` (dòng 35). `/ask` dùng qua `Depends(verify_api_key)` (dòng 70). `/` và `/health` không cần key.
- **Sai key thì sao:** thiếu key trả **401**, sai key trả **403**.
- **Rotate key:** đổi biến `AGENT_API_KEY` rồi khởi động lại. Đã thử: sau khi đổi, key cũ trả 403, key mới trả 200. Vì chỉ nhận một key nên client dùng key cũ bị từ chối ngay. Muốn đổi không gián đoạn thì server phải nhận tạm cả key cũ và key mới.

```text
== Không có key
$ curl -i -X POST http://localhost:8010/ask -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/1.1 401 Unauthorized
{"detail":"Missing API key. Include header: X-API-Key: <your-key>"}

== Sai key
$ curl -i -X POST http://localhost:8010/ask -H "X-API-Key: wrong-key" -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/1.1 403 Forbidden
{"detail":"Invalid API key."}

== Đúng key
$ curl -i -X POST http://localhost:8010/ask -H "X-API-Key: <key>" -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/1.1 200 OK
{"question":"Hello","answer":"Đây là câu trả lời từ AI agent (mock). Trong production, đây sẽ là response từ OpenAI/Anthropic."}
```

### Exercise 4.2: JWT authentication

**Luồng:** client gửi username và password tới `POST /auth/token` → server tạo JWT ký bằng HS256, chứa `sub`, `role`, `iat`, `exp` → client gửi `Authorization: Bearer <token>` → server kiểm chữ ký và hạn dùng (`auth.py` dòng 46–67), không cần tra database. Token đã lấy có `sub=student`, `role=user`, thời hạn 3600 giây.

`CODE_LAB.md` ghi `POST /token` với `admin`/`secret`; đường dẫn đó trả **404**. Đúng là `POST /auth/token` với tài khoản demo trong `auth.py`.

```text
== Không có token
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer
{"detail":"Authentication required. Include: Authorization: Bearer <token>"}

== Sai mật khẩu khi lấy token
HTTP/1.1 401 Unauthorized
{"detail":"Invalid credentials"}

== Token không hợp lệ
HTTP/1.1 403 Forbidden
{"detail":"Invalid token."}

== Token hợp lệ: POST /ask với Authorization: Bearer <token>
HTTP/1.1 200 OK
{"question":"Explain JWT","answer":"Agent đang hoạt động tốt! (mock response) Hỏi thêm câu hỏi đi nhé.","usage":{"requests_remaining":9,"budget_remaining_usd":1.6e-05}}

== GET /admin/stats bằng token của student
HTTP/1.1 403 Forbidden
{"detail":"Admin only"}
```

### Exercise 4.3: Rate limiting

- **Thuật toán:** sliding window, lưu timestamp từng request trong `deque` và bỏ các mốc cũ hơn 60 giây (`rate_limiter.py` dòng 36–46, 65). Comment ghi "Sliding Window Counter", nhưng cách lưu từng timestamp là dạng sliding window log. Request bị từ chối không được tính vào cửa sổ.
- **Giới hạn:** `student` 10 request/phút, `teacher` (role `admin`) 100 request/phút (dòng 86–87).
- **Admin:** không bỏ qua hoàn toàn giới hạn, chỉ dùng limiter mức cao hơn, chọn theo `role` (`app.py` dòng 141).
- **Hạn chế:** state nằm trong RAM. Restart là mất, và khi chạy nhiều worker hoặc instance thì mỗi tiến trình đếm riêng. Muốn dùng chung phải lưu trong Redis.

Vòng lặp 20 request bằng token `student`, chạy ngay sau 1 request thành công ở Exercise 4.2:

```text
request 1 -> 200
...
request 9 -> 200
request 10 -> 429
...
request 20 -> 429
```

Kết quả: 9 request trả 200, 11 request trả 429. Cộng request ở 4.2 là đủ 10 request trong 60 giây.

```text
HTTP/1.1 429 Too Many Requests
x-ratelimit-limit: 10
x-ratelimit-remaining: 0
x-ratelimit-reset: 1795681204
retry-after: 59
{"detail":{"error":"Rate limit exceeded","limit":10,"window_seconds":60,"retry_after_seconds":59}}
```

Cùng vòng lặp 20 request bằng token `teacher`: **20 request đều trả 200**.

### Exercise 4.4: Cost guard

**Cách code hiện tại làm** (`production/cost_guard.py`):

1. Trước khi gọi LLM, `check_budget` (dòng 60–91): chi phí trong ngày của user đạt $1 thì trả **402**; tổng chi phí mọi user đạt $10 thì trả **503**; dùng từ 80% thì ghi cảnh báo.
2. Sau khi gọi LLM, `record_usage` (dòng 93–110): cộng token và tính tiền theo giá input $0.00015, output $0.0006 cho mỗi 1K token. Số token trong demo là ước lượng bằng số từ nhân 2 (`app.py` dòng 151–152).

Để thấy 402, tôi dùng trực tiếp class `CostGuard` với budget rất nhỏ, không sửa code:

```text
first check_budget: allowed
recorded cost_usd: 7.5e-05
second check_budget: 402 {'error': 'Daily budget exceeded', 'used_usd': 7.5e-05, 'budget_usd': 1e-06, 'resets_at': 'midnight UTC'}
```

**Cách làm theo đề bài ($10/tháng, lưu trong Redis)** — đây là thiết kế, Part 4 không cài đặt và chưa chạy thử:

- Key `budget:{user_id}:{YYYY-MM}`; sang tháng mới key đổi nên tự reset. Đặt `EXPIRE` khoảng 32 ngày để dọn key cũ.
- Trước khi gọi LLM, đọc tổng đã dùng; đạt ngưỡng thì trả 402. Sau khi gọi, cộng chi phí bằng `INCRBYFLOAT`.
- Lời giải trong `CODE_LAB.md` đọc (`GET`) rồi mới cộng nên không atomic: nhiều request đồng thời có thể cùng qua bước kiểm tra. Muốn chặn chặt thì gộp kiểm tra và cộng vào một Lua script.

**Vì sao cần cả hai:** rate limit chặn gọi dồn dập, bảo vệ tốc độ và tài nguyên. Cost guard chặn tổng tiền: gọi chậm, đúng giới hạn tốc độ nhưng lâu dài hoặc prompt rất dài vẫn có thể tốn nhiều tiền.

#### Những điểm code còn lỗi

1. **`budget_remaining_usd` trong response của `/ask` sai.** `app.py` dòng 160 trả `usage.total_cost_usd`, tức tiền **đã dùng**: response ghi `1.6e-05`, trong khi `/me/usage` sau đó cho thấy budget còn lại là `0.999809`.
2. **Header `server` không bị ẩn.** `app.py` dòng 84–85 định xoá, nhưng mọi response vẫn có `server: uvicorn`.
3. **Sai key trả 403** ở bản develop (dòng 49–53). Part 6 yêu cầu thiếu hoặc sai key đều trả **401**.
4. **Budget tổng không reset theo ngày (đọc code).** `_global_cost` chỉ được cộng thêm; `_global_today` được gán ở dòng 50 rồi không dùng tới. Thông báo ghi reset lúc nửa đêm UTC nhưng ngày được tính bằng `time.strftime`, tức giờ địa phương của máy.
5. **Có giá trị mặc định cho secret (đọc code).** `JWT_SECRET` (`auth.py` dòng 22) và `AGENT_API_KEY` (`develop/app.py` dòng 35) có sẵn trong code. Nếu quên đặt biến môi trường, người đọc được code có thể tự ký token `admin` hoặc dùng key mặc định. Bản develop còn in key ra màn hình (dòng 91–92).

## Part 5: Scaling & Reliability

### Exercise 5.1: Health checks

Theo `05-scaling-reliability/develop/app.py`, chạy `python app.py` trong WSL2.

```text
$ curl -i http://localhost:8000/health
HTTP/1.1 200 OK
{"status":"ok","uptime_seconds":0.6,"version":"1.0.0","environment":"development","timestamp":"2026-11-26T08:25:08.686369+00:00","checks":{"memory":{"status":"ok","used_percent":11.1}}}

$ curl -i http://localhost:8000/ready
HTTP/1.1 200 OK
{"ready":true,"in_flight_requests":1}
```

- **`/health` (liveness, dòng 104–144):** trả lời câu hỏi "tiến trình còn sống không?". Fail thì nền tảng **restart** container. Bản này kiểm tra thêm bộ nhớ, trên 90% thì ghi `degraded` nhưng vẫn trả 200.
- **`/ready` (readiness, dòng 147–168):** trả lời câu hỏi "có nhận request được chưa?". Fail (503) thì load balancer **ngừng gửi traffic**, không cần restart.
- **Vì sao tách đôi:** khi một phụ thuộc như Redis chết, restart agent không sửa được gì. `/health` nên vẫn 200, còn `/ready` trả 503.
- **Hạn chế (đọc code):** `/ready` chỉ dựa vào cờ `_is_ready`, không kiểm tra phụ thuộc nào. `in_flight_requests` bằng 1 vì tính cả chính request `/ready`.

### Exercise 5.2: Graceful shutdown

Mock LLM của bản develop mất khoảng 3 giây (`develop/utils/mock_llm.py` dòng 21). Gửi một request `/ask`, 1.5 giây sau gửi `kill -TERM` tới server, rồi 0.5 giây sau gửi thêm một request `/health`.

```text
request gửi trước SIGTERM  -> HTTP 200 after 3.030559s
request gửi sau SIGTERM    -> 000 (curl không nhận được response nào)
server exit code: 0
```

```text
INFO:     Shutting down
INFO:     127.0.0.1:33962 - "POST /ask?question=Long+task HTTP/1.1" 200 OK
INFO:     Waiting for application shutdown.
2026-11-26 15:25:11,832 INFO 🔄 Graceful shutdown initiated...
2026-11-26 15:25:11,833 INFO ✅ Shutdown complete
INFO:     Application shutdown complete.
INFO:     Finished server process [5113]
2026-11-26 15:25:11,837 INFO Received signal 15 — uvicorn will handle graceful shutdown
```

- Request đang chạy được xử lý xong, request mới không được phục vụ, tiến trình thoát với exit code 0.
- Uvicorn là bên chờ request: nó xử lý xong request rồi mới chạy phần shutdown của `lifespan`. Vòng lặp chờ `_in_flight_requests` (dòng 61–64) không in dòng `Waiting for ...` nào.
- Handler ở dòng 175–183 chỉ ghi log, và dòng log đó hiện ra sau khi shutdown đã xong.

### Exercise 5.3: Stateless design

- **Vấn đề khi lưu state trong RAM:** mỗi instance có bộ nhớ riêng. Request sau có thể tới instance khác và không thấy lịch sử; restart là mất hết.
- **Cách bản production làm:** lưu session trong Redis, key `session:{session_id}`, TTL 3600 giây (`production/app.py` dòng 59–73), giữ tối đa 20 message (dòng 85–87). Instance nào cũng đọc được.

### Exercise 5.4: Load balancing

Trong `05-scaling-reliability/production/`, sau khi `touch .env.local`:

```bash
docker compose -p k5-day14-scaling up -d --build --scale agent=3 --wait
```

```text
NAME                       SERVICE   STATUS                    PORTS
k5-day14-scaling-agent-1   agent     Up 6 seconds (healthy)    8000/tcp
k5-day14-scaling-agent-2   agent     Up 6 seconds (healthy)    8000/tcp
k5-day14-scaling-agent-3   agent     Up 6 seconds (healthy)    8000/tcp
k5-day14-scaling-nginx-1   nginx     Up 5 seconds              0.0.0.0:8080->80/tcp
k5-day14-scaling-redis-1   redis     Up 17 seconds (healthy)   6379/tcp
```

Gửi 10 request `POST /chat`, instance trả lời xoay vòng:

```text
request 1:  served_by=instance-18fd9d  X-Served-By=172.20.0.4:8000
request 2:  served_by=instance-9e0ed8  X-Served-By=172.20.0.3:8000
request 3:  served_by=instance-ec551d  X-Served-By=172.20.0.5:8000
request 4:  served_by=instance-18fd9d  X-Served-By=172.20.0.4:8000
...
request 10: served_by=instance-18fd9d  X-Served-By=172.20.0.4:8000
```

10 request này chia 4 / 3 / 3. Đếm trong log của từng container (gồm cả 5 request của `test_stateless.py`): 5, 6 và 4 request `POST /chat`.

### Exercise 5.5: Test stateless

`python test_stateless.py`: 5 câu trong cùng một session được **3 instance khác nhau** phục vụ, history có đủ **10 message**.

```text
Request 1: [instance-18fd9d]
Request 2: [instance-9e0ed8]
Request 3: [instance-ec551d]
Request 4: [instance-18fd9d]
Request 5: [instance-9e0ed8]
Total messages: 10
✅ Session history preserved across all instances via Redis!
```

**Giải thích:** instance không giữ gì giữa các request; mỗi request đọc history từ Redis theo `session_id`, nên đổi instance không mất ngữ cảnh. Mock LLM không dùng history để trả lời, nên phép thử này chứng minh history được **lưu và đọc lại**, chưa chứng minh câu trả lời dựa trên ngữ cảnh.

**Tắt một instance giữa chừng.** `test_stateless.py` không tự tắt instance nào (`CODE_LAB.md` mô tả khác), nên tôi thử riêng: gửi Q1, Q2, `docker stop` instance đã trả lời Q1 (exit code 0), rồi gửi tiếp cùng session.

```text
Q3 -> 200   0.13s   instance-18fd9d
Q4 -> 200  60.20s   instance-ec551d
Q5 -> 200   0.11s   instance-ec551d
Q6 -> 200   0.13s   instance-18fd9d
history count: 12
```

- History còn đủ 12 message (6 câu hỏi và 6 câu trả lời), cả 4 request sau đều trả 200.
- Q4 mất **60 giây**. Log Nginx ghi `upstream timed out ... while connecting to upstream` tới `172.20.0.3`, là instance đã tắt. Nginx vẫn gửi request vào địa chỉ này, chờ hết thời gian kết nối (mặc định 60 giây) rồi mới chuyển sang instance khác.
- Nguyên nhân: `server agent:8000;` (`nginx.conf` dòng 9) không có `resolve`, nên địa chỉ được phân giải lúc Nginx khởi động. Dòng `resolver` không làm upstream này tự cập nhật. Hướng khắc phục (chưa thử): thêm `resolve` kèm `zone` cho upstream và đặt `proxy_connect_timeout` ngắn.

**Tắt Redis** (khi còn 2 instance chạy):

```text
/health -> HTTP 200 sau 4.00s: {"status":"degraded", ... "redis_connected":false}
/ready  -> HTTP 502 sau 11.07s (trang lỗi của Nginx)
Bật lại Redis: /ready -> 200
```

- `/health` vẫn 200, đúng vai trò liveness.
- Qua Nginx, `/ready` trả **502** chứ không phải 503. Theo code, agent trả 503 (dòng 213–214); `proxy_next_upstream http_503` khiến Nginx thử instance khác, trong đó có địa chỉ của instance đã tắt, và log ghi `no live upstreams`. Tôi chưa gọi thẳng vào agent để xác nhận mã 503.

#### Những điểm code còn lỗi

1. **`turn` đếm lệch 1.** Request đầu của một session trả `turn=2`, request thứ hai trả `turn=3`. `history` đã gồm câu hỏi hiện tại (dòng 140–144), nhưng dòng 154 lại cộng thêm 1.
2. **Nginx không cập nhật khi instance thay đổi** (xem phần tắt instance ở trên).
3. **Âm thầm chuyển sang lưu trong RAM (đọc code).** Nếu Redis lỗi lúc khởi động, app dùng dict trong bộ nhớ (dòng 35–45) và vẫn chạy, `/ready` vẫn trả 200. Khi đó hệ thống không còn stateless, và app không tự kết nối lại Redis.
4. **Ghi history không atomic (đọc code).** `append_to_history` đọc, sửa rồi ghi đè cả session (dòng 76–90). Hai request đồng thời trong cùng session ở hai instance có thể làm mất message. Nên dùng cấu trúc list của Redis.

## Part 6: Final Project

Chạy `python check_production_ready.py` (bản đầy đủ, có Docker) trong `06-lab-complete/` trên WSL2, Python 3.11. Kết quả: image 238 MB, `docker stop` exit code 0 sau 0.8s.

```text
  📋 Checklist Deliverable
     ✅ Dockerfile (multi-stage, < 500 MB)
     ✅ docker-compose.yml (agent + redis)
     ✅ .dockerignore
     ✅ Health check endpoint (GET /health)
     ✅ Readiness endpoint (GET /ready)
     ✅ API Key authentication
     ✅ Rate limiting
     ✅ Cost guard
     ✅ Config từ environment variables
     ✅ Structured logging
     ✅ Graceful shutdown
     ✅ Public URL ready (Railway / Render config)
----------------------------------------------------------------
  Result: 12/12 tiêu chí đạt · 41/41 checks passed
  🎉 PASS 12/12 — PRODUCTION READY! Deploy nào!
```

## AI log

- Công cụ: Claude Code.
- Hỏi: cách thiết lập môi trường (CP0), hướng dẫn làm CP1, rồi yêu cầu AI nháp file câu trả lời.
- Nhận: lệnh cài uv và Python 3.11; AI kiểm tra môi trường CP0 trên máy này; hướng dẫn từng bước cho CP1. Với Part 1, AI soạn câu trả lời, tự chạy hai bản app trong WSL2 trên máy này và dán output, log vào file (đã lược header, che key).
- Lỗi của AI đã được phát hiện: ban đầu AI đọc code và nói log `agent_request` sẽ hiện ra dưới dạng JSON hỏng. Khi chạy thật, log INFO không hiện; AI chạy thêm một lần để xác định nguyên nhân (Part 1, mục "Những điểm bản production vẫn còn lỗi", điểm 2).
- Tự sửa và kiểm tra (Part 1): tôi đã đọc và kiểm tra các câu trả lời AI soạn, không có ý kiến thay đổi.
- Tự chạy lại (Part 1): tôi đã tự chạy lại phần CP1 và kiểm tra, kết quả khớp.
- Part 2: tôi yêu cầu AI làm tiếp CP2. AI soạn câu trả lời, tự chạy trong WSL2 trên máy này các lệnh build, đo kích thước image, chạy container và stack Compose; output và số đo trong Part 2 lấy từ các lần chạy đó (đã lược bớt).
- Tự kiểm tra (Part 2): tôi đã tự chạy lại `docker images my-agent` và stack Compose (gọi `/health` qua Nginx).
- Part 4: tôi yêu cầu AI chạy và soạn nháp CP3 để tôi kiểm tra. AI soạn câu trả lời, tạo môi trường `day14-part4`, tự chạy các app ở cổng 8010 và gọi trực tiếp class `CostGuard` trên máy này; output trong Part 4 lấy từ lần chạy đó. Lần chạy đầu của AI bị treo vì script kiểm tra cổng sai trong khi cổng 8000 đang bị chiếm; AI sửa script và chạy lại.
- Tự kiểm tra (Part 4): tôi đã tự chạy lại phần CP3, kết quả khớp.
- Part 5: tôi yêu cầu AI chạy và soạn nháp CP4 để tôi kiểm tra. AI soạn câu trả lời, tự chạy app develop và stack Compose trên máy này, tự thử tắt một instance và tắt Redis; output trong Part 5 lấy từ các lần chạy đó (đã lược bớt). Ban đầu AI tưởng mock LLM chỉ trễ 0,1 giây nên làm chậm thêm bằng một file khởi chạy ngoài repo; sau khi thấy mock đã trễ 3 giây, AI chạy lại bằng `app.py` nguyên bản và chỉ dùng kết quả lần này.
- Tự kiểm tra (Part 5): tôi đã tự chạy lại phần CP4, kết quả khớp.
- Part 6: tôi yêu cầu AI hoàn thành cả 6 chặng của CP5 rồi giải thích sau. **AI viết toàn bộ code và cấu hình** trong `06-lab-complete/` (`app/config.py`, `auth.py`, `redis_client.py`, `rate_limiter.py`, `cost_guard.py`, `main.py`, `Dockerfile`, `.dockerignore`, `docker-compose.yml`, `.env.example`, `railway.toml`), không sửa `check_production_ready.py`. AI tự chạy script chấm và các phép thử thêm trên máy này (input sai, Redis chết, 30 request đồng thời, SIGTERM).
- Tự kiểm tra (Part 6): tôi đã tự chạy lại phần CP5, kết quả khớp, và đã đọc code AI viết.
- CP6: tôi chọn Render. AI đọc tài liệu Render Blueprint và viết `06-lab-complete/render.yaml`, kiểm tra cú pháp YAML, chạy phần kiểm tra tĩnh và chạy thử image với `PORT=10000` trên máy này.
- CP6 (tiếp): tôi tự deploy trên Render, tự chạy 4 lệnh kiểm tra (200, 200, 401, 200) và tự chụp 3 ảnh. AI gọi thử 3 endpoint không cần key, hướng dẫn xử lý lỗi, kiểm tra 3 ảnh, soạn `DEPLOYMENT.md` và toàn bộ câu trả lời Part 3.
