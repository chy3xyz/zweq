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
if [ "$rc" -eq 0 ]; then
  echo "E2E OK — all suites passed"
else
  echo "E2E FAILED — see output above (server log: /tmp/zweq_e2e_srv.log)"
fi
exit "$rc"
