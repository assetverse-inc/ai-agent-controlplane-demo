#!/usr/bin/env python3
"""Idempotent seed: register the 4 MCP servers + 2 A2A agents, build the FinOps
and Treasury virtual servers, and print their UUIDs + a viewer token.

Run from the host (gateway published on :4444):
    ADMIN_TOKEN=... uv run --with httpx python gateway/seed/seed.py
"""
import os
import sys
import time

import httpx

BASE = os.environ.get("GATEWAY_URL", "http://localhost:4444")
TOKEN = os.environ.get("ADMIN_TOKEN", "")
if not TOKEN:
    sys.exit("ADMIN_TOKEN env required")
H = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}

# gateway reaches backends by Compose service name (not localhost)
MCP = {
    "expense-db": "http://expense-db:8000/mcp",
    "erp-payments": "http://erp-payments:8000/mcp",
    "policy-docs": "http://policy-docs:8000/mcp",
    "notify": "http://notify:8000/mcp",
    # operator surface (ContextForge's own management/observability as MCP tools)
    "controlplane": "http://controlplane:8000/mcp",
}
A2A = {
    "auditor": "http://auditor:9001/",
    "payments": "http://payments:3000/jsonrpc",
}


def api(method, path, **kw):
    r = httpx.request(method, BASE + path, headers=H, timeout=60, **kw)
    return r


def jget(path):
    r = api("GET", path)
    try:
        return r.json()
    except Exception:
        return []


def main():
    # 1) MCP backends -------------------------------------------------------
    existing = {g.get("name") for g in jget("/gateways")}
    for name, url in MCP.items():
        if name in existing:
            print(f"[gw] exists: {name}")
            continue
        r = api("POST", "/gateways", json={
            "name": name, "url": url, "transport": "STREAMABLEHTTP",
            "description": f"{name} MCP server",
        })
        print(f"[gw] register {name}: {r.status_code} {r.text[:160]}")

    # The operator demo has Bob register 'fx-rates' LIVE; ensure it starts
    # UNregistered on every seed so the beat is repeatable without a full reset.
    for g in jget("/gateways"):
        if g.get("name") == "fx-rates":
            api("DELETE", f"/gateways/{g['id']}")
            print("[gw] removed fx-rates (reserved for the operator demo to register live)")

    # 2) A2A agents ---------------------------------------------------------
    existing_a = {a.get("name") for a in jget("/a2a")}
    for name, url in A2A.items():
        if name in existing_a:
            print(f"[a2a] exists: {name}")
            continue
        r = api("POST", "/a2a", json={"agent": {
            "name": name, "endpoint_url": url, "agent_type": "jsonrpc",
            "description": f"{name} A2A agent", "tags": ["finbyte"],
        }})
        print(f"[a2a] register {name}: {r.status_code} {r.text[:240]}")

    # 3) discover tool ids (gateway may prefix names) -----------------------
    time.sleep(3)
    tools = jget("/tools")
    tmap = {}
    for t in tools:
        n = t.get("name") or t.get("originalName") or ""
        tid = t.get("id")
        if n and tid:
            tmap[n] = tid
    print(f"[tools] {sorted(tmap)}")

    def norm(s):
        return s.lower().replace("_", "").replace("-", "")

    def ids(*names):
        out = []
        for n in names:
            nn = norm(n)
            for tn, tid in tmap.items():
                tnn = norm(tn)
                if tnn == nn or tnn.endswith(nn) or nn in tnn:
                    out.append(tid)
                    break
            else:
                print(f"[warn] tool not found: {n}")
        return out

    # 4) virtual servers ----------------------------------------------------
    finops = ids("list_pending_expenses", "get_expense", "get_receipt",
                 "approve", "reimburse", "get_policy", "wire_limit", "a2a_auditor")
    treasury = ids("wire", "reimburse", "a2a_payments")
    # Operator persona: privileged platform-operations scope (deliberately
    # separate from the least-privilege FinOps analyst — the analyst cannot
    # register servers or read the audit trail; the operator can).
    operator = ids("register_mcp_server", "list_control_plane",
                   "recent_blocks", "evaluate_policy")
    # delete+recreate so re-running fixes tool associations
    by_name = {s.get("name"): s.get("id") for s in jget("/servers")}
    for sname, tids in [("FinOps", finops), ("Treasury", treasury), ("Operator", operator)]:
        if sname in by_name:
            d = api("DELETE", f"/servers/{by_name[sname]}")
            print(f"[server] delete existing {sname}: {d.status_code}")
        r = api("POST", "/servers", json={"server": {
            "name": sname, "description": f"{sname} virtual server",
            "associated_tools": tids,
        }})
        print(f"[server] create {sname} ({len(tids)} tools): {r.status_code} {r.text[:160]}")

    print("\n=== virtual servers (use the FinOps UUID for Bob's mcp.json) ===")
    for s in jget("/servers"):
        print(f"  {s.get('name'):10s} {s.get('id')}")


if __name__ == "__main__":
    main()
