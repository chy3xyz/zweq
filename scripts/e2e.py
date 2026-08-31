#!/usr/bin/env python3
"""E2E — admin side of the `status` (上架/下架 / 启用-停用) feature.

Exercises, over real HTTP against a running zweq server:
  * admin list filters (`?status=-1|0|1`) for coupon / points / seckill / member-card
  * keyword search alongside the status filter
  * creating records with an explicit status
  * the `PUT /{id}/status` toggle endpoints
  * that off-shelf records are rejected by the shared service guards
    (claim / redeem / rush / auto-assigned member level)

Every "excludes" assertion is paired with a "includes" assertion so that an
empty result set can never pass vacuously.

Usage:
    # server must already be running; see scripts/run_e2e.sh for a one-shot runner
    ZWEQ_E2E_BASE=http://127.0.0.1:8391/api/v1 python3 scripts/e2e.py

Env:
    ZWEQ_E2E_BASE        default http://127.0.0.1:8391/api/v1
    ZWEQ_E2E_TOKEN       admin JWT (or put it in $ZWEQ_E2E_TOKEN_FILE)
    ZWEQ_E2E_TOKEN_FILE  default /tmp/zweq_e2e_token
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("ZWEQ_E2E_BASE", "http://127.0.0.1:8391/api/v1")
TOKEN_FILE = os.environ.get("ZWEQ_E2E_TOKEN_FILE", "/tmp/zweq_e2e_token")
TOKEN = os.environ.get("ZWEQ_E2E_TOKEN") or open(TOKEN_FILE).read().strip()

FAN = "fan_admin_suite"
passed = failed = 0


def call(method, path, body=None, token=TOKEN):
    """Perform a JSON API call; returns (http_status, parsed_body)."""
    req = urllib.request.Request(BASE + path,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 method=method)
    req.add_header("Authorization", f"Bearer {token or ''}")
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


def names_of(payload, key):
    return sorted(x[key] for x in data(payload).get("list", []))


def ids_of(payload):
    return sorted(x["id"] for x in data(payload).get("list", []))


# ── setup ─────────────────────────────────────────────────────────
print("== setup ==")
h, p = call("POST", "/accounts", {"name": "E2E-admin", "kind": "wechat"})
acc = data(p).get("id")
check("create account", ok(h, p) and acc, f"{h} {p}")
if not acc:
    sys.exit("cannot continue without an account")
Q = f"account_id={acc}"
print(f"  account_id={acc}")

# Provision the fan (C-login upserts unknown openids) then grant it points, so
# the points-redeem guard can be tested without touching the DB directly.
h, p = call("POST", "/shop/auth/login", {"openid": FAN, "account_id": acc})
check("provision fan via C-login", ok(h, p), f"{h} {p}")
h, p = call("POST", f"/points/adjust?{Q}", {"account_id": acc, "openid": FAN, "delta": 1000})
check("grant fan 1000 points", ok(h, p), f"{h} {p}")

# ── coupon ────────────────────────────────────────────────────────
print("\n== coupon ==")
h, p = call("POST", "/coupons", {"account_id": acc, "title": "在售券", "amount": 1000,
                                 "min_amount": 0, "total": 10, "per_user": 1, "status": 1})
on_c = data(p).get("id")
check("create on-shelf coupon", ok(h, p) and on_c, f"{h} {p}")

h, p = call("POST", "/coupons", {"account_id": acc, "title": "下架券", "amount": 1000,
                                 "min_amount": 0, "total": 10, "per_user": 1, "status": 0})
off_c = data(p).get("id")
check("create off-shelf coupon", ok(h, p) and off_c, f"{h} {p}")

for qs, want in [(-1, 2), (1, 1), (0, 1)]:
    h, p = call("GET", f"/coupons?{Q}&status={qs}")
    check(f"list status={qs} -> {want} item(s)", ok(h, p) and len(data(p).get("list", [])) == want,
          f"{h} {p}")

h, p = call("GET", f"/coupons?{Q}&status=1")
ids = ids_of(p)
check("status=1 excludes off-shelf coupon", ok(h, p) and off_c not in ids, f"{ids} {h} {p}")
check("status=1 includes on-shelf coupon (non-vacuous)", ok(h, p) and on_c in ids, str(ids))

h, p = call("GET", f"/coupons?{Q}&keyword={urllib.parse.quote('在售')}")
check("keyword+status search -> 1", ok(h, p) and len(data(p).get("list", [])) == 1, f"{h} {p}")

h, p = call("POST", f"/coupons/{off_c}/claim", {"openid": "fan_a"})
check("claim OFF-SHELF coupon REJECTED", not ok(h, p), f"{h} {p}")

h, p = call("POST", f"/coupons/{on_c}/claim", {"openid": "fan_a"})
check("claim ON-SHELF coupon succeeds", ok(h, p) and data(p).get("code"), f"{h} {p}")

h, p = call("PUT", f"/coupons/{off_c}/status", {"status": 1})
check("toggle off-shelf -> on-shelf", ok(h, p), f"{h} {p}")

h, p = call("GET", f"/coupons?{Q}&status=1")
check("after toggle, status=1 -> 2 items", ok(h, p) and len(data(p).get("list", [])) == 2, f"{h} {p}")

h, p = call("POST", f"/coupons/{off_c}/claim", {"openid": "fan_b"})
check("claim previously-off-shelf now succeeds", ok(h, p), f"{h} {p}")

# ── seckill ───────────────────────────────────────────────────────
print("\n== seckill ==")
h, p = call("POST", "/seckills", {"account_id": acc, "title": "下架秒杀", "price": 100,
                                  "original_price": 500, "stock": 10, "per_user": 1, "status": 0})
off_s = data(p).get("id")
check("create off-shelf activity", ok(h, p) and off_s, f"{h} {p}")

h, p = call("POST", "/seckills", {"account_id": acc, "title": "在售秒杀", "price": 100,
                                  "original_price": 500, "stock": 10, "per_user": 1, "status": 1})
on_s = data(p).get("id")
check("create on-shelf activity", ok(h, p) and on_s, f"{h} {p}")

h, p = call("GET", f"/seckills?{Q}&status=1")
ids = ids_of(p)
check("status=1 excludes off-shelf activity", ok(h, p) and off_s not in ids, f"{ids} {h} {p}")
check("status=1 includes on-shelf activity (non-vacuous)", ok(h, p) and on_s in ids, str(ids))

h, p = call("POST", f"/seckills/{off_s}/rush", {"openid": "fan_c", "quantity": 1})
check("rush OFF-SHELF activity REJECTED", not ok(h, p), f"{h} {p}")

h, p = call("POST", f"/seckills/{on_s}/rush", {"openid": "fan_c", "quantity": 1})
check("rush ON-SHELF activity succeeds", ok(h, p), f"{h} {p}")

# ── member_card (启用/停用) ───────────────────────────────────────
print("\n== member_card (启用/停用) ==")
h, p = call("POST", "/member-cards", {"account_id": acc, "name": "停用等级", "level": 1,
                                      "discount": 900, "points_ratio": 100, "threshold": 0, "status": 0})
off_l = data(p).get("id")
check("create disabled level", ok(h, p) and off_l, f"{h} {p}")

h, p = call("POST", "/member-cards", {"account_id": acc, "name": "启用等级", "level": 2,
                                      "discount": 950, "points_ratio": 100, "threshold": 5, "status": 1})
on_l = data(p).get("id")
check("create enabled level", ok(h, p) and on_l, f"{h} {p}")

h, p = call("GET", f"/member-cards?{Q}&status=1")
ids = ids_of(p)
check("status=1 excludes disabled level", ok(h, p) and off_l not in ids, f"{ids} {h} {p}")
check("status=1 includes enabled level (non-vacuous)", ok(h, p) and on_l in ids, str(ids))

h, p = call("POST", f"/member-cards/open?{Q}", {"openid": "fan_mc"})
check("open member card", ok(h, p), f"{h} {p}")

h, p = call("GET", f"/member-cards/members?{Q}")
rows = data(p).get("list", [])
lv = rows[0].get("level_id") if rows else None
check("new member NOT auto-assigned the disabled level", lv == on_l,
      f"level_id={lv} disabled={off_l} enabled={on_l}")

# ── points ────────────────────────────────────────────────────────
print("\n== points ==")
h, p = call("POST", f"/points/products?{Q}", {"account_id": acc, "name": "下架商品",
                                              "points": 10, "stock": 5, "status": 0})
off_pp = data(p).get("id")
check("create off-shelf points product", ok(h, p) and off_pp, f"{h} {p}")

h, p = call("POST", f"/points/products?{Q}", {"account_id": acc, "name": "在售商品",
                                              "points": 10, "stock": 5, "status": 1})
on_pp = data(p).get("id")
check("create on-shelf points product", ok(h, p) and on_pp, f"{h} {p}")

h, p = call("GET", f"/points/products?{Q}&status=1")
ids = ids_of(p)
check("status=1 excludes off-shelf product", ok(h, p) and off_pp not in ids, f"{ids} {h} {p}")
check("status=1 includes on-shelf product (non-vacuous)", ok(h, p) and on_pp in ids, str(ids))

h, p = call("POST", f"/points/redeem?{Q}", {"account_id": acc, "openid": FAN, "product_id": off_pp})
check("redeem OFF-SHELF product REJECTED", not ok(h, p), f"{h} {p}")

h, p = call("POST", f"/points/redeem?{Q}", {"account_id": acc, "openid": FAN, "product_id": on_pp})
check("redeem ON-SHELF product succeeds", ok(h, p), f"{h} {p}")

print(f"\n==== {passed} passed, {failed} failed ====")
sys.exit(1 if failed else 0)
