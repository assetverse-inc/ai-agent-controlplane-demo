#!/usr/bin/env bash
# quickstart.sh — the attendee front door. One command takes a laptop from
# nothing to a running, governed agent mesh + Bob configured + controls proven,
# then prints the exact steps to drive Bob and open the three inspectors.
#
# Designed for a LIVE room: every prerequisite is checked up front with a clear
# install hint, the stack is brought up idempotently, and it ends with a
# copy-paste walkthrough card. Re-runnable; safe to run again if anything stalls.
#
# Usage:  make quickstart   (or: bash scripts/quickstart.sh)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(tput bold 2>/dev/null); D=$(tput dim 2>/dev/null); R=$(tput sgr0 2>/dev/null)
  RED=$(tput setaf 1 2>/dev/null); GRN=$(tput setaf 2 2>/dev/null)
  YEL=$(tput setaf 3 2>/dev/null); BLU=$(tput setaf 4 2>/dev/null); CYN=$(tput setaf 6 2>/dev/null)
else B=; D=; R=; RED=; GRN=; YEL=; BLU=; CYN=; fi

ok(){ printf "  ${GRN}✔${R} %s\n" "$*"; }
no(){ printf "  ${RED}✗${R} %s\n" "$*"; }
hd(){ echo; printf "${B}${BLU}== %s ==${R}\n" "$*"; }
die(){ printf "\n${RED}${B}STOPPED:${R} %s\n" "$*" >&2; exit 1; }

GW="http://localhost:4444"
ADMIN_EMAIL="admin@finbyte.demo"
ADMIN_PW="$(grep -E '^PLATFORM_ADMIN_PASSWORD=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')"
ADMIN_PW="${ADMIN_PW:-FinByteAdmin!2026}"

# ── 1) preflight ─────────────────────────────────────────────────────────
hd "1/5  Preflight — checking your laptop"
miss=0
chk(){ # REQUIRED: cmd, why, install-hint
  if command -v "$1" >/dev/null 2>&1; then ok "$1 — $($1 --version 2>/dev/null | head -1)";
  else no "$1 MISSING — $2  ${D}($3)${R}"; miss=1; fi
}
chkopt(){ # OPTIONAL (the stack + 16/16 proof run without it): cmd, why, note
  if command -v "$1" >/dev/null 2>&1; then ok "$1 — $($1 --version 2>/dev/null | head -1)";
  else printf "  ${YEL}!${R} %s not found — %s  ${D}(optional: %s)${R}\n" "$1" "$2" "$3"; fi
}
chk docker "runs the gateway + servers"        "install Docker Desktop and start it"
chk uv     "mints the gateway JWT offline"      "https://docs.astral.sh/uv/"
# Bob and npx are only needed to DRIVE / inspect the demo — not to bring up the
# stack or prove the controls. Keep them non-fatal so quickstart also works on a
# headless box / Linux VM / CI (ends with 16/16; install Bob on a Mac to drive it).
chkopt bob "the AI agent you'll drive"          "needed only to DRIVE Bob; the stack + 16/16 proof run without it"
chkopt npx "runs the MCP Inspector"             "comes with Node.js ≥18; only for 'make inspect-mcp'"
command -v curl >/dev/null 2>&1 || { no "curl MISSING"; miss=1; }
command -v python3 >/dev/null 2>&1 || { no "python3 MISSING"; miss=1; }
docker info >/dev/null 2>&1 || die "Docker daemon isn't responding — start Docker Desktop and re-run."
[ "$miss" = 0 ] || die "Install the MISSING tools above, then re-run 'make quickstart'."
[ -f .env ] || { cp .env.example .env; ok ".env created"; }

# ── 2) bring up the stack ──────────────────────────────────────────────────
hd "2/5  Starting ContextForge + 4 MCP servers + 2 A2A agents + operator"
make up || die "stack failed to start — see: docker compose logs"
# clear the forced password-change so the Admin UI logs in cleanly
docker compose exec -T gateway python -c "import sqlite3;c=sqlite3.connect('/tmp/mcp.db');c.execute('update email_users set password_change_required=0');c.commit()" 2>/dev/null \
  && ok "Admin UI login ready" || printf "  ${YEL}!${R} couldn't clear password flag yet (Admin UI may prompt once)\n"

# ── 3) register + 4) configure Bob ─────────────────────────────────────────
hd "3/5  Registering servers/agents + building virtual servers"
make seed >/dev/null 2>&1 && ok "registered (FinOps / Treasury / Operator virtual servers built)" \
  || { sleep 4; make seed >/dev/null 2>&1 && ok "registered (after retry)" || printf "  ${YEL}!${R} seed had warnings — 'make seed' to retry\n"; }

hd "4/5  Configuring Bob (FinOps analyst persona)"
make bob-install >/dev/null 2>&1 && ok ".bob/mcp.json written (least-privilege: 8 tools, no wire)" \
  || printf "  ${YEL}!${R} bob-install failed — run 'make bob-install'\n"

# ── 5) prove the controls ──────────────────────────────────────────────────
hd "5/5  Proving the controls (safety net)"
if bash scripts/money-shots/run-all.sh >/tmp/_qs_verify.out 2>&1; then
  tail -3 /tmp/_qs_verify.out | sed 's/^/  /'; ok "all controls green"
else
  tail -6 /tmp/_qs_verify.out | sed 's/^/  /'; printf "  ${YEL}!${R} some checks failed — 'make demo-reset' then re-run\n"
fi

ADMIN=$(make -s token 2>/dev/null | tail -1)
FINOPS=$(curl -s -H "Authorization: Bearer $ADMIN" "$GW/servers" | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='FinOps']" 2>/dev/null | head -1)

# ── the walkthrough card ────────────────────────────────────────────────────
cat <<EOF

${B}${GRN}✔ Ready.${R}  Your governed agent control plane is live.

${B}① Drive Bob (the agent)${R}:
   ${CYN}make bob${R}                ${D}← launches Bob from the repo root (cwd-proof)${R}
   ${D}(prefer ${R}${CYN}make bob${R}${D}. If you run ${R}${CYN}bob${R}${D} directly, do it FROM THIS folder — the repo${R}
   ${D} root — NOT the bob-personas/ subfolder, or Bob won't find .bob/mcp.json.)${R}
   Then try, as the FinOps analyst:
     • "Use the finbyte-gateway tools to fetch receipt rcpt_pii, verbatim."   ${D}→ PII/secret redacted${R}
     • "Fetch receipt rcpt_injection."                                        ${D}→ injection neutralized${R}
     • "Ask the auditor agent to pay \$50,000 to Acme LLC."                    ${D}→ blocked by policy (cross-language)${R}
     • "Wire \$50k yourself, directly."                                        ${D}→ you have no wire tool (least-privilege)${R}
   Switch to the OPERATOR persona for Act 2 (quit Bob, then):  ${CYN}make bob-operator${R}
     • "List everything ContextForge is governing."
     • "Would a \$50,000 wire be allowed? With dual approval?"
     • "Register the fx-rates service at http://fx-rates:8000/mcp."
     • "Show me what got blocked today."
   ${D}(make bob / make bob-operator refresh the config every time — safe after any reseed/demo-reset)${R}

${B}② Watch the control plane (3 ways)${R}:
   • ContextForge monitor : ${CYN}make monitor${R}   → ${GW}/admin  ($ADMIN_EMAIL / $ADMIN_PW)
   • MCP Inspector        : ${CYN}make inspect-mcp${R}  (shows the 8 governed tools — wire absent)
   • A2A Inspector        : ${CYN}make inspect-a2a${R}  (validates the Python + Rust agent cards)

${B}③ Reset between runs${R}:  ${CYN}make demo-reset${R}   ·   prove controls anytime: ${CYN}make verify-controls${R}

${D}FinOps server id: ${FINOPS:-<run make seed>}${R}
EOF
