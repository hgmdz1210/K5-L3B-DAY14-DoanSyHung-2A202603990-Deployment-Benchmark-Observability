#!/usr/bin/env bash
# Chạy toàn bộ phép đo Part 7 bước 1 (Exercise 7.1–7.3) và lưu kết quả.
#
#   source ~/.venvs/day14/bin/activate
#   bash 06-lab-complete/benchmark-observability/develop/run_cp7.sh
#
# Script XOÁ các file .json/.txt cũ trong reports/ rồi tạo lại từ lần chạy này.

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DEV/../../.." && pwd)"
OUT="${OUT:-$DEV/reports}"
ROOT_OUT="${ROOT_OUT:-$REPO/reports}"
N="${N:-300}"                # số request mỗi lần load test
BASE_COMMIT=f1fb9f0          # commit có KNOWLEDGE_BASE gốc (chưa sửa)
KB_PATH=06-lab-complete/benchmark-observability/develop/utils/mock_llm.py

TMP="$(mktemp -d)"
PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT

die() { echo "LỖI: $*"; exit 1; }
busy() { ss -ltn | grep -q ":$1 "; }

# ── Kiểm tra trước khi xoá bất cứ thứ gì ─────────────────
python -c 'import fastapi, uvicorn, httpx, prometheus_client' 2>/dev/null \
  || die "thiếu thư viện. Chạy: source ~/.venvs/day14/bin/activate"
for p in 8000 8001 8002; do
  busy "$p" && die "cổng $p đang bận. Tắt server cũ (Ctrl+C) rồi chạy lại."
done
mkdir -p "$TMP/orig/utils"
cp "$DEV/app.py" "$TMP/orig/"
git -c safe.directory='*' -C "$REPO" show "$BASE_COMMIT:$KB_PATH" > "$TMP/orig/utils/mock_llm.py" \
  || die "không lấy được KNOWLEDGE_BASE gốc từ git"
grep -q 'autoscal' "$TMP/orig/utils/mock_llm.py" && die "KNOWLEDGE_BASE gốc không đúng"
grep -q 'autoscal' "$DEV/utils/mock_llm.py" || die "KNOWLEDGE_BASE hiện tại chưa được sửa"

unset MOCK_SLOW_RATE MOCK_ERROR_RATE MOCK_LATENCY_MS MOCK_JITTER_MS MOCK_SLOW_MS MOCK_RETRIEVAL_MS \
      LLM_MODEL AGENT_URL AGENT_API_KEY
export PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

mkdir -p "$OUT" "$ROOT_OUT"
rm -f "$OUT"/*.json "$OUT"/*.txt "$ROOT_OUT"/*.json "$ROOT_OUT"/*.txt

# start_agent <thư mục code> <version> <port> [BIẾN=giá_trị ...]
start_agent() {
  local dir=$1 v=$2 port=$3; shift 3
  ( cd "$dir" && exec env AGENT_VERSION="$v" PORT="$port" "$@" python app.py ) > "$TMP/agent_$port.log" 2>&1 &
  LAST=$!; PIDS+=("$LAST")
  for _ in $(seq 1 60); do
    curl -s -o /dev/null --max-time 2 "http://localhost:$port/health" && return 0
    sleep 0.5
  done
  tail -20 "$TMP/agent_$port.log"; die "agent $v không khởi động được ở cổng $port"
}
stop_agent() {
  kill "$1" 2>/dev/null; wait "$1" 2>/dev/null
}

# Đo thêm: latency phía client so với phía server, và CPU time của từng tiến trình
cat > "$TMP/measure.py" <<'EOF'
import json, os, resource, subprocess, sys, time
c, log, server_pid, out, n = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
def cpu(pid):
    f = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) / os.sysconf("SC_CLK_TCK")
offset = os.path.getsize(log)
s0, k0, t0 = cpu(server_pid), resource.getrusage(resource.RUSAGE_CHILDREN), time.time()
subprocess.run([sys.executable, "load_test.py", "--url", "http://localhost:8002", "--requests", n,
                "--concurrency", str(c), "--out", out], stdout=subprocess.DEVNULL)
wall, s1, k1 = time.time() - t0, cpu(server_pid), resource.getrusage(resource.RUSAGE_CHILDREN)
with open(log, encoding="utf-8") as fh:
    fh.seek(offset)
    ms = sorted(e["ms"] for e in (json.loads(l) for l in fh if l.startswith("{"))
                if e.get("event") == "http_request" and e.get("route") == "/ask" and e["status"] == 200)
pct = lambda p: ms[int((len(ms) - 1) * p / 100)]
r = json.load(open(out))
print(f"c={c:<4} rps={r['rps']:<7} client p50={r['latency_ms']['p50']:<7} p95={r['latency_ms']['p95']:<7} | "
      f"server p50={pct(50):<6} p95={pct(95):<6} | CPU s: server={s1 - s0:.2f} "
      f"load_test={k1.ru_utime + k1.ru_stime - k0.ru_utime - k0.ru_stime:.2f} "
      f"(wall {wall:.2f}s, test {r['duration_s']}s)")
EOF

main() {
  cd "$DEV" || exit 1
  {
    echo "date: $(date '+%Y-%m-%d %H:%M %z')"
    grep PRETTY /etc/os-release | cut -d'"' -f2
    echo "cpus: $(nproc)  mem: $(free -h | awk '/Mem:/{print $2}')  $(python --version)"
  } | tee "$OUT/environment.txt"

  echo; echo "########## 7.1 metrics"
  start_agent "$DEV" v2 8002; A=$LAST
  curl -s --max-time 10 -o /dev/null -w 'POST /ask -> %{http_code}\n' -X POST http://localhost:8002/ask \
    -H 'Content-Type: application/json' -d '{"question": "Prometheus thu thập metrics như thế nào?"}'
  for p in wp-admin .env a1b2c3; do
    echo "GET /$p -> $(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "http://localhost:8002/$p")"
  done
  curl -s --max-time 10 http://localhost:8002/metrics > "$OUT/metrics_v2.txt"
  grep -E '^(http_requests_total|agent_in_flight_requests|agent_question_length_chars)' "$OUT/metrics_v2.txt"
  stop_agent "$A"

  echo; echo "########## 7.2 concurrency (agent v2, cấu hình mặc định)"
  start_agent "$DEV" v2 8002; A=$LAST
  for c in 1 10 50 100; do
    python load_test.py --url http://localhost:8002 --requests "$N" --concurrency "$c" --out "$OUT/load_v2_c$c.json"
  done
  stop_agent "$A"

  echo "########## 7.2 tail latency (concurrency 20)"
  for s in 0 0.03 0.1; do
    start_agent "$DEV" v2 8002 MOCK_SLOW_RATE=$s; A=$LAST
    echo "--- MOCK_SLOW_RATE=$s"
    python load_test.py --url http://localhost:8002 --requests "$N" --concurrency 20 --out "$OUT/load_v2_slow_$s.json"
    stop_agent "$A"
  done

  echo "########## chẩn đoán concurrency 50 và 100"
  start_agent "$DEV" v2 8002; A=$LAST
  {
    echo "Chay rieng, khong ghi de load_v2_*.json. $N request moi lan, agent v2 mac dinh."
    for c in 50 100; do python "$TMP/measure.py" "$c" "$TMP/agent_8002.log" "$A" "$TMP/diag.json" "$N"; done
  } | tee "$OUT/diag_load_generator.txt"
  stop_agent "$A"

  echo; echo "########## 7.3 eval v1 và v2 (KNOWLEDGE_BASE gốc)"
  start_agent "$TMP/orig" v1 8001; A=$LAST
  start_agent "$TMP/orig" v2 8002; B=$LAST
  python eval/run_eval.py --url http://localhost:8001 --out "$OUT/eval_v1.json"
  echo "exit code eval v1: $?"
  python eval/run_eval.py --url http://localhost:8002 --out "$OUT/eval_v2.json" --baseline "$OUT/eval_v1.json"
  echo "exit code eval v2: $?"

  echo "########## thử quality gate: v1 so với baseline v2 (phải bị chặn)"
  python eval/run_eval.py --url http://localhost:8001 --baseline "$OUT/eval_v2.json" > "$OUT/gate_demo_v1_vs_v2.txt" 2>&1
  echo "exit code: $?" | tee -a "$OUT/gate_demo_v1_vs_v2.txt"
  stop_agent "$A"; stop_agent "$B"

  echo; echo "########## 7.3 eval v2 sau khi sửa KNOWLEDGE_BASE"
  start_agent "$DEV" v2 8002; A=$LAST
  python eval/run_eval.py --url http://localhost:8002 --min-accuracy 1.0 \
    --baseline "$OUT/eval_v2.json" --out "$OUT/eval_v2_fixed.json"
  echo "exit code eval cuối: $?"
  stop_agent "$A"

  echo "########## chạy thử các lệnh của job CI trên máy local"
  start_agent "$DEV" v2 8000 MOCK_ERROR_RATE=0; A=$LAST
  python eval/run_eval.py --url http://localhost:8000 --min-accuracy 0.85 \
    --baseline "$OUT/eval_v2_fixed.json" > "$OUT/ci_local.txt" 2>&1
  echo "exit code: $?" | tee -a "$OUT/ci_local.txt"
  grep -E 'Accuracy|Quality gate' "$OUT/ci_local.txt"
  stop_agent "$A"

  echo; echo "########## TÓM TẮT"
  python - "$OUT" <<'EOF'
import json, pathlib, sys
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.json")):
    r = json.loads(p.read_text())
    if "rps" in r:
        l = r["latency_ms"]
        print(f"{p.name:<24} n={r['total_requests']:<4} rps={r['rps']:<7} avg={l['avg']:<7} p50={l['p50']:<7} "
              f"p95={l['p95']:<7} p99={l['p99']:<7} err={r['error_rate']} slo={'PASS' if r['slo']['passed'] else 'FAIL'}")
    else:
        print(f"{p.name:<24} {r['agent_version']} {r['passed']}/{r['total']} tokens={r['avg_tokens']} "
              f"cost={r['total_cost_usd']} gate={'PASS' if r['quality_gate']['passed'] else 'FAIL'} errors={r['errors']}")
EOF
}

main 2>&1 | tee "$TMP/run_log.txt"
cp "$TMP/run_log.txt" "$OUT/run_log.txt"
cp "$OUT"/*.json "$OUT"/*.txt "$ROOT_OUT"/

count=$(ls "$OUT"/*.json 2>/dev/null | wc -l)
if [ "$count" -eq 10 ]; then
  echo; echo "XONG: đủ 10 file JSON trong $OUT và đã chép ra $ROOT_OUT"
else
  echo; echo "THIẾU: chỉ có $count/10 file JSON. Xem lại output phía trên."; exit 1
fi
