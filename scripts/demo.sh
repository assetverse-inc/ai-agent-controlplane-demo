#!/usr/bin/env bash
# demo.sh — bulletproof, stage-gated end-to-end driver for the FinByte
# AI-agent control plane (ContextForge + 4 MCP servers + 2 cross-language A2A agents).
#
# Runs the WHOLE thing from a cold start and PAUSES after each stage so you
# choose when to advance (great for a live talk):
#   0  preflight       — docker/uv present, .env ready
#   1  bring up        — pull ContextForge image, build MCP+A2A, wait healthy
#   2  register        — seed: 4 MCP servers, 2 A2A agents, FinOps+Treasury vservers
#   3  scenario #1     — OPA policy: $50k blocked / $5k allowed / $50k+approval allowed
#   4  scenario #1b    — agent-mesh: same policy blocks the bridged A2A payment
#   5  scenario #2     — PII + secret redaction on tool output
#   6  scenario #3     — prompt-injection neutralized
#   7  scenario #4     — least-privilege: FinOps server hides the raw wire tool
#   8  scenario #5     — cross-language A2A: the Rust agent executes
#   9  proof           — full assertion suite (16/16) + how to drive it live
#
# Each money-shot stage prints the live OPA decision log as proof the gateway
# actually consulted policy with the real arguments.
#
# Usage:
#   bash scripts/demo.sh           # interactive, stops after each stage
#   bash scripts/demo.sh --fresh   # tear down volumes first (truly cold start)
#   bash scripts/demo.sh --yes     # no pauses (CI / self-test)
#   bash scripts/demo.sh --no-color
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# ── flags ──────────────────────────────────────────────────────────────
FRESH=0; ASSUME_YES=0; USE_COLOR=1
for a in "$@"; do
  case "$a" in
    --fresh)      FRESH=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    --no-color)   USE_COLOR=0 ;;
    -h|--help)    sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a (try --help)"; exit 2 ;;
  esac
done
[ -t 1 ] || USE_COLOR=0
[ -n "${NO_COLOR:-}" ] && USE_COLOR=0

# ── colors ─────────────────────────────────────────────────────────────
if [ "$USE_COLOR" = 1 ]; then
  BOLD=$(tput bold 2>/dev/null); DIM=$(tput dim 2>/dev/null); RST=$(tput sgr0 2>/dev/null)
  RED=$(tput setaf 1 2>/dev/null); GRN=$(tput setaf 2 2>/dev/null); YEL=$(tput setaf 3 2>/dev/null)
  BLU=$(tput setaf 4 2>/dev/null); CYN=$(tput setaf 6 2>/dev/null)
else BOLD=; DIM=; RST=; RED=; GRN=; YEL=; BLU=; CYN=; fi

# ── config ─────────────────────────────────────────────────────────────
GW="${GATEWAY_URL:-http://localhost:4444}"
COMPOSE="docker compose"
SECRET="$(grep -E '^JWT_SECRET_KEY=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')"
SECRET="${SECRET:-demo-only-change-me-0123456789abcdef}"
ADMIN_EMAIL="admin@finbyte.demo"
ADMIN_PW="$(grep -E '^PLATFORM_ADMIN_PASSWORD=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')"
ADMIN_PW="${ADMIN_PW:-FinByteAdmin!2026}"
PASS=0; FAIL=0; TOKEN=""

# ── helpers ────────────────────────────────────────────────────────────
say()   { printf '%s\n' "$*"; }
hr()    { printf "${DIM}────────────────────────────────────────────────────────────${RST}\n"; }
stage() { local n=$1; shift; echo; hr; printf "${BOLD}${BLU}STAGE %s${RST}${BOLD} — %s${RST}\n" "$n" "$*"; hr; }
ok()    { printf "  ${GRN}✔${RST} %s\n" "$*"; }
warn()  { printf "  ${YEL}!${RST} %s\n" "$*"; }
bad()   { printf "  ${RED}✗${RST} %s\n" "$*"; }
die()   { printf "\n${RED}${BOLD}FATAL:${RST} %s\n" "$*" >&2; exit 1; }
need()  { command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH. $2"; }

pause() {
  echo
  if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then printf "${DIM}(auto-advancing)${RST}\n"; return 0; fi
  printf "${BOLD}↵ Enter${RST}=next   ${BOLD}${YEL}s${RST}=run the rest non-stop   ${BOLD}${RED}q${RST}=quit  ➤ "
  read -r ans || true
  case "${ans:-}" in q|Q) say "stopped."; exit 0 ;; s|S) ASSUME_YES=1 ;; esac
}

mint() { # <user> -> admin JWT (offline; no gateway needed)
  DATABASE_URL="sqlite:///./.tokmint.db" uv run --with mcp-contextforge-gateway -- \
    python -m mcpgateway.utils.create_jwt_token -u "$1" --admin -e 10080 -s "$SECRET" 2>/dev/null | tail -1
}

call() { # <toolname> <args-json>   (uses $TOKEN)
  curl -s -X POST "$GW/rpc" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"
}
pretty() { printf '%s' "$1" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$1"; }

a_contains() { # <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; PASS=$((PASS+1));
  else bad "$1  ${DIM}(missing: $3)${RST}"; FAIL=$((FAIL+1)); fi
}
a_absent() {
  if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1  ${DIM}(leaked: $3)${RST}"; FAIL=$((FAIL+1));
  else ok "$1"; PASS=$((PASS+1)); fi
}

# Print the latest OPA decision-log entry for <toolname> — the gateway's
# proof that it consulted policy with the REAL arguments. Logs are passed via
# env var (not a pipe) so they don't collide with the heredoc program on stdin.
show_opa() { # <toolname>
  printf "  ${CYN}📋 PROOF — live OPA decision log (the policy decision point):${RST}\n"
  OPA_LOGS="$($COMPOSE logs --no-color --tail 250 opa 2>/dev/null)" TOOL="$1" python3 <<'PY' 2>/dev/null || printf "     (no decision captured)\n"
import os, json
tool = os.environ.get("TOOL", ""); pick = None
for line in os.environ.get("OPA_LOGS", "").splitlines():
    i = line.find('{')
    if i < 0: continue
    try: d = json.loads(line[i:])
    except Exception: continue
    if d.get("msg") != "Decision Log": continue
    if d.get("input", {}).get("resource", {}).get("id") == tool: pick = d
if not pick:
    print("     (no decision captured)"); raise SystemExit(0)
inp = pick.get("input", {}); r = pick.get("result", {})
print("     action    :", inp.get("action"))
print("     tool_args :", json.dumps(inp.get("context", {}).get("tool_args", {})))
print("     allow     :", r.get("allow"))
for d in (r.get("deny") or []):
    print("     deny      :", d)
PY
}

# ════════════════════════════════════════════════════════════════════════
stage 0 "Preflight — tooling & config"
need docker "Install Docker Desktop and start it."
docker info >/dev/null 2>&1 || die "Docker daemon not responding. Start Docker Desktop and retry."
ok "docker daemon up"
need uv "Install uv → https://docs.astral.sh/uv/ (used to mint JWTs offline)"; ok "uv present"
need curl ""; need python3 ""
if [ ! -f .env ]; then cp .env.example .env; ok ".env created from .env.example"; else ok ".env present"; fi
say "  Gateway → ${BOLD}$GW${RST}   ·   Admin UI login: ${BOLD}$ADMIN_EMAIL${RST} / ${BOLD}$ADMIN_PW${RST}"
[ "$FRESH" = 1 ] && warn "--fresh: volumes will be torn down for a cold start"
pause

# ════════════════════════════════════════════════════════════════════════
stage 1 "Bring up ContextForge + 4 MCP servers + 2 A2A agents"
if [ "$FRESH" = 1 ]; then say "  tearing down (down -v)…"; $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true; fi
say "  minting the Auditor's gateway token…"
printf 'AUDITOR_TOKEN=%s\n' "$(mint auditor@finbyte.demo)" > .env.tokens
say "  ${DIM}docker compose up -d --build  (pulls the pinned ContextForge image, builds 6 local images)${RST}"
$COMPOSE --env-file .env.tokens up -d --build || die "compose up failed — inspect with: $COMPOSE logs"
printf "  waiting for gateway health"
healthy=0
for _ in $(seq 1 60); do
  if curl -sf "$GW/health" >/dev/null 2>&1; then healthy=1; break; fi
  printf "."; sleep 2
done
echo
[ "$healthy" = 1 ] || die "gateway not healthy within 120s. Inspect: $COMPOSE logs gateway"
ok "gateway healthy at $GW"
if $COMPOSE exec -T gateway python -c "import sqlite3;c=sqlite3.connect('/tmp/mcp.db');c.execute('update email_users set password_change_required=0');c.commit()" 2>/dev/null; then
  ok "admin password-change flag cleared (Admin UI login ready)"
else
  warn "couldn't clear the password-change flag yet (Admin UI may prompt once)"
fi
echo; $COMPOSE ps
pause

# ════════════════════════════════════════════════════════════════════════
stage 2 "Register servers/agents with ContextForge + build virtual servers"
TOKEN="$(mint "$ADMIN_EMAIL")"; [ -n "$TOKEN" ] || die "could not mint admin token (is uv working?)"
ok "admin token minted"
seeded=0
for attempt in 1 2 3; do
  say "  seeding (attempt $attempt)…"
  out="$(ADMIN_TOKEN="$TOKEN" uv run --with httpx python gateway/seed/seed.py 2>&1)"
  printf '%s\n' "$out" | sed 's/^/    /'
  if printf '%s' "$out" | grep -q "FinOps" && ! printf '%s' "$out" | grep -q "tool not found"; then seeded=1; break; fi
  warn "backends still warming up — retrying in 4s…"; sleep 4
done
[ "$seeded" = 1 ] && ok "registration complete" || warn "seed finished with warnings (see above) — continuing"
echo; say "  ${BOLD}Registered inventory:${RST}"
curl -s -H "Authorization: Bearer $TOKEN" "$GW/gateways" | python3 -c "import sys,json;[print('    MCP   ',g['name'],'→',g.get('url')) for g in json.load(sys.stdin)]" 2>/dev/null || true
curl -s -H "Authorization: Bearer $TOKEN" "$GW/a2a"      | python3 -c "import sys,json;[print('    A2A   ',a['name'],'→',a.get('endpoint_url','')) for a in json.load(sys.stdin)]" 2>/dev/null || true
curl -s -H "Authorization: Bearer $TOKEN" "$GW/servers"  | python3 -c "import sys,json;[print('    VSRV  ',s['name'],s['id']) for s in json.load(sys.stdin)]" 2>/dev/null || true
pause

# ════════════════════════════════════════════════════════════════════════
stage 3 "Scenario #1 — OPA policy: the \$10,000 wire cap"
say "  ${BOLD}A) \$50,000 wire, no approval${RST}  → expect ${RED}BLOCK${RST}"
req='{"payee":"Acme LLC","amount":50000,"approval":false}'
say "  ${DIM}→ erp-payments-wire $req${RST}"
r="$(call erp-payments-wire "$req")"
a_contains "blocked with a Plugin Violation" "$r" "Plugin Violation"
a_contains "block cites the FinByte T&E policy" "$r" "T&E policy"
say "  ${DIM}response:${RST}"; pretty "$r" | sed 's/^/    /'
show_opa "erp-payments-wire"
echo
say "  ${BOLD}B) \$5,000 wire${RST}  → expect ${GRN}ALLOW${RST}"
r="$(call erp-payments-wire '{"payee":"Corner Cafe","amount":5000,"approval":false}')"
a_contains "small wire executed" "$r" '"status":"wired"'
echo
say "  ${BOLD}C) \$50,000 wire WITH dual approval${RST}  → expect ${GRN}ALLOW${RST}"
r="$(call erp-payments-wire '{"payee":"Acme LLC","amount":50000,"approval":true}')"
a_contains "executed with dual approval" "$r" '"status":"wired"'
pause

# ════════════════════════════════════════════════════════════════════════
stage 4 "Scenario #1b — Agent-mesh: same OPA policy governs the A2A payment"
req='{"payee":"Acme LLC","amount":50000,"approval":false}'
say "  ${DIM}→ a2a-payments $req   (bridged Rust-agent tool, not the raw wire)${RST}"
r="$(call a2a-payments "$req")"
a_contains "\$50k via a2a-payments BLOCKED" "$r" "Plugin Violation"
say "  ${DIM}response:${RST}"; pretty "$r" | sed 's/^/    /'
show_opa "a2a-payments"
pause

# ════════════════════════════════════════════════════════════════════════
stage 5 "Scenario #2 — Data protection: PII + secret redaction"
say "  ${DIM}→ expense-db-get-receipt {\"id\":\"rcpt_pii\"}${RST}"
r="$(call expense-db-get-receipt '{"id":"rcpt_pii"}')"
a_contains "SSN masked"         "$r" "***-**-6789"
a_contains "credit card masked" "$r" "****-****-****-1111"
a_contains "API key redacted"   "$r" "[SECRET_REDACTED]"
a_absent  "raw card not leaked" "$r" "4111 1111 1111 1111"
a_absent  "raw key not leaked"  "$r" "sk-live-ABCDEF"
say "  ${DIM}response (post-redaction — what the model actually sees):${RST}"; pretty "$r" | sed 's/^/    /'
pause

# ════════════════════════════════════════════════════════════════════════
stage 6 "Scenario #3 — Prompt-injection neutralized in tool output"
say "  ${DIM}→ expense-db-get-receipt {\"id\":\"rcpt_injection\"}${RST}"
r="$(call expense-db-get-receipt '{"id":"rcpt_injection"}')"
a_contains "injection neutralized"    "$r" "[INJECTION_BLOCKED]"
a_absent  "injected instruction gone" "$r" "ignore all prior policy"
say "  ${DIM}response:${RST}"; pretty "$r" | sed 's/^/    /'
pause

# ════════════════════════════════════════════════════════════════════════
stage 7 "Scenario #4 — Least-privilege: FinOps server excludes the raw wire tool"
FINOPS_ID="$(curl -s -H "Authorization: Bearer $TOKEN" "$GW/servers" | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='FinOps']" 2>/dev/null | head -1)"
ft="$(curl -s -H "Authorization: Bearer $TOKEN" "$GW/servers/$FINOPS_ID/tools")"
names="$(printf '%s' "$ft" | python3 -c "import sys,json;print(', '.join(sorted(t.get('name','') for t in json.load(sys.stdin))))" 2>/dev/null)"
say "  FinOps (Bob's server) tools: ${DIM}$names${RST}"
a_contains "FinOps exposes approve"        "$ft" "approve"
a_contains "FinOps exposes a2a-auditor"    "$ft" "a2a-auditor"
a_absent  "FinOps HIDES erp-payments-wire" "$ft" "erp-payments-wire"
pause

# ════════════════════════════════════════════════════════════════════════
stage 8 "Scenario #5 — Cross-language A2A: the Rust Payments agent executes"
req='{"message":{"role":"ROLE_USER","parts":[{"text":"Execute payment of $5000 to Corner Cafe"}],"messageId":"m-demo"}}'
say "  ${DIM}→ a2a-payments (message)  ·  gateway → Rust agent (different language/process)${RST}"
r="$(call a2a-payments "$req")"
a_contains "Rust agent executed the payment" "$r" "Payment executed"
say "  ${DIM}response:${RST}"; pretty "$r" | sed 's/^/    /'
pause

# ════════════════════════════════════════════════════════════════════════
stage 9 "Proof + how to drive it live"
printf "  ${BOLD}Inline tally:${RST} ${GRN}%s passed${RST}, ${RED}%s failed${RST}\n" "$PASS" "$FAIL"
say "  Running the canonical assertion suite…"
if bash scripts/money-shots/run-all.sh >/tmp/_demo_verify.out 2>&1; then
  tail -3 /tmp/_demo_verify.out | sed 's/^/    /'; ok "verify-controls green"
else
  tail -8 /tmp/_demo_verify.out | sed 's/^/    /'; warn "verify-controls reported failures (see above)"
fi
echo
say "  ${BOLD}Drive it live:${RST}"
say "   • Browser companion : ${CYN}make companion${RST}   → http://localhost:7070"
say "   • IBM Bob config    : ${CYN}make bob-config${RST}  → paste into ~/.bob/mcp_settings.json"
say "   • Admin UI          : ${CYN}$GW/admin${RST}  ($ADMIN_EMAIL / $ADMIN_PW)"
say "   • Reset anytime     : ${CYN}make demo-reset${RST}"
echo
if [ "$FAIL" -eq 0 ]; then printf "${GRN}${BOLD}✔ End-to-end demo complete — every control fired as designed.${RST}\n"
else printf "${YEL}${BOLD}Completed with %s assertion failure(s) — review the stages above.${RST}\n" "$FAIL"; fi
