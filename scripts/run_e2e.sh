#!/usr/bin/env bash
# One-shot runner for the E2E suites (scripts/e2e.py + scripts/e2e_c.py).
#
# Brings up a throwaway SQLite database and a zweq server, bootstraps an admin,
# runs both suites, then tears everything down. Safe to re-run.
#
#   ./scripts/run_e2e.sh
#
# Env overrides: ZWEQ_E2E_DB, ZWEQ_E2E_PORT, ZWEQ_E2E_EMAIL, ZWEQ_E2E_PASSWORD
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

DB=${ZWEQ_E2E_DB:-/tmp/zweq_e2e.db}
PORT=${ZWEQ_E2E_PORT:-8391}
EMAIL=${ZWEQ_E2E_EMAIL:-admin@e2e.test}
PASSWORD=${ZWEQ_E2E_PASSWORD:-secret123}
TOKEN_FILE=${ZWEQ_E2E_TOKEN_FILE:-/tmp/zweq_e2e_token}
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
ZWEQ_SQLITE_PATH="$DB" ./zig-out/bin/zweq >/tmp/zweq_e2e_boot.log 2>&1 &
BOOT_PID=$!
sleep 4
kill "$BOOT_PID" 2>/dev/null
wait "$BOOT_PID" 2>/dev/null

echo "== bootstrap admin =="
ZWEQ_SQLITE_PATH="$DB" ./zig-out/bin/zweq-admin \
  create-admin --email "$EMAIL" --password "$PASSWORD" --name E2E || exit 1

echo "== start server (port $PORT) =="
ZWEQ_SQLITE_PATH="$DB" ZWEQ_HTTP_PORT="$PORT" \
  ./zig-out/bin/zweq >/tmp/zweq_e2e_srv.log 2>&1 &
SRV_PID=$!

# Wait for the login endpoint to answer rather than sleeping a fixed amount.
for _ in $(seq 1 30); do
  if curl -sf -X POST "$BASE/auth/login" \
       -H 'Content-Type: application/json' \
       -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
       -o /tmp/zweq_e2e_login.json 2>/dev/null; then
    break
  fi
  sleep 1
done

python3 -c 'import json,sys; print(json.load(open("/tmp/zweq_e2e_login.json"))["data"]["token"])' \
  > "$TOKEN_FILE" || { echo "login failed; server log:"; cat /tmp/zweq_e2e_srv.log; exit 1; }

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
# panic 与未停机直接判失败；泄漏则逐块归因（见下方豁免说明）。
if grep -qi "panic" /tmp/zweq_e2e_srv.log 2>/dev/null; then
  echo "shutdown gate FAILED — panic in server log:"
  grep -ni "panic" /tmp/zweq_e2e_srv.log | head -10
  gate_rc=1
fi
if grep -qi "leaked" /tmp/zweq_e2e_srv.log 2>/dev/null; then
  # 已确认的上游泄漏豁免：zigmodu ≤ v0.15.47 的 SecurityModule.base64UrlDecode /
  # base64Decode 在 `decoder.decode` 失败时不释放已分配的缓冲（无效 token 的
  # header/payload 段触发，每次验签失败漏一小块）。修复是每函数两行 errdefer，
  # 归 zigmodu 仓库；本仓库升级到带修复的发布版后必须删除这段豁免。
  bad=$(awk '
    /^error\(SafeAllocator\): leaked/ { left=6; known=0; next }
    left > 0 {
      left--;
      if ($0 ~ /SecurityModule\.zig/ && $0 ~ /base64UrlDecode|base64Decode/) known=1;
      if (left == 0 && !known) print "  leak block ending at line " NR " is NOT the known upstream site";
    }
  ' /tmp/zweq_e2e_srv.log)
  if [ -n "$bad" ]; then
    echo "shutdown gate FAILED — leaked allocations in server log:"
    echo "$bad"
    grep -ni "leaked" /tmp/zweq_e2e_srv.log | head -10
    gate_rc=1
  else
    echo "shutdown gate OK — our leaks: 0（已豁免已确认的 zigmodu base64UrlDecode 上游泄漏）"
  fi
else
  echo "shutdown gate OK — no leaked allocations, no panic (log: /tmp/zweq_e2e_srv.log)"
fi
[ "$gate_rc" -ne 0 ] && rc=1

echo
if [ "$rc" -eq 0 ]; then
  echo "E2E OK — all suites passed"
else
  echo "E2E FAILED — see output above (server log: /tmp/zweq_e2e_srv.log)"
fi
exit "$rc"
