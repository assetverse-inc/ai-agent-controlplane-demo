# Getting attendees in — when laptops don't have Docker/make/git

The honest blocker isn't `git`/`make` (a 30-second `brew install`) — it's a **container
runtime + building 10 images on conference WiFi**. So the goal is to keep the mesh
**server-side** and ask attendees for as little as possible. Pick the tier that fits your room.

## The key fact that makes this easy

IBM Bob speaks to **remote** MCP servers natively (streamable-HTTP + a bearer token) —
no local wrapper, no `uv`, no Docker. So Bob on a bare laptop can drive a gateway
running anywhere. Proven end-to-end: a fresh Bob pointed at `/servers/<id>/mcp` over a
**public Codespaces URL** lists the governed tools and gets PII redacted — all four
controls still apply over the wire.

```bash
# run from an EMPTY folder (not a clone of this repo — its .bob/mcp.json would shadow this)
bob mcp add finbyte-gateway "<GATEWAY_URL>/servers/<UUID>/mcp" \
  -t http -H "Authorization: Bearer <TOKEN>" --trust
```

`make connect` prints that command fully filled in (URL + UUID + token) for whatever
gateway you're running — Codespace, VM, or localhost.

> **Use `-t http` + `/mcp`, not SSE, for a hosted gateway.** SSE is a long-lived stream
> that the Codespaces (and most tunnel) proxies buffer, so Bob hangs on connect.
> Streamable-HTTP is plain request/response and goes through cleanly. `make connect`
> emits the `http` form by default.

## Tier 1 — Zero install, browser only (everyone)

The prompt-card page is **static HTML** — `docs/cockpit.html` (or `make dev-start`).
It opens in any browser with no tools and carries every stage's Bob prompts. Good for
read-along, and as the fallback when someone's environment fights them.

## Tier 2 — Attendees install ONLY Bob; the mesh runs in GitHub Codespaces  ⭐ recommended

The containers run in a Codespace (cloud); each attendee's **local Bob** connects to the
forwarded gateway. No Docker/uv/make/git on the laptop — just Bob.

**Presenter (or each attendee), in the Codespace:**
1. Open the repo → **Code ▸ Codespaces ▸ Create codespace**. The devcontainer
   (`.devcontainer/`) installs Docker + the toolchain and runs `make up && make seed`
   automatically (a few minutes, in the cloud — not on WiFi).
2. **PORTS** tab → right-click **4444** → **Port Visibility → Public**.
3. `make connect` → copy the printed `bob mcp add …` command (or post it / show it on screen).

**Attendee, on their laptop:** install [IBM Bob Shell](https://bob.ibm.com/download), paste
the one command, then `bob`. That's it.

- **One shared Codespace** (presenter's): everyone points at the same gateway — zero setup
  for attendees, but shared state (the *register* and *reset* beats collide; great for the
  read-only control beats like redaction and the $50k block).
- **One Codespace per attendee**: isolated + fully hands-on (they can run the *register*
  beat too). Costs each attendee some Codespaces compute quota.

## Tier 3 — Presenter-hosted on a VM (attendees just watch/poke a URL)

Run the stack on any always-on box (`make up && make seed`), expose `:4444` (and
`:7070` for the Companion), then `make connect GATEWAY_URL=https://your-host:4444`
to hand out the connect command — or just share the Companion URL/QR for a watch-along.
Immune to WiFi and laptop chaos; attendees interact via browser + (optionally) their own Bob.

## Tier 4 — Fully local (the night-before prep path)

For attendees who want everything on their own machine: `scripts/test-fresh-host.sh`
bootstraps a fresh **Linux/WSL2** host (installs Docker/make/uv/node, brings it up, proves
16/16). On macOS, `brew install make git tmux` + Docker Desktop + `make quickstart`. This
builds images locally — fine the night before, **risky for a whole room at once**.

---

### Cheat sheet

| You want… | Do this |
|---|---|
| Read-along, no install | open `docs/cockpit.html` (`make dev-start`) |
| Hands-on, only Bob local | Codespace → make 4444 Public → `make connect` |
| Watch-along, nothing local | presenter VM/Codespace → share Companion `:7070` |
| Everything local | `make check` → `make quickstart` (or the bootstrap script) |

> Security note: `make connect` embeds an admin JWT in the command and the forwarded
> port is public for the session. Fine for a short-lived demo on throwaway data; tear the
> Codespace/port down afterward.
