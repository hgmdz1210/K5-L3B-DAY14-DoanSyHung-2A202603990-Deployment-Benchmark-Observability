# Benchmark & Observability Report — Day 14

> Mọi con số ở Mục 1–3 lấy từ file trong `reports/`, tạo bởi một lần chạy `bash 06-lab-complete/benchmark-observability/develop/run_cp7.sh`. Log toàn bộ lần chạy: [run_log.txt](reports/run_log.txt).

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

**Ở concurrency 100, phần chậm nằm ngoài phần xử lý của server, nhiều khả năng ở công cụ tạo tải.** Phép đo riêng ([diag_load_generator.txt](reports/diag_load_generator.txt)):

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
- Đã thử gate: chạy v1 so với baseline v2 cho exit code 1 với 20 regression ([gate_demo_v1_vs_v2.txt](reports/gate_demo_v1_vs_v2.txt)).
- Các lệnh của job đã chạy thử trên máy local, exit code 0 ([ci_local.txt](reports/ci_local.txt)). Job chưa chạy trên GitHub Actions.

---

## 4. Observability stack (production)

### 4.1 Screenshot

- [ ] Dashboard Grafana khi đang có tải (thấy rõ Golden Signals)
- [ ] Một trace chậm trong Jaeger (thấy span nào chiếm thời gian)
- [ ] Một trace lỗi trong Jaeger (có event `exception`)
- [ ] Trang Alerts của Prometheus với ít nhất 1 alert đang **firing**

### 4.2 Thí nghiệm "phá hệ thống"

| # | Thay đổi | Alert nào firing | Thời gian từ lúc đổi → firing | Panel nào phản ánh rõ nhất |
|---|---|---|---|---|
| A | `MOCK_ERROR_RATE=0.2` | | | |
| B | `MOCK_SLOW_RATE=0.3` | | | |
| C | `LLM_MODEL=mock-llm-large` | | | |
| D | `docker pause` 1 instance | | | |
| E | `AGENT_VERSION=v1` | | | |

**Thí nghiệm E không làm alert nào firing. Bạn sẽ phát hiện loại sự cố này trong production bằng cách nào?**

...

### 4.3 Debug bằng trace

Chọn 1 trace chậm nhất bạn tìm được:

- `trace_id`: ...
- Tổng thời gian: ... ms
- Span chiếm nhiều thời gian nhất: ... (... ms, ...%)
- Dòng log tương ứng (grep theo `trace_id`):

```json

```

---

## 5. Benchmark scaling (production, Locust headless, 100 users, 2 phút)

| Số instance | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Failures |
|---|---|---|---|---|---|
| 1 | | | | | |
| 3 | | | | | |

**Giải thích kết quả:** Scale có cải thiện p95 không? Nút thắt nằm ở đâu?

...

---

## 6. Kết luận

- 3 điều bạn học được về benchmark & observability:
  1. ...
  2. ...
  3. ...
- Nếu đưa agent này lên production thật, bạn sẽ thêm metric / alert nào nữa?

...

---

## Phụ lục: Exercise 7.1 — Đọc metrics

Trích từ [metrics_v2.txt](reports/metrics_v2.txt).

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
