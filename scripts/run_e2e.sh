#!/usr/bin/env bash
# One-shot runner for the E2E suites (scripts/e2e.py + scripts/e2e_c.py).
#
# Brings up a throwaway SQLite database and a zweq server, bootstraps an admin,
# runs both suites, then tears everything down. Safe to re-run.
#
#   ./scripts/run_e2e.sh
#
# Env overrides: ZWEQ_E2E_DB, ZWEQ_E2E_PORT, ZWEQ_E2E_EMAIL, ZWEQ_E2E_PASSWORD,
#                ZWEQ_E2E_TOKEN_FILE, ZWEQ_E2E_TMPDIR (logs/temp files; default
#                a fresh mktemp -d so parallel runs never clobber each other)
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

DB=${ZWEQ_E2E_DB:-/tmp/zweq_e2e.db}
PORT=${ZWEQ_E2E_PORT:-8391}
EMAIL=${ZWEQ_E2E_EMAIL:-admin@e2e.test}
PASSWORD=${ZWEQ_E2E_PASSWORD:-secret123}
TOKEN_FILE=${ZWEQ_E2E_TOKEN_FILE:-/tmp/zweq_e2e_token}
# 日志与登录应答等临时文件统一进独立临时目录：默认 mktemp -d（每次一个新
# 目录），并行跑多个 e2e 实例互不覆盖；需要固定路径收集产物时用 ZWEQ_E2E_TMPDIR。
E2E_TMP=${ZWEQ_E2E_TMPDIR:-$(mktemp -d)}
mkdir -p "$E2E_TMP"
BOOT_LOG="$E2E_TMP/zweq_e2e_boot.log"
SRV_LOG="$E2E_TMP/zweq_e2e_srv.log"
LOGIN_JSON="$E2E_TMP/zweq_e2e_login.json"
BASE="http://127.0.0.1:${PORT}/api/v1"

export ZWEQ_E2E_BASE="$BASE"
export ZWEQ_E2E_TOKEN_FILE="$TOKEN_FILE"

SRV_PID=""

cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  wait "$SRV_PID" 2>/dev/null
}
trap cleanup EXIT

echo "== build =="
zig build || exit 1

echo "== fresh database =="
rm -f "$DB" "$DB-wal" "$DB-shm"

# zweq-admin only migrates 5 groups, so the app itself must run once first to
# create every table; otherwise create-admin has nowhere to write.
ZWEQ_SQLITE_PATH="$DB" ./zig-out/bin/zweq >"$BOOT_LOG" 2>&1 &
BOOT_PID=$!
sleep 4
kill "$BOOT_PID" 2>/dev/null
wait "$BOOT_PID" 2>/dev/null

echo "== bootstrap admin =="
ZWEQ_SQLITE_PATH="$DB" ./zig-out/bin/zweq-admin \
  create-admin --email "$EMAIL" --password "$PASSWORD" --name E2E || exit 1

echo "== start server (port $PORT) =="
ZWEQ_SQLITE_PATH="$DB" ZWEQ_HTTP_PORT="$PORT" \
  ./zig-out/bin/zweq >"$SRV_LOG" 2>&1 &
SRV_PID=$!

# Wait for the login endpoint to answer rather than sleeping a fixed amount.
for _ in $(seq 1 30); do
  if curl -sf -X POST "$BASE/auth/login" \
       -H 'Content-Type: application/json' \
       -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
       -o "$LOGIN_JSON" 2>/dev/null; then
    break
  fi
  sleep 1
done

python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["data"]["token"])' "$LOGIN_JSON" \
  > "$TOKEN_FILE" || { echo "login failed; server log:"; cat "$SRV_LOG"; exit 1; }

rc=0
echo
echo "########## admin suite ##########"
python3 scripts/e2e.py || rc=1
echo
echo "########## C-side (fan) suite ##########"
python3 scripts/e2e_c.py || rc=1

echo
echo "########## graceful shutdown + leak gate ##########"
# 优雅停机后扫服务日志：SafeAllocator 会在停机时逐条打印未释放分配（带分配栈），
# `panic` 说明进程异常中止。这一类缺陷编译与单测都拦不住——单测里请求 arena 与
# store 分配器同为 std.testing.allocator，分配器不匹配抓不到（曾因此漏掉 631 条
# 运行期泄漏，靠手工冒烟才发现）。这个门禁就是那次手工流程的固化。
gate_rc=0
if [ -n "$SRV_PID" ]; then
  kill -TERM "$SRV_PID" 2>/dev/null
  for _ in $(seq 1 20); do
    kill -0 "$SRV_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$SRV_PID" 2>/dev/null; then
    echo "shutdown gate FAILED — server still running 20s after SIGTERM"
    shutdown_stat=""
    kill -9 "$SRV_PID" 2>/dev/null
    gate_rc=1
  fi
  wait "$SRV_PID" 2>/dev/null
  SRV_PID=""
fi
# panic 与泄漏一律判失败。原先为 zigmodu ≤ v0.15.47 的 SecurityModule.base64UrlDecode
# 泄漏留过一段豁免；该 bug 已在上游修复（v0.33.0 的两处 `errdefer allocator.free(decoded)`
# 已在本地检出的源码里确认），故豁免已删除——门禁恢复严格。
if grep -qi "panic" "$SRV_LOG" 2>/dev/null; then
  echo "shutdown gate FAILED — panic in server log:"
  grep -ni "panic" "$SRV_LOG" | head -10
  gate_rc=1
fi
if grep -qi "leaked" "$SRV_LOG" 2>/dev/null; then
  echo "shutdown gate FAILED — leaked allocations in server log:"
  grep -ni "leaked" "$SRV_LOG" | head -10
  gate_rc=1
else
  echo "shutdown gate OK — no leaked allocations, no panic (log: $SRV_LOG)"
fi
[ "$gate_rc" -ne 0 ] && rc=1

echo
if [ "$rc" -eq 0 ]; then
  echo "E2E OK — all suites passed"
else
  echo "E2E FAILED — see output above (server log: $SRV_LOG)"
fi
exit "$rc"
