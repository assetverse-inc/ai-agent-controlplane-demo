#!/usr/bin/env bash
# connect.sh — `make connect`: print the ONE command an attendee runs on their
# LOCAL IBM Bob to drive the governed gateway running HERE (a Codespace, a VM, or
# localhost). The whole 10-service mesh stays server-side; the attendee installs
# nothing but Bob — no Docker, uv, make, git, or the mcpgateway wrapper. Bob talks
# to the gateway directly over SSE + a bearer token (proven: governance — redaction,
# least-privilege, OPA — all still apply over the remote connection).
#
# URL resolution (first hit wins):
#   GATEWAY_URL=...    explicit (a presenter VM, a tunnel, anything)
#   $CODESPACE_NAME    auto: https://<codespace>-4444.<forwarding-domain>
#   else               http://localhost:4444  (same-machine only)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(tput bold 2>/dev/null); D=$(tput dim 2>/dev/null); R=$(tput sgr0 2>/dev/null)
  GRN=$(tput setaf 2 2>/dev/null); YEL=$(tput setaf 3 2>/dev/null); CYN=$(tput setaf 6 2>/dev/null)
else B=; D=; R=; GRN=; YEL=; CYN=; fi
ok(){ printf "  ${GRN}✔${R} %s\n" "$*"; }
warn(){ printf "  ${YEL}!${R} %s\n" "$*"; }

SECRET="${SECRET:-demo-only-change-me-0123456789abcdef}"

# ── 1) where is the gateway? ─────────────────────────────────────────────────
if [ -n "${GATEWAY_URL:-}" ]; then
  BASE="${GATEWAY_URL%/}"; WHERE="GATEWAY_URL override"
elif [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
  BASE="https://${CODESPACE_NAME}-4444.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"; WHERE="GitHub Codespace"
else
  BASE="http://localhost:4444"; WHERE="localhost (same machine only — set GATEWAY_URL or run in a Codespace for remote attendees)"
fi

# ── 2) mint a token + find the virtual servers (locally, against :4444) ───────
# Mint EXACTLY like the Makefile's token/seed targets (no eval) so the token is
# identical to the one `make seed` proved works.
ADMIN=$(DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- \
  python -m mcpgateway.utils.create_jwt_token -u admin@finbyte.demo --admin -e 10080 -s "$SECRET" 2>/dev/null | tail -1)
[ -n "$ADMIN" ] || { echo "could not mint a token — is 'uv' here and the gateway up? (make up && make seed)"; exit 1; }

# Fetch /servers (read-only) and resolve the FinOps/Operator UUIDs. Parse with
# grep/sed — NO python — because some base images (e.g. the devcontainer's
# python3-minimal) ship a python3 without the stdlib `json` module. The gateway
# emits compact {"id":"…","name":"…",…} with id immediately before name, so this is
# reliable against the pinned image.
SRV_BODY=$(curl -s -H "Authorization: Bearer $ADMIN" localhost:4444/servers)
srv_uuid(){ printf '%s' "$SRV_BODY" | grep -o "\"id\":\"[^\"]*\",\"name\":\"$1\"" | head -1 | sed 's/"id":"\([^"]*\)".*/\1/'; }
FINOPS=$(srv_uuid FinOps)
OPERATOR=$(srv_uuid Operator)
if [ -z "$FINOPS" ]; then
  NAMES=$(printf '%s' "$SRV_BODY" | grep -o '"name":"[^"]*"' | sed 's/"name":"\([^"]*\)"/\1/' | sort -u | paste -sd, - 2>/dev/null)
  echo "FinOps server not found at localhost:4444/servers."
  echo "  servers seen: ${NAMES:-<none — gateway unreachable or not seeded>}"
  echo "  body (first 160 chars): $(printf '%s' "$SRV_BODY" | head -c 160)"
  echo "  → names without FinOps = run 'make seed'; empty = gateway not up."
  exit 1
fi

# ── 3) reachability hint ─────────────────────────────────────────────────────
echo; printf "${B}Gateway location:${R} %s   ${D}(%s)${R}\n" "$BASE" "$WHERE"
case "$BASE" in
  https://*app.github.dev*)
    if curl -sf "$BASE/health" >/dev/null 2>&1; then ok "public URL reachable — attendees can connect"
    else warn "the forwarded port isn't public yet. In the Codespace PORTS tab, set port 4444 visibility to ${B}Public${R}, then re-run 'make connect'."; fi ;;
  http://localhost:*)
    warn "this is a LOCAL url — only Bob on THIS machine can use it. For a room, run the stack in a Codespace (or set GATEWAY_URL to a public address)." ;;
esac

# ── 4) the attendee command(s) ───────────────────────────────────────────────
# Use the STREAMABLE-HTTP transport (-t http + the /mcp endpoint), not SSE. SSE is
# a long-lived stream that the Codespaces/tunnel proxy buffers, so Bob hangs on
# connect; /mcp is plain request/response and goes through cleanly (verified). It
# works identically for a local gateway too, so http is the universal default.
cat <<EOF

${B}Attendees: install IBM Bob, then — FROM AN EMPTY FOLDER — run ONE command${R}
${D}(no Docker/uv/make. NOT from a clone of this repo: its .bob/mcp.json would shadow this one.)${R}

${B}Act 1 — FinOps analyst${R} (8 governed tools, no wire):
  ${CYN}bob mcp add finbyte-gateway "$BASE/servers/$FINOPS/mcp" -t http -H "Authorization: Bearer $ADMIN" --trust${R}

Then drive it (from the same folder):
  ${CYN}bob${R}
    "Use the finbyte-gateway tools to fetch receipt rcpt_pii, verbatim."   ${D}→ PII/secret redacted${R}
    "Ask the auditor agent to pay \$50,000 to Acme LLC."                    ${D}→ blocked by policy${R}

${D}Act 2 — platform operator (advanced): re-add pointed at the Operator server${R}
  ${CYN}bob mcp add finbyte-gateway "$BASE/servers/$OPERATOR/mcp" -t http -H "Authorization: Bearer $ADMIN" --trust${R}

${D}Equivalent .bob/settings.json (if they prefer a file over the command):${R}
  {"mcpServers":{"finbyte-gateway":{"httpUrl":"$BASE/servers/$FINOPS/mcp","headers":{"Authorization":"Bearer $ADMIN"}}}}

${D}Reset:  bob mcp remove finbyte-gateway   ·   tip: copy the FULL token (it's ~470 chars — don't truncate)${R}
EOF
