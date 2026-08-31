#!/usr/bin/env python3
"""E2E — C-side (fan-facing) half of the `status` feature.

Verifies that off-shelf records are invisible *and* unusable through the real
`/app/*` fan routes, using a genuine fan JWT (roles=["fan"], sub=openid)
obtained from `POST /shop/auth/login`.

Self-sufficient: creates its own account and fixtures, and identifies rows by
id (never by title) so it is immune to leftovers from other suites.

Usage:
    ZWEQ_E2E_BASE=http://127.0.0.1:8391/api/v1 python3 scripts/e2e_c.py

Env:
    ZWEQ_E2E_BASE        default http://127.0.0.1:8391/api/v1
    ZWEQ_E2E_TOKEN       admin JWT (or put it in $ZWEQ_E2E_TOKEN_FILE)
    ZWEQ_E2E_TOKEN_FILE  default /tmp/zweq_e2e_token
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("ZWEQ_E2E_BASE", "http://127.0.0.1:8391/api/v1")
TOKEN_FILE = os.environ.get("ZWEQ_E2E_TOKEN_FILE", "/tmp/zweq_e2e_token")
ADMIN = os.environ.get("ZWEQ_E2E_TOKEN") or open(TOKEN_FILE).read().strip()

FAN = "fan_c_suite"
passed = failed = 0


def call(method, path, body=None, token=None):
    req = urllib.request.Request(BASE + path,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 method=method)
    req.add_header("Authorization", f"Bearer {token or ADMIN}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read()) if e.fp else {}


def ok(http, payload):
    return http in (200, 201) and payload.get("code") == 0


def data(payload):
    d = payload.get("data")
    return d if d is not None else {}


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}  {detail}")


def ids_of(payload):
    return sorted(x["id"] for x in data(payload).get("list", []))


# ── setup: admin creates fixture data ─────────────────────────────
print("== setup ==")
h, p = call("POST", "/accounts", {"name": "E2E-fan", "kind": "wechat"})
acc = data(p).get("id")
check("create account", ok(h, p) and acc, f"{h} {p}")
if not acc:
    sys.exit("cannot continue without an account")
Q = f"account_id={acc}"

h, p = call("POST", "/coupons", {"account_id": acc, "title": "C-下架券", "amount": 500,
                                 "total": 10, "per_user": 1, "status": 0})
off_c = data(p).get("id")
check("create off-shelf coupon", ok(h, p) and off_c, f"{h} {p}")

h, p = call("POST", "/coupons", {"account_id": acc, "title": "C-在售券", "amount": 500,
                                 "total": 10, "per_user": 1, "status": 1})
on_c = data(p).get("id")
check("create on-shelf coupon", ok(h, p) and on_c, f"{h} {p}")

h, p = call("POST", f"/points/products?{Q}", {"account_id": acc, "name": "C-下架商品",
                                              "points": 10, "stock": 5, "status": 0})
off_pp = data(p).get("id")
check("create off-shelf points product", ok(h, p) and off_pp, f"{h} {p}")

h, p = call("POST", "/seckills", {"account_id": acc, "title": "C-下架秒杀", "price": 100,
                                  "stock": 10, "per_user": 1, "status": 0})
off_s = data(p).get("id")
check("create off-shelf activity", ok(h, p) and off_s, f"{h} {p}")

# ── fan identity ──────────────────────────────────────────────────
print("\n== fan auth ==")
# NOTE: C-login upserts unknown openids as fans, so this also provisions FAN.
h, p = call("POST", "/shop/auth/login", {"openid": FAN, "account_id": acc})
fan = data(p).get("token")
check("C-login issues fan token", ok(h, p) and fan, f"{h} {p}")
if not fan:
    sys.exit("cannot continue without a fan token")

h, p = call("GET", f"/app/coupons?{Q}", token="garbage.token.here")
check("C routes reject an invalid token", not ok(h, p), f"{h} {p}")

# ── visibility ────────────────────────────────────────────────────
print("\n== C-side visibility ==")
h, p = call("GET", f"/app/coupons?{Q}", token=fan)
ids = ids_of(p)
check("C coupon list hides off-shelf", ok(h, p) and off_c not in ids, f"{ids} {h} {p}")
check("C coupon list shows on-shelf (non-vacuous)", ok(h, p) and on_c in ids, str(ids))

h, p = call("GET", f"/app/points/products?{Q}", token=fan)
ids = ids_of(p)
check("C points list hides off-shelf", ok(h, p) and off_pp not in ids, f"{ids} {h} {p}")

h, p = call("GET", f"/app/seckill/activities?{Q}", token=fan)
ids = ids_of(p)
check("C seckill list hides off-shelf", ok(h, p) and off_s not in ids, f"{ids} {h} {p}")

# ── usability ─────────────────────────────────────────────────────
print("\n== C-side usability ==")
h, p = call("POST", f"/app/coupons/{off_c}/claim", {"account_id": acc}, token=fan)
check("C claim OFF-SHELF coupon REJECTED", not ok(h, p), f"{h} {p}")

h, p = call("POST", f"/app/coupons/{on_c}/claim", {"account_id": acc}, token=fan)
check("C claim ON-SHELF coupon succeeds", ok(h, p), f"{h} {p}")

h, p = call("POST", "/app/points/redeem",
            {"account_id": acc, "product_id": off_pp}, token=fan)
check("C redeem OFF-SHELF product REJECTED", not ok(h, p), f"{h} {p}")

h, p = call("POST", f"/app/seckill/activities/{off_s}/rush",
            {"account_id": acc, "openid": FAN, "quantity": 1}, token=fan)
check("C rush OFF-SHELF activity REJECTED", not ok(h, p), f"{h} {p}")

print(f"\n==== {passed} passed, {failed} failed ====")
sys.exit(1 if failed else 0)
