#!/usr/bin/env bash
# Live, readable stream of OPA policy decisions — the control plane's "why".
# Each line: time · ALLOW/DENY · tool · args · (deny reason). Ctrl+C to stop.
# Used by `make logs-opa`. Optional arg = how many past lines to show first.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
exec docker compose logs -f --tail="${1:-30}" opa 2>/dev/null | python3 -u -c '
import sys, json
for line in sys.stdin:
    i = line.find("{")
    if i < 0:
        continue
    try:
        d = json.loads(line[i:])
    except Exception:
        continue
    if d.get("msg") != "Decision Log":
        continue
    inp = d.get("input", {}); r = d.get("result", {})
    tool = inp.get("resource", {}).get("id", "?")
    args = json.dumps(inp.get("context", {}).get("tool_args", {}))
    allow = r.get("allow")
    verdict = "ALLOW" if allow else "DENY "
    why = "" if allow else ("  -> " + (r.get("deny") or [""])[0])
    print("%s  %s  %-20s %s%s" % (d.get("time", ""), verdict, tool, args, why), flush=True)
'
