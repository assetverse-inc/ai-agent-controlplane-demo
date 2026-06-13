#!/usr/bin/env bash
# check.sh — `make check`: verify EVERY prerequisite to run the demo, drive Bob,
# and open the cockpit/inspectors — then report live stack status. Read-only, no
# side effects. Exits non-zero if a REQUIRED tool is missing, so it doubles as a
# pre-talk gate ("am I ready?"). Optional tools only warn (the stack + 16/16 proof
# run without Bob/tmux/npx).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(tput bold 2>/dev/null); D=$(tput dim 2>/dev/null); R=$(tput sgr0 2>/dev/null)
  RED=$(tput setaf 1 2>/dev/null); GRN=$(tput setaf 2 2>/dev/null)
  YEL=$(tput setaf 3 2>/dev/null); BLU=$(tput setaf 4 2>/dev/null); CYN=$(tput setaf 6 2>/dev/null)
else B=; D=; R=; RED=; GRN=; YEL=; BLU=; CYN=; fi

hd(){ echo; printf "${B}${BLU}━━ %s ━━${R}\n" "$*"; }
ok(){ printf "  ${GRN}✔${R} %s\n" "$*"; }
no(){ printf "  ${RED}✗${R} %s\n" "$*"; }
warn(){ printf "  ${YEL}!${R} %s\n" "$*"; }

miss=0
ver(){ v=$("$1" --version 2>/dev/null | head -1); [ -n "$v" ] || v=$("$1" -V 2>/dev/null | head -1); echo "$v"; }  # tmux uses -V
req(){  # cmd, why, install-hint  → fatal if missing
  if command -v "$1" >/dev/null 2>&1; then ok "$1 — $(ver "$1")  ${D}($2)${R}";
  else no "$1 MISSING — $2  ${D}install: $3${R}"; miss=1; fi; }
opt(){  # cmd, why, note  → warn if missing
  if command -v "$1" >/dev/null 2>&1; then ok "$1 — $(ver "$1")  ${D}($2)${R}";
  else warn "$1 not found — $2  ${D}(optional: $3)${R}"; fi; }

# ── 1) container runtime + compose ───────────────────────────────────────────
hd "Container runtime (need ONE of docker / podman)"
RUNTIME=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  RUNTIME=docker; ok "docker — $(ver docker)  ${D}(responding)${R}"
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 \
    && ok "docker compose — $(docker compose version --short 2>/dev/null)" \
    || { command -v docker-compose >/dev/null 2>&1 && ok "docker-compose — $(docker-compose version --short 2>/dev/null)" \
         || { no "no compose v2 — install Docker Desktop (bundles 'docker compose')"; miss=1; }; }
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman; ok "podman — $(ver podman)"
  sock="/run/user/$(id -u 2>/dev/null)/podman/podman.sock"
  [ -S "$sock" ] && ok "podman API socket live ($sock)" \
    || warn "podman socket not live — run: ${CYN}systemctl --user enable --now podman.socket${R}"
  if command -v docker-compose >/dev/null 2>&1; then ok "docker-compose — $(docker-compose version --short 2>/dev/null)  ${D}(compose engine for podman)${R}";
  elif docker compose version >/dev/null 2>&1; then ok "docker compose (v2 plugin)";
  else warn "no Docker Compose v2 — podman needs it (legacy podman-compose is too buggy; see RUNBOOK 'Run on Podman')"; fi
elif command -v docker >/dev/null 2>&1; then
  no "docker present but NOT responding — start Docker Desktop / the daemon"; miss=1
else
  no "no container runtime — install Docker Desktop, or Podman (rootless)"; miss=1
fi

# ── 2) required to bring the stack up + prove 16/16 ──────────────────────────
hd "Required (stack + 16/16 proof)"
req uv      "mints JWTs · runs seed/companion"  "https://docs.astral.sh/uv/"
req curl    "health probes · API calls"         "your package manager"
req python3 "seed · token parsing · log filters" "python.org"
req git     "inspect-a2a first-run build"        "your package manager"

# ── 3) optional — to DRIVE Bob and OPEN the cockpit/inspectors ───────────────
hd "Optional (drive / observe — stack + proof run without these)"
opt bob  "the AI agent you'll drive"   "IBM Bob Shell — https://bob.ibm.com/download"
opt npx  "MCP Inspector"               "comes with Node.js ≥18"
opt tmux "make cockpit (multi-pane)"   "brew install tmux  /  apt-get install tmux"

# ── 4) live status (informational) ───────────────────────────────────────────
hd "Live status (informational)"
if curl -sf localhost:4444/health >/dev/null 2>&1; then
  ok "gateway UP — http://localhost:4444/health"
  if command -v uv >/dev/null 2>&1; then
    ADMIN=$(DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- \
      python -m mcpgateway.utils.create_jwt_token -u admin@finbyte.demo --admin -e 60 \
      -s demo-only-change-me-0123456789abcdef 2>/dev/null | tail -1)
    names=$(curl -s -H "Authorization: Bearer $ADMIN" localhost:4444/servers 2>/dev/null \
      | python3 -c "import sys,json;print(','.join(s['name'] for s in json.load(sys.stdin) if isinstance(s,dict)))" 2>/dev/null)
    case "$names" in
      *FinOps*) ok "seeded — virtual servers: $names" ;;
      "") warn "couldn't read /servers (token?) — try: ${CYN}make seed${R}" ;;
      *) warn "up but not fully seeded ($names) — run: ${CYN}make seed${R}" ;;
    esac
  fi
else
  warn "gateway not up yet — bring it up with: ${CYN}make up${R}  (or ${CYN}make quickstart${R})"
fi
[ -f .env ] && ok ".env present" || warn "no .env yet — created on first 'make up' (cp .env.example .env)"
[ -f .bob/mcp.json ] && ok ".bob/mcp.json present (Bob persona configured)" || warn "no .bob/mcp.json — written by 'make bob' / 'make bob-install'"
[ -f mcp-servers/sales-tax/server.py ] && warn "Stage-1 sales-tax/server.py exists (from a prior run) — ${CYN}make stage-reset${R} for a clean 'build from scratch'" \
  || ok "Stage-1 clean (sales-tax/server.py absent — Bob builds it live)"

# ── verdict ──────────────────────────────────────────────────────────────────
hd "Result"
if [ "$miss" = 0 ]; then
  printf "  ${GRN}${B}✔ All required prerequisites present.${R}  Next: ${CYN}make quickstart${R} or ${CYN}make stage1-build${R}\n\n"
  exit 0
else
  printf "  ${RED}${B}✗ Missing required prerequisites above.${R}  Install them, then re-run ${CYN}make check${R}\n\n"
  exit 1
fi
