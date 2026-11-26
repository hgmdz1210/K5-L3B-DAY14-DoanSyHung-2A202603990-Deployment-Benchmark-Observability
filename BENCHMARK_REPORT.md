# Benchmark & Observability Report — Day 14

> Số liệu Mục 1–3 lấy từ file JSON trong `reports/`, Mục 5 từ file CSV trong `benchmark-results/`. Phần output khác mà báo cáo dùng được trích nguyên văn ở Phụ lục B. Các số đo lấy từ những lần tôi chạy trên máy mình.

**Họ tên:** Doan Sy Hung
**Ngày chạy:** 2026-11-26, bắt đầu 16:39 (GMT+7)
**Môi trường:** Windows 11 + WSL2 (Ubuntu 26.04.1, 8 CPU, 7.7 GiB RAM), Python 3.11.18. Agent và công cụ tạo tải chạy trên cùng một máy.

---

## 1. SLO của agent

| SLI | SLO | Lý do chọn ngưỡng này |
|---|---|---|
| p95 latency `/ask` | < 500 ms | Khi không có request chậm bất thường, p95 đo được 218.1 ms; ngưỡng 500 ms chừa khoảng trống hơn 2 lần, và là mặc định của `load_test.py` |
| Error rate `/ask` | < 2 % | Mặc định của `load_test.py`, gấp đôi tỉ lệ lỗi 1% của mock LLM (xem ghi chú dưới bảng) |
| Accuracy trên golden dataset | ≥ 90 % | Với 23 câu, ngưỡng này cho phép sai tối đa 2 câu; ngoài ra quality gate còn chặn mọi regression so với baseline |

**Ghi chú về ngưỡng lỗi:** trong 7 lần load test, error rate dao động từ 0.33% đến 2.33% dù tỉ lệ lỗi của mock không đổi, và 2 lần vượt ngưỡng. Với 300 request, chỉ cần 7 lỗi là thành 2.33%, nên ngưỡng 2% khá sát so với mẫu nhỏ như vậy. SLO lỗi nên được đánh giá trên mẫu hoặc cửa sổ thời gian lớn hơn. Tôi giữ nguyên ngưỡng, không nới sau khi thấy kết quả.

---

## 2. Benchmark hiệu năng (develop, `load_test.py`)

### 2.1 Concurrency vs latency (agent v2)

Mỗi mức 300 request, cấu hình mock mặc định (`MOCK_SLOW_RATE=0.03`, lỗi 1%).

| Concurrency | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Error rate | SLO |
|---|---|---|---|---|---|---|
| 1 | 4.08 | 192.5 | 219.6 | 1709.4 | 0.33% | PASS |
| 10 | 37.35 | 191.2 | 220.6 | 1710.1 | 2.33% | **FAIL** (error rate) |
| 50 | 101.64 | 205.7 | 404.7 | 1722.3 | 0.67% | PASS |
| 100 | 52.2 | 393.2 | 3984.7 | 4422.1 | 0.33% | **FAIL** (p95) |

**Nhận xét:** RPS có tăng tuyến tính theo concurrency không? Vì sao?

Không.

- **1 → 10:** RPS tăng từ 4.08 lên 37.35, gần tỉ lệ với concurrency, trong khi p50 và p95 gần như không đổi. Agent dùng async nên phần lớn thời gian là chờ mock LLM, nhiều request chờ cùng lúc được. Lần chạy ở mức 10 không đạt SLO là do lỗi 503 ngẫu nhiên, không phải do latency.
- **10 → 50:** concurrency gấp 5 nhưng RPS chỉ gấp khoảng 2.7. Một yếu tố có thể là mỗi lần chạy chỉ có 300 request (trung bình 6 request mỗi worker), nên vài request chậm cuối bài kéo dài tổng thời gian. Tôi chưa kiểm chứng riêng giả thuyết này.
- **50 → 100:** RPS **giảm** từ 101.64 còn 52.2 và p95 tăng từ 404.7 lên 3984.7 ms.

**Ở concurrency 100, phần chậm nằm ngoài phần xử lý của server, nhiều khả năng ở công cụ tạo tải.** Phép đo riêng (Phụ lục B2):

| Concurrency | Client p50 / p95 (ms) | Server p50 / p95 (ms) | CPU server | CPU `load_test.py` |
|---|---|---|---|---|
| 50 | 196.1 / 273.0 | 188.9 / 219.1 | 0.42 s | 0.72 s |
| 100 | 745.2 / 4537.6 | 203.4 / 246.9 | 0.47 s | 5.47 s |

- Ở mức 100, latency do server tự đo gần như không đổi so với mức 50, trong khi latency phía client tăng nhiều lần.
- `load_test.py` dùng 5.47 giây CPU trong 7.40 giây chạy (trung bình khoảng 74% một core), gấp khoảng 12 lần server.
- Đồng hồ phía server chỉ bắt đầu khi server nhận xử lý request, nên không tính thời gian chờ trước đó. Vì server dùng rất ít CPU, tôi cho rằng công cụ tạo tải là nút thắt.

Vì vậy kết quả FAIL ở mức 100 chưa cho biết giới hạn của agent. Muốn đo đúng cần chạy công cụ tạo tải trên máy khác hoặc dùng nhiều tiến trình tạo tải.

**Dao động giữa các lần chạy:** cùng ở concurrency 50, p95 là 404.7 ms trong bảng trên và 273.0 ms trong phép đo riêng. Với 300 request, không nên coi một lần đo là con số chính xác.

### 2.2 Tail latency

Concurrency 20, 300 request mỗi lần.

| `MOCK_SLOW_RATE` | avg (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|
| 0 | 189.7 | 218.1 | 225.2 |
| 0.03 (mặc định) | 258.1 | 228.3 | 1710.0 |
| 0.1 | 357.3 | 1695.3 | 1715.6 |

**Nhận xét:** Chỉ số nào nhạy nhất với request chậm? Vì sao SLO không nên đặt theo average?

- **p99 phản ứng sớm nhất:** chỉ 3% request chậm đã đưa p99 từ 225.2 lên 1710.0 ms, trong khi average tăng 68.4 ms và p95 chỉ tăng 10.2 ms.
- Khi tỉ lệ chậm lên 10% (vượt 5%), **p95 cũng nhảy** lên 1695.3 ms; average mới tăng 167.6 ms so với mức 0.
- Average chia đều phần chậm cho mọi request nên che mất nhóm người dùng phải chờ khoảng 1.7 giây. Ở mức 0.1, average 357.3 ms vẫn dưới 500 ms trong khi p95 đã vi phạm SLO. SLO nên đặt theo percentile (p95, và theo dõi thêm p99).
- Lần chạy 0.03 cũng bị đánh dấu FAIL, nhưng do error rate 2.33%, không phải do latency.

---

## 3. Benchmark chất lượng (develop, `eval/run_eval.py`)

| Chỉ số | Agent v1 | Agent v2 | Agent v2 (sau khi sửa KB) |
|---|---|---|---|
| Accuracy | 4.3% (1/23) | 91.3% (21/23) | 100% (23/23) |
| Avg tokens / câu | 57.0 | 109.1 | 114.7 |
| Tổng cost (USD) | 0.000403 | 0.000762 | 0.0008 |
| Cost / câu đúng (USD) | 0.00040275 | 0.00003627 | 0.00003478 |
| Quality gate | FAIL (ngưỡng 80%) | PASS (ngưỡng 80%, 0 regression) | PASS (ngưỡng 100%, 0 regression) |

**Những câu v2 trả lời sai ban đầu và cách bạn sửa:**

| ID | Keyword bị thiếu | Bạn đã sửa gì |
|---|---|---|
| `security-02` | token, hết hạn, chữ ký | Thêm tài liệu về JWT so với API key (từ khoá kích hoạt `jwt`) |
| `scaling-03` | cpu, memory, custom metrics | Thêm tài liệu về Kubernetes HPA (từ khoá `hpa`, `kubernetes`, `autoscal`) |

Cả hai câu ban đầu nhận câu trả lời chung chung vì `KNOWLEDGE_BASE` không có tài liệu phù hợp. Sửa trong `develop/utils/mock_llm.py`, nội dung theo hướng gợi ý của `CODE_LAB.md`; không sửa `golden_dataset.jsonl`. Sau khi sửa, so với baseline `eval_v2.json`: 2 câu cải thiện, 0 regression. Eval v1 và v2 ban đầu chạy với bản `KNOWLEDGE_BASE` gốc lấy từ git (commit `f1fb9f0`).

**Nhận xét về trade-off chất lượng / chi phí / latency giữa v1 và v2:**

- **Chất lượng:** accuracy tăng từ 4.3% lên 91.3%.
- **Chi phí:** v2 dùng nhiều token hơn khoảng 1.9 lần mỗi câu vì prompt có thêm context, tổng cost tăng từ 0.000403 lên 0.000762 USD. Tính theo **câu trả lời đúng** thì v2 rẻ hơn khoảng 11 lần.
- **Latency:** p50 tăng từ 161.3 lên 187.0 ms. p95 lại cho kết quả ngược (v1 1648.2 ms, v2 220.7 ms), nhiều khả năng vì eval chỉ có 23 request nên vài request chậm ngẫu nhiên đủ quyết định p95. Không dùng eval để kết luận về latency.
- "Cost / câu" khiến v1 trông rẻ hơn dù gần như không trả lời đúng. "Cost / câu đúng" tính cả chất lượng nên so sánh hai phiên bản công bằng hơn.

### Quality gate trong CI

Job ở [`.github/workflows/eval.yml`](.github/workflows/eval.yml), chạy khi có pull request: bật agent v2 với `MOCK_ERROR_RATE=0`, rồi chạy `run_eval.py --min-accuracy 0.85 --baseline reports/eval_v2_fixed.json`.

- `run_eval.py` thoát với **exit code 1** khi accuracy dưới ngưỡng hoặc có regression; bước CI nhận mã khác 0 nên job fail.
- Để **chặn merge**, cần bật branch protection cho `main` và đặt check `eval` là bắt buộc. Chỉ có file workflow thì job fail chưa tự chặn merge.
- Đã thử gate: chạy v1 so với baseline v2 cho exit code 1 với 20 regression (Phụ lục B3).
- Các lệnh của job đã chạy thử trên máy local, exit code 0 (Phụ lục B4). Job chưa chạy trên GitHub Actions.

---

## 4. Observability stack (production)

Số liệu Mục 4–5 lấy từ một lần đo tự động tôi chạy ngày 2026-11-26, bắt đầu 17:19 (GMT+7) (riêng trace ở Mục 4.3, xem tại đó). Docker 29.9.3, máy 8 CPU / 7.7 GiB; mỗi container agent bị giới hạn 0.5 CPU và 256 MB. Locust chạy trên cùng máy. Unit test alert rules: `SUCCESS` (Phụ lục B5).

Để container agent chạy được, tôi phải thêm `ENV PYTHONUSERBASE=/home/agent/.local` vào `production/Dockerfile`. Thư viện được copy vào `/home/agent/.local` nhưng home của user `agent` là `/app`, nên container báo `No module named 'uvicorn'`.

### 4.1 Screenshot

- [x] Dashboard Grafana khi đang có tải: [grafana-dashboard.png](screenshots/grafana-dashboard.png)
- [x] Một trace chậm trong Jaeger: [jaeger-slow-trace.png](screenshots/jaeger-slow-trace.png)
- [x] Một trace lỗi trong Jaeger có event `exception`: [jaeger-error-trace.png](screenshots/jaeger-error-trace.png)
- [x] Trang Alerts của Prometheus, `AgentHighErrorRate` và `AgentHighLatencyP95` cùng **firing**: [prometheus-alert-firing.png](screenshots/prometheus-alert-firing.png)

### Exercise 7.4 — Đọc dashboard

Tải nền 30 user, 2 instance. Số lấy từ Phụ lục B6 (17:33:23, cửa sổ 1 phút); ảnh Grafana chụp trước đó khoảng 2 phút nên lệch nhẹ.

**1. p95 và avg là bao nhiêu, khoảng cách nói lên điều gì?** p95 = 293.9 ms, avg = 235.6 ms. Hai số khá gần nhau vì tỉ lệ request chậm (3%) thấp hơn 5% nên p95 chưa chạm tới nhóm chậm. Đuôi chậm chỉ lộ ở p99: trên biểu đồ Grafana, đường p99 ở khoảng 1.8 giây, cao hơn nhiều so với avg. Chỉ nhìn avg hoặc p95 ở đây sẽ không thấy nhóm request chậm này.

**2. Nginx có chia đều traffic cho 2 instance không?** Có: 9.327 và 9.345 req/s. Lúc có 3 instance là 20.45, 20.8 và 20.76 req/s.

**3. Vì sao input tokens/s lớn hơn output tokens/s?** 1376 so với 730.5 token/s. Input gồm system prompt, tài liệu retrieval đưa thêm vào và câu hỏi; output chỉ là câu trả lời.

**4. `curl http://localhost:8080/metrics` trả về gì, vì sao?** HTTP 404 (Phụ lục B5). `nginx.conf` chặn `/metrics` từ bên ngoài vì metrics để lộ route, lưu lượng và thông tin hệ thống. Prometheus scrape thẳng vào từng container trong mạng nội bộ nên không bị ảnh hưởng.

### 4.2 Thí nghiệm "phá hệ thống"

Tải nền 30 user trong suốt các thí nghiệm. Thời gian tính từ lúc script bắt đầu áp dụng thay đổi, hỏi trạng thái alert mỗi 2 giây (Phụ lục B8).

| # | Thay đổi | Alert nào firing | Thời gian từ lúc đổi → firing | Panel nào phản ánh rõ nhất |
|---|---|---|---|---|
| A | `MOCK_ERROR_RATE=0.2` | `AgentHighErrorRate` | 86 s (pending sau 26 s) | Error rate |
| B | `MOCK_SLOW_RATE=0.3` (A vẫn bật) | `AgentHighLatencyP95` | 144 s (pending sau 24 s) | Latency p95/p99 |
| C | `LLM_MODEL=mock-llm-large` | `LLMCostBurnRateHigh` | 144 s (pending sau 24 s) | Cost burn rate (USD/giờ) |
| D | `docker pause` 1 instance | `AgentInstanceDown` | 40 s (pending sau 10 s) | Instances up |
| E | `AGENT_VERSION=v1` | Không alert nào | Không firing | Retrieval hit ratio, Tokens/s, bảng phiên bản |

Số đo trong lúc thí nghiệm (Phụ lục B9):

- **A và B:** khi cả hai bật, error ratio 0.2086, p95 1.899 s, avg 0.5854 s. So với tải nền bình thường, p95 tăng khoảng 6.5 lần (từ 0.2939 s), còn avg tăng khoảng 2.5 lần (từ 0.2356 s). Thời gian của B được đo khi A vẫn đang bật.
- **Thời gian firing** gồm `for` của rule (1 phút ở A, 2 phút ở B) cộng thời gian để cửa sổ `rate(...[1m])` vượt ngưỡng (khoảng 25 giây ở cả hai).
- **C:** trước khi đổi không có alert nào, nên đo được thời gian tới firing. Cost lên 25.04 USD/giờ, p95 từ 0.2926 lên 0.7117 s. Ngay trước khi đổi, cost là 1.675 USD/giờ, nhưng mức này thấp hơn bình thường vì cửa sổ 5 phút còn gồm giai đoạn A+B (ít request thành công hơn). So với tải nền 30 user ổn định (2.296 USD/giờ), cost tăng khoảng 11 lần. Lúc lấy số, cửa sổ 5 phút vẫn còn lẫn dữ liệu của model nhỏ, nên 25.04 chưa phải mức ổn định.
- **D:** Prometheus còn 1 instance up. Từ lúc pause đến lúc lấy số, Nginx ghi 803 request `/ask` mã 200, 7 mã 503 và **29 mã 504** (Phụ lục B10), nhưng error ratio theo metric của agent vẫn 0.009309. Lỗi 504 phát sinh ở Nginx khi chờ instance bị treo; agent không xử lý xong các request đó nên không đếm. Phải giám sát thêm ở load balancer hoặc kiểm tra từ bên ngoài.
- **E:** sau 180 giây chờ của script, không alert nào pending hay firing. Retrieval không còn dữ liệu, input tokens/s là 680.2 (khoảng một nửa so với 1327 ở cấu hình mặc định trước C), p95 giảm còn 0.1993 s. Nhìn metric hạ tầng thì v1 còn "tốt hơn". Giờ lấy số của E (19:07:19) cách lần lấy số của D (17:50:02) hơn nhiều so với thời gian script chờ; nhiều khả năng máy đã sleep trong khoảng đó, tôi không kiểm chứng được. Lúc lấy số, tải vẫn chạy (18.87 req/s).

**Ngưỡng alert chi phí đang quá sát tải bình thường.** `LLMCostBurnRateHigh` (> 2 USD/giờ) đã firing dù chưa phá gì: cost là 5.914 USD/giờ sau bài đo 100 user và 2.296 USD/giờ với tải nền 30 user ổn định. Alert chỉ tắt sau giai đoạn A+B, khi cost trong cửa sổ 5 phút xuống 1.675 USD/giờ. Ngưỡng này báo động theo lượng traffic hơn là theo sự cố; nên đặt theo ngân sách thực tế hoặc theo cost trên mỗi request.

**Thí nghiệm E không làm alert nào firing. Bạn sẽ phát hiện loại sự cố này trong production bằng cách nào?**

Metric hạ tầng không biết câu trả lời đúng hay sai. Cần đo chất lượng riêng:

- Chạy eval trên golden dataset trong CI để chặn trước khi deploy, và chạy lại sau deploy hoặc theo lịch trên production. Ở Mục 3, eval phân biệt rõ v1 (4.3%) với v2 (91.3%).
- Alert cho tín hiệu gần với chất lượng, ví dụ tỉ lệ retrieval hit giảm. Rule phải xử lý cả trường hợp mất dữ liệu (`absent()`), vì ở v1 metric này không còn tăng.
- Cảnh báo khi `agent_info` đổi version ngoài kế hoạch, thu phản hồi người dùng, và chấm mẫu câu trả lời thật bằng người hoặc LLM-as-judge.

### 4.3 Debug bằng trace

Jaeger lưu trace trong bộ nhớ, và ảnh trace của lần chạy đầu chưa hiện đủ chi tiết, nên tôi tạo lại trace để chụp sau khi chạy xong các thí nghiệm (cấu hình mặc định, 2 agent, 400 request với 10 request song song; thời điểm chụp ghi ở Phụ lục B11). Số liệu của mục này thuộc các trace mới đó, không thuộc lần đo bắt đầu 17:19.

Trace chậm nhất tìm được từ log (span: Phụ lục B11):

- `trace_id`: `42b25eefded02a371b51fcb89b3aab25`
- Tổng thời gian: 1716.2 ms
- Span chiếm nhiều thời gian nhất: `chat mock-llm-small` (1686.3 ms, 98%); `agent.retrieve_context` chỉ 26.9 ms
- Dòng log tương ứng (grep theo `trace_id`):

```json
{"ts": "2026-11-26T12:14:16.366686+00:00", "level": "INFO", "service": "observable-agent", "instance": "eb4de0736695", "event": "llm_call", "trace_id": "42b25eefded02a371b51fcb89b3aab25", "span_id": "1f006a490e8fd0a7", "request_id": "2230ee289722", "model": "mock-llm-small", "agent_version": "v2", "input_tokens": 81, "output_tokens": 46, "cost_usd": 4e-05, "llm_ms": 1686.4}
{"ts": "2026-11-26T12:14:16.367664+00:00", "level": "INFO", "service": "observable-agent", "instance": "eb4de0736695", "event": "http_request", "trace_id": "42b25eefded02a371b51fcb89b3aab25", "span_id": "1f006a490e8fd0a7", "request_id": "2230ee289722", "method": "POST", "route": "/ask", "status": 200, "ms": 1715.1}
```

Nút thắt là lời gọi LLM, không phải code của agent: span dài 1686.3 ms, khớp với `llm_ms` 1686.4 ms mà log ghi cho lời gọi LLM.

**Trace lỗi** (span: Phụ lục B11): `trace_id` `4d67ce6fab0838ffc33fefb8361a3cd8`, 99.3 ms, trả 503. Span `chat mock-llm-small` (72.1 ms) có event `exception`: `utils.mock_llm.LLMError: Upstream LLM error: 503 Service Unavailable (mock)`.

```json
{"ts": "2026-11-26T12:28:03.109372+00:00", "level": "INFO", "service": "observable-agent", "instance": "ce97efbfd058", "event": "llm_error", "trace_id": "4d67ce6fab0838ffc33fefb8361a3cd8", "span_id": "ece1b00d67e9345b", "request_id": "c0a37593f0df", "error": "Upstream LLM error: 503 Service Unavailable (mock)"}
```

---

## 5. Benchmark scaling (production, Locust headless, 100 users, 2 phút)

Số của dòng `/ask` trong [scale_1_stats.csv](benchmark-results/scale_1_stats.csv) và [scale_3_stats.csv](benchmark-results/scale_3_stats.csv). Mỗi cấu hình chạy một lần.

| Số instance | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Failures |
|---|---|---|---|---|---|
| 1 | 59.33 | 190 | 280 | 1700 | 75 / 7095 (1.06%) |
| 3 | 59.87 | 190 | 230 | 1700 | 77 / 7161 (1.08%) |

**Giải thích kết quả:** Scale có cải thiện p95 không? Nút thắt nằm ở đâu?

- **p95 cải thiện nhẹ** (280 → 230 ms). **RPS, p50, p99 và tỉ lệ lỗi gần như không đổi.** Average của `/ask` đi từ 241.6 xuống 236.0 ms.
- **RPS không tăng vì Locust tạo tải kiểu closed-loop:** mỗi user chờ response rồi nghỉ 0.5–2 giây mới gửi tiếp. Với 100 user, tốc độ gửi bị quyết định chủ yếu bởi thời gian nghỉ, nên khi server đã đáp ứng kịp thì thêm instance không tạo thêm request.
- **Nút thắt của latency là lời gọi LLM:** LLM p95 theo Prometheus là 0.198 s với 1 instance và 0.1979 s với 3 instance. Phần lớn thời gian request nằm ở đó, và đuôi 1700 ms đến từ các lời gọi chậm của mock, nên p99 không đổi khi scale.
- Phần p95 được cải thiện có thể do 1 instance (0.5 CPU) phải xếp hàng đôi chút; p95 của `/health` cũng giảm từ 30 xuống 6 ms. Muốn biết sức chịu tải tối đa của một instance cần tăng số user cho tới khi RPS ngừng tăng.
- Lỗi khoảng 1% đến từ `MOCK_ERROR_RATE`, không phụ thuộc số instance.

---

## 6. Kết luận

- 3 điều bạn học được về benchmark & observability:
  1. **Chọn đúng percentile.** Với 3% request chậm, p95 trông vẫn bình thường còn p99 đã lên khoảng 1.7 giây; khi tỉ lệ vượt 5% thì p95 mới nhảy. Average che mất cả hai.
  2. **Phải kiểm tra cả công cụ đo.** Ở concurrency 100, chính công cụ tạo tải nhiều khả năng là nút thắt (Mục 2.1). Ở bài scaling, tải closed-loop làm RPS không tăng dù thêm instance (Mục 5).
  3. **Dashboard xanh chưa có nghĩa là hệ thống đúng.** Agent v1 trả lời sai gần hết mà không alert nào kêu; lỗi 504 ở Nginx không xuất hiện trên metric của agent.
- Nếu đưa agent này lên production thật, bạn sẽ thêm metric / alert nào nữa?

Tôi sẽ thêm:

- Metric và alert tỉ lệ 5xx ở Nginx, cùng synthetic check gọi `/ask` từ bên ngoài.
- Alert khi số instance ít hơn mong đợi (instance bị stop biến mất khỏi DNS nên `up == 0` không bắt được).
- Điểm eval chạy định kỳ và tỉ lệ retrieval hit làm tín hiệu chất lượng.
- Cost trên mỗi request, và cost tích luỹ so với ngân sách ngày.
- Alertmanager để gửi cảnh báo tới người trực.

---

## Phụ lục: Exercise 7.1 — Đọc metrics

Trích từ output `/metrics` của agent v2.

**1. Ba loại metric trong output `/metrics`:**

| Loại | Ví dụ | Đặc điểm |
|---|---|---|
| Counter | `http_requests_total{method="POST",route="/ask",status="200"} 1.0` | Chỉ tăng, dùng với `rate()` |
| Gauge | `agent_in_flight_requests 0.0` | Tăng và giảm |
| Histogram | `http_request_duration_seconds_bucket{le="0.2",method="POST",route="/ask"} 1.0` | Đếm theo bucket, tính percentile bằng `histogram_quantile` |

**2. Vì sao label `route` dùng `route.path` thay vì URL thật:** nếu dùng URL thật, mỗi URL lạ mà bot quét gọi tới sẽ tạo thêm time series mới. Số series tăng không giới hạn làm Prometheus tốn RAM. Đã thử gọi `/wp-admin`, `/.env`, `/a1b2c3`: cả ba trả 404 và gộp chung vào một series:

```text
http_requests_total{method="GET",route="unmatched",status="404"} 3.0
```

**Metric thêm mới** `agent_question_length_chars` (Histogram). Sau một câu hỏi 40 ký tự:

```text
agent_question_length_chars_bucket{le="20.0"} 0.0
agent_question_length_chars_bucket{le="50.0"} 1.0
agent_question_length_chars_count 1.0
agent_question_length_chars_sum 40.0
```

---

## Phụ lục B: Bằng chứng trích nguyên văn

Output của các lần tôi chạy, dùng cho những số không nằm trong file JSON hoặc CSV.

### B1. Môi trường đo Mục 2–3

```text
date: 2026-11-26 16:39 +0700
Ubuntu 26.04.1 LTS
cpus: 8  mem: 7.7Gi  Python 3.11.18
```

### B2. Phép đo CPU và latency phía client, server (Mục 2.1)

```text
Chay rieng, khong ghi de load_v2_*.json. 300 request moi lan, agent v2 mac dinh.
c=50   rps=104.13  client p50=196.1   p95=273.0   | server p50=188.9  p95=219.1  | CPU s: server=0.42 load_test=0.72 (wall 3.34s, test 2.88s)
c=100  rps=42.94   client p50=745.2   p95=4537.6  | server p50=203.4  p95=246.9  | CPU s: server=0.47 load_test=5.47 (wall 7.40s, test 6.99s)
```

### B3. Thử quality gate: v1 so với baseline v2 (phần cuối output)

```text
  Tổng cost (USD)           0.000762    0.000398       -0.000364

  ✨ Câu được cải thiện : 0
  ⚠️  Câu bị regression : 20 ['docker-01', 'docker-02', 'probe-01', 'probe-02', 'reliability-01', 'config-01', 'security-01', 'scaling-01', 'scaling-02', 'bench-01', 'bench-02', 'obs-01', 'obs-02', 'obs-03', 'obs-04', 'obs-05', 'obs-06', 'slo-01', 'cost-01', 'cloud-01']
──────────────────────────────────────────────────────────
  Quality gate (accuracy ≥ 80%, không regression): ❌ FAIL
══════════════════════════════════════════════════════════

exit code: 1
```

### B4. Chạy thử lệnh của job CI trên máy local (các dòng kết quả)

```text
  Accuracy      : 100.0%  (23/23)
  Accuracy                    100.0%      100.0%     +0.0 điểm %
  Quality gate (accuracy ≥ 85%, không regression): ✅ PASS
exit code: 0
```

### B5. Unit test alert rules và `/metrics` qua Nginx

```text
Processing test file: /p/alert_rules_test.yml
  SUCCESS

$ GET /metrics qua Nginx
HTTP 404
```

### B6. Số từ Prometheus cho Exercise 7.4

```text
--- snapshot: tải nền 30 user, 2 instance (Exercise 7.4) (17:33:23)
  instances_up       2
  traffic_rps        18.67
  rps_by_instance    [instance=172.20.0.5:8000] 9.327; [instance=172.20.0.8:8000] 9.345
  error_ratio        0.009737
  latency_avg_s      0.2356
  latency_p95_s      0.2939
  llm_p95_s          0.1981
  tokens_per_s       [type=input] 1376; [type=output] 730.5
  cost_usd_per_hour  2.296
  retrieval_per_s    [result=hit] 16.67; [result=miss] 1.945
  agent_info         [model=mock-llm-small,version=v2] 2
  alerts             LLMCostBurnRateHigh=firing
```

### B7. Số từ Prometheus cuối mỗi bài đo scaling

```text
--- snapshot: cuối bài đo 1 instance (17:22:09)
  instances_up       1
  traffic_rps        61.49
  rps_by_instance    [instance=172.20.0.5:8000] 61.49
  error_ratio        0.01005
  latency_avg_s      0.2393
  latency_p95_s      0.3031
  llm_p95_s          0.198
  tokens_per_s       [type=input] 4536; [type=output] 2410
  cost_usd_per_hour  2.938
  retrieval_per_s    [result=hit] 55.45; [result=miss] 6.109
  agent_info         [model=mock-llm-small,version=v2] 1
  alerts             LLMCostBurnRateHigh=pending
--- snapshot: cuối bài đo 3 instance (17:24:38)
  instances_up       3
  traffic_rps        62.02
  rps_by_instance    [instance=172.20.0.5:8000] 20.45; [instance=172.20.0.8:8000] 20.8; [instance=172.20.0.9:8000] 20.76
  error_ratio        0.009675
  latency_avg_s      0.2317
  latency_p95_s      0.2931
  llm_p95_s          0.1979
  tokens_per_s       [type=input] 4535; [type=output] 2414
  cost_usd_per_hour  5.914
  retrieval_per_s    [result=hit] 54.91; [result=miss] 7.127
  agent_info         [model=mock-llm-small,version=v2] 3
  alerts             LLMCostBurnRateHigh=firing
```

### B8. Thời gian alert firing

```text
trước A: LLMCostBurnRateHigh=firing
A (MOCK_ERROR_RATE=0.2) | AgentHighErrorRate | pending sau 26s | FIRING sau 86s
trước B: AgentHighErrorRate=firing, LLMCostBurnRateHigh=firing
B (MOCK_SLOW_RATE=0.3, khi A vẫn bật) | AgentHighLatencyP95 | pending sau 24s | FIRING sau 144s
B: chờ alert A firing lại | AgentHighErrorRate | pending sau không quan sát được | FIRING sau 0s
lúc chụp: AgentHighErrorRate=firing, AgentHighLatencyP95=firing
sau khi chụp: AgentHighErrorRate=firing, AgentHighLatencyP95=firing
trước C: không có alert nào pending/firing
C (mock-llm-large) | LLMCostBurnRateHigh | pending sau 24s | FIRING sau 144s
trước D: LLMCostBurnRateHigh=firing
D (docker pause) | AgentInstanceDown | pending sau 10s | FIRING sau 40s
trước E: LLMCostBurnRateHigh=firing
E (AGENT_VERSION=v1), sau 3 phút: không có alert nào pending/firing
```

### B9. Số từ Prometheus trong các thí nghiệm

```text
--- snapshot: A+B đang bật (17:39:08)
  instances_up       2
  traffic_rps        15.16
  rps_by_instance    [instance=172.20.0.5:8000] 7.509; [instance=172.20.0.8:8000] 7.655
  error_ratio        0.2086
  latency_avg_s      0.5854
  latency_p95_s      1.899
  llm_p95_s          1.92
  tokens_per_s       [type=input] 879.4; [type=output] 466.5
  cost_usd_per_hour  1.62
  retrieval_per_s    [result=hit] 13.27; [result=miss] 1.964
  agent_info         [model=mock-llm-small,version=v2] 2
  alerts             AgentHighErrorRate=firing, AgentHighLatencyP95=firing
--- snapshot: mặc định trước C (17:44:00)
  instances_up       2
  traffic_rps        18.21
  rps_by_instance    [instance=172.20.0.5:8000] 9.024; [instance=172.20.0.8:8000] 9.182
  error_ratio        0.01331
  latency_avg_s      0.2284
  latency_p95_s      0.2926
  llm_p95_s          0.1977
  tokens_per_s       [type=input] 1327; [type=output] 705.1
  cost_usd_per_hour  1.675
  retrieval_per_s    [result=hit] 16.22; [result=miss] 2.018
  agent_info         [model=mock-llm-small,version=v2] 2
  alerts             không có alert nào pending/firing
--- snapshot: C: model lớn (17:47:54)
  instances_up       2
  traffic_rps        16.03
  rps_by_instance    [instance=172.20.0.5:8000] 8.073; [instance=172.20.0.8:8000] 7.962
  error_ratio        0.006802
  latency_avg_s      0.4884
  latency_p95_s      0.7117
  llm_p95_s          0.4958
  tokens_per_s       [type=input] 1189; [type=output] 633.6
  cost_usd_per_hour  25.04
  retrieval_per_s    [result=hit] 14.38; [result=miss] 1.563
  agent_info         [model=mock-llm-large,version=v2] 2
  alerts             LLMCostBurnRateHigh=firing
--- snapshot: D: 1 instance bị pause (17:50:02)
  instances_up       1
  traffic_rps        13.67
  rps_by_instance    [instance=172.20.0.8:8000] 13.67
  error_ratio        0.009309
  latency_avg_s      0.2354
  latency_p95_s      0.2937
  llm_p95_s          0.198
  tokens_per_s       [type=input] 1002; [type=output] 532.5
  cost_usd_per_hour  19.74
  retrieval_per_s    [result=hit] 12.25; [result=miss] 1.473
  agent_info         [model=mock-llm-small,version=v2] 1
  alerts             AgentInstanceDown=firing, LLMCostBurnRateHigh=firing
--- snapshot: E: agent v1 (19:07:19)
  instances_up       2
  traffic_rps        18.87
  rps_by_instance    [instance=172.20.0.5:8000] 9.363; [instance=172.20.0.8:8000] 9.509
  error_ratio        0.0106
  latency_avg_s      0.2068
  latency_p95_s      0.1993
  llm_p95_s          0.198
  tokens_per_s       [type=input] 680.2; [type=output] 370.9
  cost_usd_per_hour  0.5748
  retrieval_per_s    (không có dữ liệu)
  agent_info         [model=mock-llm-small,version=v1] 2
  alerts             không có alert nào pending/firing
```

### B10. Log Nginx của thí nghiệm D

```text
Nginx tu luc pause: so dong theo ma HTTP cua /ask
    803 " 200 
      7 " 503 
     29 " 504 
2026/11/26 10:49:12 [error] 30#30: *1711 upstream timed out (110: Operation timed out) while reading response header from upstream, client: 172.20.0.9, server: , request: "POST /ask HTTP/1.1", upstream: "http://172.20.0.5:8000/ask", host: "nginx"
2026/11/26 10:49:12 [error] 30#30: *1740 upstream timed out (110: Operation timed out) while reading response header from upstream, client: 172.20.0.9, server: , request: "POST /ask HTTP/1.1", upstream: "http://172.20.0.5:8000/ask", host: "nginx"
2026/11/26 10:49:12 [error] 30#30: *1714 upstream timed out (110: Operation timed out) while reading response header from upstream, client: 172.20.0.9, server: , request: "POST /ask HTTP/1.1", upstream: "http://172.20.0.5:8000/ask", host: "nginx"
```

### B11. Span của trace chậm và trace lỗi

```text
trace slow: 42b25eefded02a371b51fcb89b3aab25
URL: http://localhost:16686/trace/42b25eefded02a371b51fcb89b3aab25
tong thoi gian: 1716.2 ms
spans:
  POST /ask                       1716.2 ms  (100%)
  agent.run                       1713.4 ms  (100%)
  agent.retrieve_context            26.9 ms  (2%)
  chat mock-llm-small             1686.3 ms  (98%)

trace error: 4d67ce6fab0838ffc33fefb8361a3cd8
URL: http://localhost:16686/trace/4d67ce6fab0838ffc33fefb8361a3cd8
tong thoi gian: 99.3 ms
spans:
  POST /ask                         99.3 ms  (100%)
  agent.run                         97.9 ms  (99%)
      event exception: utils.mock_llm.LLMError: Upstream LLM error: 503 Service Unavailable (mock)
  agent.retrieve_context            25.4 ms  (26%)
  chat mock-llm-small               72.1 ms  (73%)
      event exception: utils.mock_llm.LLMError: Upstream LLM error: 503 Service Unavailable (mock)

2026-11-26 19:20:03 +0700  chup lai 2 anh Jaeger (retake_traces.sh, cau hinh mac dinh, 2 agent)
2026-11-26 19:31:25 +0700  chup lai anh Jaeger (retake_traces.sh ONLY=error, cau hinh mac dinh, 2 agent)
```
