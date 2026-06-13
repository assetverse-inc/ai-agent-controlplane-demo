#!/usr/bin/env bash
# post-create.sh — runs once when the Codespace is created. Installs the bits the
# base image lacks (make, tmux, uv), then brings up + seeds the governed mesh so
# the Codespace is demo-ready. Docker + node come from devcontainer features.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

say(){ printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

say "Installing make / tmux / full python3 / uv"
sudo apt-get update -qq
# python3 = the FULL stdlib (the base image often has only python3-minimal, which
# lacks the `json` module the Makefile's inline `python3 -c` parsers need).
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq make tmux python3 python3-venv >/dev/null
python3 -c 'import json' 2>/dev/null && echo "python3 stdlib OK (json present)" \
  || echo "!! python3 still lacks stdlib json — run: sudo apt-get install -y python3"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || true
  for d in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    [ -x "$d/uv" ] && sudo ln -sf "$d/uv" /usr/local/bin/uv && sudo ln -sf "$d/uvx" /usr/local/bin/uvx 2>/dev/null || true
  done
fi
command -v uv >/dev/null 2>&1 && echo "uv $(uv --version 2>&1 | awk '{print $2}')" || echo "!! uv install failed — run the curl installer manually"

say "Building + seeding the governed mesh (first run pulls/builds images — a few minutes, in the cloud not on WiFi)"
if make up && make seed; then
  echo "stack up + seeded"
else
  echo "!! up/seed hit a snag — run 'make up && make seed' yourself once the Codespace finishes opening"
fi

cat <<'EOF'

══════════════════════════════════════════════════════════════════════════════
 READY — the governed mesh runs HERE in the Codespace.
 To let attendees drive it from their own laptops with ONLY IBM Bob installed:

   1) PORTS tab → right-click port 4444 → Port Visibility → **Public**
   2) Run:   make connect
        → prints the one 'bob mcp add …' command they paste into their local Bob
          (no Docker / uv / make on their machine — Bob talks to :4444 directly)

 Presenter surfaces (also forwarded):  Companion :7070 · Admin UI :4444/admin
══════════════════════════════════════════════════════════════════════════════
EOF
