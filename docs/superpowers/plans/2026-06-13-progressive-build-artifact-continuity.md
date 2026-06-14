# Progressive-build Artifact Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry the `sales-tax` MCP server Bob builds in Stage 1 all the way through Stage 2 (containerize → register → grant → call it governed), add a co-equal "Bob extends fx-rates" beat, show the dev's code + a real tool call, surface the BYOB path, and dev-voice the build page — without breaking `make up` on a fresh clone.

**Architecture:** Stage 2 of `scripts/stages.sh` is rewritten to bring `sales-tax` up as a container on the compose network via a stage-2-only override file, register it into the ContextForge gateway, **grant** its tool into a new minimal `Builder` virtual server, and have Bob call it through the gateway. All gateway-API mutations live in small `gateway/seed/*.py` helpers (run via `uv run --with httpx`, mirroring the existing `seed.py`) so they work even on `python3-minimal` hosts. The build-view HTML (`docs/cockpit.html`) is updated to match.

**Tech Stack:** Bash (`scripts/stages.sh`), GNU Make, Docker/Podman Compose, Python 3 + `httpx` + `fastmcp==3.3.1`, ContextForge gateway REST API (`/gateways`, `/servers`, `/tools`), static HTML.

**Spec:** `docs/superpowers/specs/2026-06-13-progressive-build-artifact-continuity-design.md` (Codex-reviewed; decisions D1–D8).

**Branch:** `feature/issue-9-artifact-continuity` (already checked out; spec committed at `71c8dab`).

---

## Conventions used throughout this plan

- **Gateway tool naming:** ContextForge federates a backend tool as `<gateway-name>-<tool-name-with-underscores-as-dashes>`. Evidence: the `Operator` persona's `alwaysAllow` lists `controlplane-register-mcp-server` for gateway `controlplane` / tool `register_mcp_server`. So `sales-tax`/`add_tax` → **`sales-tax-add-tax`**; `fx-rates`/`convert` → **`fx-rates-convert`**.
- **Admin token:** minted exactly like the Makefile's `$(MINT)`: `DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- python -m mcpgateway.utils.create_jwt_token -u admin@finbyte.demo --admin -e 10080 -s demo-only-change-me-0123456789abcdef`.
- **Gateway base URL:** `http://localhost:4444` (the published port). The gateway reaches backends by compose service DNS (`http://sales-tax:8000/mcp`).
- **Lint gate:** every new/edited `.py` must pass `make lint` (`ruff check` + `black --check`) and `make bandit`. Run them before each Python commit. Format with `uvx black <files>` first to avoid the `black --check` failure that bit PR #8.
- **`PY_DIRS`** already includes `gateway/seed` and `scripts`, so new helpers there are auto-covered by `make lint`/`bandit`/`test`.

---

## File structure (what gets created / modified)

**Created:**
- `gateway/seed/_gwapi.py` — shared gateway-API helpers (`client`, `jget`, `api`, `norm`, `match_tool_ids`).
- `gateway/seed/register.py` — delete-then-recreate a gateway backend by name+url (fixes D8 staleness).
- `gateway/seed/grant.py` — ensure a virtual server exists with a given set of tools (union + delete-then-recreate); print its UUID.
- `gateway/seed/test_gwapi.py` — pytest for the pure helpers (`norm`, `match_tool_ids`).
- `scripts/salestax_smoke.py` — async `fastmcp.Client` call of `add_tax(100)` against the bare Stage-1 server (proof-of-life).
- `mcp-servers/sales-tax/Dockerfile` — build the generated `server.py` (mirror of `mcp-servers/fx-rates/Dockerfile`).
- `docker-compose.salestax.yml` — stage-2-only override: the `sales-tax` service on the base network, host port `8001:8000`.
- `bob-personas/mcp.builder.json.template` — Builder persona (mirror of `mcp.operator.json.template`).

**Modified:**
- `Makefile` — new targets `salestax-up`, `salestax-down`, `salestax-register`, `salestax-grant`, `bob-config-builder`, `bob-install-builder`, `fxrates-extend`; `.PHONY` updates.
- `scripts/stages.sh` — rewrite `stage_govern`; add proof-of-life to `stage_build`; extend `reset`.
- `docs/cockpit.html` — build-view headline/lede/copy, Stage 1 additions, Stage 2 → 2a/2b, BYOB twisty, reset twisty.

---

## Task 1: Shared gateway-API helpers (`_gwapi.py`) + unit tests

**Files:**
- Create: `gateway/seed/_gwapi.py`
- Test: `gateway/seed/test_gwapi.py`

- [ ] **Step 1: Write the failing test**

Create `gateway/seed/test_gwapi.py`:

```python
"""Unit tests for the pure helpers in _gwapi (no network)."""

from _gwapi import match_tool_ids, norm


def test_norm_strips_separators_and_lowercases():
    assert norm("Register_MCP-Server") == "registermcpserver"
    assert norm("add_tax") == "addtax"


def test_match_tool_ids_matches_by_normalized_name():
    tools = [
        {"name": "add_tax", "id": "t1"},
        {"name": "sales-tax-add-tax", "id": "t2"},
        {"name": "convert", "id": "t3"},
    ]
    # exact-normalized "add_tax" should resolve to the first matching tool
    assert match_tool_ids(tools, ["add_tax"]) == ["t1"]
    # "convert" resolves to t3
    assert match_tool_ids(tools, ["convert"]) == ["t3"]


def test_match_tool_ids_skips_unknown_and_dedupes():
    tools = [{"name": "add_tax", "id": "t1"}]
    assert match_tool_ids(tools, ["add_tax", "nope", "add_tax"]) == ["t1"]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd gateway/seed && uv run --with pytest pytest test_gwapi.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named '_gwapi'`.

- [ ] **Step 3: Write the helper**

Create `gateway/seed/_gwapi.py`:

```python
"""Shared helpers for talking to the ContextForge gateway admin API.

Run via `uv run --with httpx` so a full Python stdlib + httpx is always present
(some demo hosts ship python3-minimal without the stdlib `json` module).

Env:
    GATEWAY_URL   gateway base (default http://localhost:4444)
    ADMIN_TOKEN   admin bearer token (required for mutating calls)
"""

import os

import httpx

BASE = os.environ.get("GATEWAY_URL", "http://localhost:4444").rstrip("/")
TOKEN = os.environ.get("ADMIN_TOKEN", "")
H = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def client():
    return httpx.Client(base_url=BASE, headers=H, timeout=60)


def jget(c, path):
    """GET path and return parsed JSON, or [] on any error."""
    try:
        return c.get(path).json()
    except Exception:
        return []


def api(c, method, path, **kw):
    return c.request(method, path, **kw)


def norm(s):
    """Normalize a tool name for fuzzy matching: lowercase, drop _ and -."""
    return (s or "").lower().replace("_", "").replace("-", "")


def match_tool_ids(tools, names):
    """Resolve tool *names* to gateway tool ids via normalized matching.

    `tools` is the /tools list (dicts with 'name'/'originalName' and 'id').
    Returns ids in request order, de-duplicated, skipping names with no match.
    """
    tmap = {}
    for t in tools:
        n = t.get("name") or t.get("originalName") or ""
        tid = t.get("id")
        if n and tid:
            tmap[n] = tid
    out = []
    for name in names:
        want = norm(name)
        for tn, tid in tmap.items():
            tnn = norm(tn)
            if tnn == want or tnn.endswith(want) or want in tnn:
                if tid not in out:
                    out.append(tid)
                break
    return out
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd gateway/seed && uv run --with pytest pytest test_gwapi.py -v`
Expected: PASS (3 passed).

- [ ] **Step 5: Lint + commit**

```bash
uvx black gateway/seed/_gwapi.py gateway/seed/test_gwapi.py
uvx ruff check gateway/seed/_gwapi.py gateway/seed/test_gwapi.py
git add gateway/seed/_gwapi.py gateway/seed/test_gwapi.py
git commit -m "feat(seed): shared gateway-API helpers + unit tests (#9)"
```
Expected: lint clean; commit succeeds.

---

## Task 2: `register.py` — delete-then-recreate a gateway backend (fixes D8)

**Files:**
- Create: `gateway/seed/register.py`

This is mostly network I/O; the pure matching logic is already tested in Task 1. Verification is a manual run against a live gateway in Task 11. Keep it tiny and obvious.

- [ ] **Step 1: Write the script**

Create `gateway/seed/register.py`:

```python
"""Register (or RE-register) a backend MCP server into the gateway.

Unlike a bare POST that treats "already exists" as success, this DELETEs any
existing gateway record of the same name first, so the gateway re-discovers the
backend's current tool list (e.g. a freshly-added `convert`). Mirrors seed.py.

Usage:
    ADMIN_TOKEN=... uv run --with httpx python gateway/seed/register.py \
        <name> <url> [transport]
Example:
    register.py sales-tax http://sales-tax:8000/mcp STREAMABLEHTTP
"""

import sys

from _gwapi import api, client, jget


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: register.py <name> <url> [transport]")
    name, url = sys.argv[1], sys.argv[2]
    transport = sys.argv[3] if len(sys.argv) > 3 else "STREAMABLEHTTP"

    with client() as c:
        for g in jget(c, "/gateways"):
            if g.get("name") == name and g.get("id"):
                d = api(c, "DELETE", f"/gateways/{g['id']}")
                print(f"[gw] delete existing {name}: {d.status_code}")
        r = api(
            c,
            "POST",
            "/gateways",
            json={
                "name": name,
                "url": url,
                "transport": transport,
                "description": f"{name} MCP server",
            },
        )
        print(f"[gw] register {name}: {r.status_code} {r.text[:160]}")
        if r.status_code not in (200, 201):
            sys.exit(1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Lint + commit**

```bash
uvx black gateway/seed/register.py
uvx ruff check gateway/seed/register.py
git add gateway/seed/register.py
git commit -m "feat(seed): register.py — delete-then-recreate a gateway backend (#9)"
```
Expected: lint clean; commit succeeds.

---

## Task 3: `grant.py` — ensure a virtual server holds a set of tools (D7)

**Files:**
- Create: `gateway/seed/grant.py`

Grants tools to Bob by adding them to a virtual server's `associated_tools`. Unions with any existing association so 2b's `convert` adds to 2a's `add_tax`. Delete-then-recreate (like `seed.py`) so re-runs re-associate cleanly. Prints the vserver UUID on the last line (the Makefile captures it).

- [ ] **Step 1: Write the script**

Create `gateway/seed/grant.py`:

```python
"""Grant tools to Bob by (re)building a virtual server that contains them.

Registering a backend only catalogs its tools; Bob can only CALL a tool that is
in the associated_tools of the virtual server his persona points at. This
ensures a named virtual server exists whose tool set is the UNION of its current
tools and the requested ones, then prints its UUID.

Usage:
    ADMIN_TOKEN=... uv run --with httpx python gateway/seed/grant.py \
        <vserver-name> <tool-name> [<tool-name> ...]
Example:
    grant.py Builder add_tax
"""

import sys

from _gwapi import api, client, jget, match_tool_ids


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: grant.py <vserver-name> <tool-name> [<tool-name> ...]")
    vname, want_names = sys.argv[1], sys.argv[2:]

    with client() as c:
        tools = jget(c, "/tools")
        want_ids = match_tool_ids(tools, want_names)
        if not want_ids:
            sys.exit(
                f"none of {want_names} found in /tools — is the backend registered?"
            )

        servers = jget(c, "/servers")
        existing = next((s for s in servers if s.get("name") == vname), None)
        keep_ids = []
        if existing:
            # preserve whatever this vserver already exposed, then union
            keep_ids = [
                t.get("id") if isinstance(t, dict) else t
                for t in existing.get("associated_tools", [])
            ]
            d = api(c, "DELETE", f"/servers/{existing['id']}")
            print(f"[server] delete existing {vname}: {d.status_code}")

        tids = list(dict.fromkeys([*keep_ids, *want_ids]))  # ordered union
        r = api(
            c,
            "POST",
            "/servers",
            json={
                "server": {
                    "name": vname,
                    "description": f"{vname} virtual server (dev-owned tools)",
                    "associated_tools": tids,
                }
            },
        )
        print(f"[server] create {vname} ({len(tids)} tools): {r.status_code}")
        if r.status_code not in (200, 201):
            sys.exit(1)

        uuid = next(
            (s.get("id") for s in jget(c, "/servers") if s.get("name") == vname), ""
        )
        if not uuid:
            sys.exit("could not read back the Builder UUID")
        print(uuid)  # LAST line = UUID (Makefile captures this)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Lint + commit**

```bash
uvx black gateway/seed/grant.py
uvx ruff check gateway/seed/grant.py
git add gateway/seed/grant.py
git commit -m "feat(seed): grant.py — add tools to a virtual server so Bob can call them (#9)"
```
Expected: lint clean; commit succeeds.

---

## Task 4: `Dockerfile` + compose override for `sales-tax`

**Files:**
- Create: `mcp-servers/sales-tax/Dockerfile`
- Create: `docker-compose.salestax.yml`

- [ ] **Step 1: Write the Dockerfile**

Create `mcp-servers/sales-tax/Dockerfile` (identical to `mcp-servers/fx-rates/Dockerfile`):

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastmcp==3.3.1
COPY server.py .
EXPOSE 8000
CMD ["python", "server.py"]
```

- [ ] **Step 2: Write the override file**

Create `docker-compose.salestax.yml`:

```yaml
# Stage-2-only override: brings up the sales-tax server Bob built in Stage 1 as a
# container on the SAME network as the gateway. NOT referenced by the base
# `make up`, so a fresh clone (no generated server.py) is never affected.
# Host port 8001 lets the Stage-2 health gate probe the CONTAINER unambiguously
# (the raw Stage-1 process still owns host :8000 until it is stopped).
services:
  sales-tax:
    build: ./mcp-servers/sales-tax
    restart: unless-stopped
    ports:
      - "8001:8000"
```

- [ ] **Step 3: Verify the base compose still validates**

Run: `make compose-validate`
Expected: `OK` (the override is not part of the base file; nothing broke).

- [ ] **Step 4: Verify the override composes cleanly**

First make a throwaway `server.py` so the `build:` context resolves:
```bash
cp mcp-servers/sales-tax/_solution.py mcp-servers/sales-tax/server.py
docker compose -f docker-compose.yml -f docker-compose.salestax.yml config --quiet && echo OVERRIDE_OK
rm -f mcp-servers/sales-tax/server.py
```
Expected: prints `OVERRIDE_OK`. (If the host uses podman, substitute `docker-compose -f ... -f ...`.)

- [ ] **Step 5: Commit**

```bash
git add mcp-servers/sales-tax/Dockerfile docker-compose.salestax.yml
git commit -m "feat: sales-tax Dockerfile + stage-2-only compose override (#9)"
```

---

## Task 5: Builder persona template + `bob-install-builder`

**Files:**
- Create: `bob-personas/mcp.builder.json.template`
- Modify: `Makefile` (add `bob-config-builder`, `bob-install-builder`; update `.PHONY`)

- [ ] **Step 1: Write the persona template**

Create `bob-personas/mcp.builder.json.template` (mirror of `mcp.operator.json.template`; `alwaysAllow` lists the dev-owned tools by their gateway-federated names):

```json
{
  "mcpServers": {
    "finbyte-builder": {
      "command": "uvx",
      "args": ["--from", "mcp-contextforge-gateway", "python", "-m", "mcpgateway.wrapper"],
      "env": {
        "MCP_SERVER_URL": "http://localhost:4444/servers/REPLACE_BUILDER_UUID/sse",
        "MCP_AUTH": "Bearer REPLACE_GATEWAY_TOKEN",
        "DATABASE_URL": "sqlite:////tmp/mcpwrapper.db",
        "MCP_WRAPPER_LOG_LEVEL": "OFF"
      },
      "alwaysAllow": [
        "sales-tax-add-tax",
        "fx-rates-convert"
      ],
      "disabled": false
    }
  }
}
```

- [ ] **Step 2: Add the Make targets**

In `Makefile`, immediately after the `bob-install-operator` target (the block ending with `echo "Switch back to the analyst with: make bob-install";`), add:

```makefile
bob-config-builder: ## Print the Bob MCP config for the BUILDER persona (Builder vserver + admin token)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='Builder']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "Builder server not found — run 'make salestax-grant' first" >&2; exit 1; fi; \
	sed -e "s|REPLACE_BUILDER_UUID|$$UUID|" -e "s|REPLACE_GATEWAY_TOKEN|$$ADMIN|" bob-personas/mcp.builder.json.template

bob-install-builder: ## Write .bob/mcp.json for the BUILDER persona (calls the dev's own granted tools)
	@mkdir -p .bob; \
	$(MAKE) -s bob-config-builder > .bob/mcp.json && \
	echo "wrote .bob/mcp.json — BUILDER persona (calls your granted tools: add_tax, convert). Restart Bob."; \
	echo "Switch back to the analyst with: make bob-install"
```

Note: `bob-config-builder` uses the same `python3 -c` JSON parse as the existing `bob-config-operator`. This runs on the **host** (where full python3 is present), not in the devcontainer's python3-minimal path, so it matches the working operator precedent.

- [ ] **Step 3: Update `.PHONY`**

Find the `.PHONY:` line that lists `bob-install-operator` (line ~34) and add `bob-config-builder bob-install-builder` to it.

- [ ] **Step 4: Verify the targets parse**

Run: `make -n bob-install-builder`
Expected: prints the recipe lines with no "No rule to make target" error. (It will reference `bob-config-builder`; a dry-run does not need the gateway up.)

- [ ] **Step 5: Commit**

```bash
git add bob-personas/mcp.builder.json.template Makefile
git commit -m "feat: Builder persona + bob-install-builder (#9)"
```

---

## Task 6: Stage-2 Make targets — `salestax-up`, `salestax-down`, `salestax-register`, `salestax-grant`, `fxrates-extend`

**Files:**
- Modify: `Makefile` (add 5 targets; update `.PHONY`)

- [ ] **Step 1: Add the targets**

In `Makefile`, in the Dev Day section near the other `fxrates-*` / `stage*` targets, add:

```makefile
SALESTAX_COMPOSE := $(COMPOSE) -f docker-compose.yml -f docker-compose.salestax.yml

salestax-up: ## (Stage 2) build + run the Bob-built sales-tax server as a container on the mesh network
	@if [ ! -f mcp-servers/sales-tax/server.py ]; then \
	  echo "mcp-servers/sales-tax/server.py is missing — run 'make stage1-build' or 'make stage1-scaffold' first" >&2; exit 1; fi
	$(SALESTAX_COMPOSE) up -d --build sales-tax
	@echo "sales-tax container up — host :8001 (health probe), gateway reaches it at http://sales-tax:8000/mcp"

salestax-down: ## Stop + remove just the ad-hoc sales-tax container
	@$(SALESTAX_COMPOSE) rm -sf sales-tax 2>/dev/null || true
	@echo "sales-tax container stopped + removed"

salestax-register: ## (Stage 2 fallback) register/refresh sales-tax in the gateway (delete-then-recreate)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/register.py sales-tax http://sales-tax:8000/mcp STREAMABLEHTTP

salestax-grant: ## (Stage 2) grant add_tax into the Builder vserver + install the Builder persona so Bob can CALL it
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/grant.py Builder add_tax | tail -1 >/dev/null; \
	$(MAKE) -s bob-install-builder

fxrates-extend: ## (Stage 2b fallback) give fx-rates a convert tool, rebuild, refresh in the gateway, grant it to Bob
	cp mcp-servers/fx-rates/server_with_convert.py mcp-servers/fx-rates/server.py
	$(COMPOSE) up -d --build fx-rates
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/register.py fx-rates http://fx-rates:8000/mcp STREAMABLEHTTP; \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/grant.py Builder convert add_tax | tail -1 >/dev/null; \
	$(MAKE) -s bob-install-builder
	@echo "fx-rates extended with 'convert', re-discovered, and granted to Bob's Builder persona"
```

Notes:
- `salestax-grant` calls `grant.py Builder add_tax`, then `bob-install-builder` (which reads the now-existing `Builder` vserver). The `| tail -1 >/dev/null` discards grant.py's progress lines from the recipe output; `bob-install-builder` re-resolves the UUID itself.
- `fxrates-extend` grants **`convert add_tax`** so the Builder vserver keeps `add_tax` AND gains `convert` (grant.py unions, but passing both is explicit and order-independent).

- [ ] **Step 2: Update `.PHONY`**

Add `salestax-up salestax-down salestax-register salestax-grant fxrates-extend` to the relevant `.PHONY:` line (the one with the other stage/fxrates targets, line ~34).

- [ ] **Step 3: Verify guard fires without a server.py**

```bash
rm -f mcp-servers/sales-tax/server.py
make salestax-up; echo "exit=$?"
```
Expected: prints the "server.py is missing — run 'make stage1-build'…" message and `exit=2` (non-zero). No container built.

- [ ] **Step 4: Verify the override-compose target parses**

Run: `make -n salestax-down`
Expected: prints the `... rm -sf sales-tax` recipe with no Make error.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "feat: Stage-2 sales-tax up/down/register/grant + fxrates-extend targets (#9)"
```

---

## Task 7: Proof-of-life smoke client + `stage_build` wiring

**Files:**
- Create: `scripts/salestax_smoke.py`
- Modify: `scripts/stages.sh` (`stage_build`)

- [ ] **Step 1: Write the smoke client**

Create `scripts/salestax_smoke.py`:

```python
"""Stage-1 proof-of-life: call add_tax(100) on the BARE sales-tax server.

Uses the async fastmcp.Client (not a hand-rolled HTTP POST — streamable-HTTP
session/init is easy to get wrong). Run via:
    uv run --with fastmcp==3.3.1 python scripts/salestax_smoke.py
Prints a single human line; exits non-zero on failure.
"""

import asyncio
import sys

from fastmcp import Client

URL = "http://localhost:8000/mcp"


async def main():
    async with Client(URL) as c:
        res = await c.call_tool("add_tax", {"amount": 100})
    # fastmcp 3.x: prefer structured .data, fall back to text content
    data = getattr(res, "data", None)
    if not isinstance(data, dict):
        sc = getattr(res, "structured_content", None)
        data = sc if isinstance(sc, dict) else {}
    tax = data.get("tax")
    total = data.get("total")
    if tax is None or total is None:
        print(f"add_tax(100) returned unexpected shape: {data!r}", file=sys.stderr)
        return 1
    print(
        f"add_tax(100, 8.5) -> tax={tax:.2f}, total={total:.2f}   "
        "(no token, no policy - anyone on :8000 can call this)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
```

- [ ] **Step 2: Lint the new script**

```bash
uvx black scripts/salestax_smoke.py
uvx ruff check scripts/salestax_smoke.py
```
Expected: clean.

- [ ] **Step 3: Add the proof-of-life beat to `stage_build`**

In `scripts/stages.sh`, in `stage_build()`, locate the block that begins after the server is confirmed up:

```bash
  echo
  say "${B}The point to land:${R} this works — and that's exactly the problem. Anyone on"
  say "the network calls anything; no redaction, no policy, no audit. Open the"
  say "Inspector and call the tool yourself — notice there's ${B}no token field${R}:"
  echo
```

Replace that block with:

```bash
  echo
  say "${B}② Call it — proof it works (and that's the problem):${R}"
  if uv run --with fastmcp==3.3.1 python scripts/salestax_smoke.py; then
    ok "called add_tax over MCP — no token, no policy, no audit. Anyone on the network could."
  else
    no "smoke call failed — if Bob's server has a bug, drop in the known-good one: ${CYN}make stage1-scaffold${R}, then re-run."
  fi
  echo
  say "Want to poke it by hand too? Open the MCP Inspector (no token field):"
  echo
```

This keeps the existing Inspector launch below it (now framed as the optional "poke it by hand" path).

- [ ] **Step 4: Verify the script is syntactically wired**

Run: `bash -n scripts/stages.sh`
Expected: no output, exit 0 (syntax OK).

- [ ] **Step 5: Commit**

```bash
git add scripts/salestax_smoke.py scripts/stages.sh
git commit -m "feat(stage1): deterministic add_tax proof-of-life via fastmcp.Client (#9)"
```

---

## Task 8: Rewrite `stage_govern` (register → grant → call + 2b)

**Files:**
- Modify: `scripts/stages.sh` (`stage_govern`, and a network-aware health helper)

- [ ] **Step 1: Add a container-health helper near `start_raw`**

In `scripts/stages.sh`, after the `start_raw()` function, add:

```bash
wait_salestax_container(){  # the CONTAINER answers on host :8001 (raw still owns :8000)
  for _ in $(seq 1 40); do
    curl -sf "localhost:8001/health" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}
```

- [ ] **Step 2: Replace the body of `stage_govern`**

Replace the entire `stage_govern()` function (currently the block from `stage_govern(){` through its closing `}` before `stage_controls`) with:

```bash
stage_govern(){
  hd "STAGE 2/4 — govern the tool you just built (register → grant → call)"
  say "Same code — now it goes into the mesh: containerised, in the catalog, and"
  say "reachable only through the one governed seam with a token."
  echo

  if [ ! -f "$SCRATCH_SRC" ]; then
    no "$SCRATCH_SRC doesn't exist — you can't govern what wasn't built."
    say "  Run ${CYN}make stage1-build${R} (have Bob write it) or ${CYN}make stage1-scaffold${R}, then re-run ${CYN}make stage2-govern${R}."
    exit 0
  fi

  say "Bringing up the gateway + OPA + backends (idempotent)…"
  make up   || { no "stack failed to start — see: make logs"; exit 1; }
  make seed || { no "seed failed — retry 'make seed'"; exit 1; }
  ok "mesh seeded — catalog + Operator virtual server built"
  make -s bob-install-operator >/dev/null 2>&1 && ok "Bob set to the OPERATOR persona (can register)" \
    || no "couldn't set operator persona — run 'make bob-install-operator'"
  echo

  say "${B}②a Containerise the tool you built${R} (on the mesh network):"
  make salestax-up || { no "couldn't build/run the sales-tax container — see 'make logs'"; exit 1; }
  if wait_salestax_container; then
    ok "sales-tax container healthy on :8001"
    stop_raw && ok "retired the bare Stage-1 process on :8000 (the container takes over)"
  else
    no "the sales-tax container didn't answer on :8001 — check 'make logs'"; exit 1
  fi
  echo

  say "${B}②b Register it${R} — drive Bob (operator):"
  bob "Register the sales-tax service at http://sales-tax:8000/mcp."
  bob "List everything ContextForge is governing."
  say "  ${D}Fallback:${R} ${CYN}make salestax-register${R}"
  say "  ${D}It's now in the catalog, token-gated — but Bob still ${B}can't call it${R}.${D}"
  say "  Exposing a tool to an agent is a separate grant. That gate ${B}is${R}${D} least-privilege.${R}"
  echo

  say "${B}②c Grant it + call it${R} — make the tool you built usable by your agent:"
  say "  ${CYN}make salestax-grant${R}   ${D}(adds add_tax to a 'Builder' vserver + switches Bob to the builder persona)${R}"
  bob "Add sales tax to \$100."
  say "  ${D}→ governed call through :4444 → 108.50. Built → governed → ${B}used${R}.${D} The loop closes.${R}"
  echo

  say "${B}②d Bonus — have Bob extend an EXISTING service${R} (fx-rates):"
  bob "Add a convert(amount, src_ccy, dst_ccy) tool to the fx-rates service at mcp-servers/fx-rates/server.py, then rebuild it."
  bob "Re-register fx-rates and convert 1000 USD to EUR."
  say "  ${D}Fallback (does all of it):${R} ${CYN}make fxrates-extend${R}"
  say "  ${D}build-from-scratch (sales-tax) AND extend-existing (fx-rates), both governed.${R}"
  echo

  ( open http://localhost:4444/admin 2>/dev/null || xdg-open http://localhost:4444/admin 2>/dev/null || true )
  say "Watch both land in the catalog → ${CYN}make monitor${R} (Admin UI). Next: ${CYN}make stage3-controls${R}"
}
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n scripts/stages.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/stages.sh
git commit -m "feat(stage2): carry sales-tax through register->grant->call + fx-rates extend beat (#9)"
```

---

## Task 9: Extend `reset` (stop container + robust fx-rates restore)

**Files:**
- Modify: `scripts/stages.sh` (`reset` case)

- [ ] **Step 1: Replace the `reset)` case**

In `scripts/stages.sh`, the `case` at the bottom has:

```bash
  reset)    stop_raw; rm -f "$SCRATCH_SRC" && echo "stopped the bare Stage-1 server and removed $SCRATCH_SRC (beat repeats clean; _solution.py kept)." ;;
```

Replace that single line with:

```bash
  reset)
    stop_raw
    rm -f "$SCRATCH_SRC"
    make -s salestax-down >/dev/null 2>&1 || true
    if ! git diff --quiet -- mcp-servers/fx-rates/server.py 2>/dev/null; then
      echo "note: discarding local edits to mcp-servers/fx-rates/server.py (restoring committed version)."
    fi
    git checkout HEAD -- mcp-servers/fx-rates/server.py 2>/dev/null || true
    echo "reset: stopped the bare server, removed $SCRATCH_SRC, stopped the sales-tax container, restored base fx-rates ( _solution.py / server_with_convert.py kept )."
    ;;
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/stages.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Verify reset runs clean (no stack needed)**

```bash
make stage-reset
```
Expected: prints the "reset: stopped the bare server…" line and exits 0. `git status` shows no changes to `mcp-servers/fx-rates/server.py`.

- [ ] **Step 4: Commit**

```bash
git add scripts/stages.sh
git commit -m "feat(reset): stop the sales-tax container + restore base fx-rates with HEAD checkout (#9)"
```

---

## Task 10: Build-view HTML (`docs/cockpit.html`)

**Files:**
- Modify: `docs/cockpit.html`

Each step is one exact find-and-replace. Line numbers are from the current file; match on the quoted text, not the number.

- [ ] **Step 1: Dev-voice the headline + lede**

Replace (l.209–211):

```html
      <h2 style="margin-bottom:8px">Build it live — bare tool → governed mesh</h2>
      <p class="lede">Four stages. At each one <b>you prompt IBM Bob</b> to do the real work — build the server, register it, drive the controls — while <code class="inline">make</code> handles the plumbing. Copy the prompts straight from here into Bob. Every stage has a one-command fallback so a wobbly live edit never stalls the room.</p>
      <div class="note">This is the <b>live-talk</b> path. The all-at-once solo path is <code class="inline">make quickstart</code>; the watch-everything window is the <b>🛰 Cockpit</b> tab.</div>
```

with:

```html
      <h2 style="margin-bottom:8px">Build an MCP server in 2 minutes — then watch it get governed</h2>
      <p class="lede">Four stages. At each one <b>you prompt IBM Bob</b> to do the real work — build the server, <b>containerize it</b>, register it, grant it, drive the controls — while <code class="inline">make</code> handles the plumbing. Copy the prompts straight from here into Bob. Every stage has a one-command fallback if a live edit wobbles.</p>
      <div class="note">The all-at-once path is <code class="inline">make quickstart</code>; the watch-everything window is the <b>🛰 Cockpit</b> tab.</div>
```

- [ ] **Step 2: Add the BYOB twisty (right after the Architecture twisty)**

After the Architecture `</details>` (the one whose summary is `Architecture at a glance`, closing at ~l.224) and before the Stage 1 `<details>`, insert:

```html
    <details class="twisty">
      <summary>No Docker on your laptop? Drive the whole mesh with just Bob</summary>
      <div class="twisty-body">
        <p>You don't need Docker, <code class="inline">uv</code>, or <code class="inline">make</code> to <em>drive</em> this. If the governed stack is running somewhere — a teammate's machine, a VM, or a <b>GitHub Codespace</b> — your laptop only needs IBM Bob. One command points Bob at the gateway over HTTPS:</p>
        <div class="cmd">make connect<button class="copy" data-copy="make connect">copy</button></div>
        <p style="margin-bottom:0">It prints a ready-to-paste <code class="inline">bob mcp add finbyte-gateway … -t http</code> line (streamable-HTTP on <code class="inline">/mcp</code> — verified through the Codespaces proxy). Redaction, least-privilege, and OPA all still apply over that remote connection. See <code class="inline">docs/ONBOARDING.md</code>.</p>
      </div>
    </details>
```

- [ ] **Step 3: Stage 1 — add "What Bob produced", the agentic loop, and the proof-of-life**

In the Stage 1 twisty body, replace the run block (l.232–234):

```html
        <div class="runlabel">② Serve it bare + open the Inspector</div>
        <div class="cmd">make stage1-build<button class="copy" data-copy="make stage1-build">copy</button></div>
        <p style="margin-bottom:0">The MCP Inspector opens with <b>no token field</b> — connect (Via Proxy) and call <code class="inline">add_tax</code> yourself. Anyone on the network could. No redaction, no policy, no audit.</p>
```

with:

```html
        <p class="note" style="margin-top:0">Bob writes, runs, and fixes its own code — if the first <code class="inline">server.py</code> won't start, paste the error back and Bob iterates until it runs.</p>
        <details class="twisty">
          <summary>What Bob produced (<code class="inline">mcp-servers/sales-tax/server.py</code>)</summary>
          <div class="twisty-body">
            <pre><code>from fastmcp import FastMCP

mcp = FastMCP("sales-tax")

@mcp.tool
def add_tax(amount: float, rate_pct: float = 8.5) -> dict:
    """Add sales tax to an amount. `rate_pct` is a percentage, e.g. 8.5 for 8.5%."""
    tax = round(amount * rate_pct / 100, 2)
    return {
        "amount": amount,
        "rate_pct": rate_pct,
        "tax": tax,
        "total": round(amount + tax, 2),
    }

@mcp.custom_route("/health", methods=["GET"])
async def health(request):
    from starlette.responses import JSONResponse
    return JSONResponse({"status": "ok", "server": "sales-tax"})

if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)</code></pre>
          </div>
        </details>
        <div class="runlabel">② Serve it bare + call it</div>
        <div class="cmd">make stage1-build<button class="copy" data-copy="make stage1-build">copy</button></div>
        <p>It runs the server bare on <code class="inline">:8000</code> and calls the tool to prove it works:</p>
        <div class="cmd">add_tax(100, 8.5) → tax=8.50, total=108.50   <span style="color:var(--muted)"># no token, no policy</span></div>
        <p style="margin-bottom:0"><b>That's exactly the problem.</b> Anyone on the network calls anything — no redaction, no policy, no audit. (Want to poke it by hand? <code class="inline">make stage1-build</code> also opens the MCP Inspector, no token field.)</p>
```

Note: this snippet is copied verbatim from `mcp-servers/sales-tax/_solution.py` (the tracked fallback Bob's live build mirrors), so the page matches what Bob produces.

- [ ] **Step 4: Stage 2 — rewrite into 2a (register→grant→call) + 2b (extend)**

Replace the Stage 2 twisty body (l.241–251, from `<p>Building is easy;` through the closing `</div>` before that `</details>`) with:

```html
        <p>Building is easy; <b>governing</b> is the hard part ContextForge solves. Carry the tool you just built into the mesh — then watch the grant be the thing that makes it callable.</p>
        <div class="runlabel">①  Containerize + bring the stack up (operator persona)</div>
        <div class="cmd">make stage2-govern<button class="copy" data-copy="make stage2-govern">copy</button></div>
        <div class="saybob">②a Register it — tell Bob (operator)</div>
        <div class="cmd">Register the sales-tax service at http://sales-tax:8000/mcp.<button class="copy" data-copy="Register the sales-tax service at http://sales-tax:8000/mcp.">copy</button></div>
        <p>Now it's in the catalog, token-gated — but Bob <b>still can't call it</b>. Exposing a tool to an agent is a separate grant. <b>That gate is least-privilege.</b></p>
        <div class="runlabel">②b Grant it, then call it</div>
        <div class="cmd">make salestax-grant<button class="copy" data-copy="make salestax-grant">copy</button></div>
        <div class="saybob">Now tell Bob (builder)</div>
        <div class="cmd">Add sales tax to $100.<button class="copy" data-copy="Add sales tax to $100.">copy</button></div>
        <p><b>→ governed call through <code class="inline">:4444</code> → 108.50.</b> The tool you ran wide-open on <code class="inline">:8000</code> now runs token-gated through the one seam. Built → governed → <b>used</b>.</p>
        <div class="saybob">②c Bonus — have Bob extend an existing service (fx-rates)</div>
        <div class="cmd">Add a convert(amount, src_ccy, dst_ccy) tool to the fx-rates service at mcp-servers/fx-rates/server.py, then rebuild it.<button class="copy" data-copy="Add a convert(amount, src_ccy, dst_ccy) tool to the fx-rates service at mcp-servers/fx-rates/server.py, then rebuild it.">copy</button></div>
        <div class="cmd">Re-register fx-rates and convert 1000 USD to EUR.<button class="copy" data-copy="Re-register fx-rates and convert 1000 USD to EUR.">copy</button></div>
        <div class="warnbox"><b>Fallback</b> (does 2a–2c deterministically): <code class="inline">make salestax-register</code>, <code class="inline">make salestax-grant</code>, <code class="inline">make fxrates-extend</code>.</div>
```

- [ ] **Step 5: De-presenter the Stage 3 + Stage 4 copy**

Stage 3 summary (l.255): replace `<span class="pill rec">the gasp</span>` with `<span class="pill rec">4 controls fire</span>`.

Stage 4 body (l.280): replace `but the room watched it get built.` with `but you built it stage by stage.`

- [ ] **Step 6: Update the Reset twisty**

Replace the Stage-reset cmd line (l.294):

```html
        <div class="cmd">make stage-reset        <span style="color:var(--muted)"># stop Bob's bare server + delete the generated server.py</span><button class="copy" data-copy="make stage-reset">copy</button></div>
```

with:

```html
        <div class="cmd">make stage-reset        <span style="color:var(--muted)"># stop bare server + container, delete generated server.py, restore base fx-rates</span><button class="copy" data-copy="make stage-reset">copy</button></div>
```

- [ ] **Step 7: Eyeball the page**

Run: `open "docs/cockpit.html#build"` (or `xdg-open`). Confirm: new headline; BYOB twisty near the top; Stage 1 shows the code twisty + the `108.50` proof line; Stage 2 shows 2a/2b/2c; no "the gasp"/"the room" copy. Expand/Collapse all still works.

- [ ] **Step 8: Commit**

```bash
git add docs/cockpit.html
git commit -m "docs(cockpit): dev-voice build view + carry sales-tax + BYOB twisty (#9)"
```

---

## Task 11: Full local stage-flow self-test + CI gate

No code changes — this is the integration gate from the spec's "Stage-flow self-test". Requires a working container runtime.

- [ ] **Step 1: Static gate**

```bash
make ci
```
Expected: `lint` clean, `bandit` clean, `compose-validate` prints `OK`. (Runs over the new `gateway/seed/*.py` and `scripts/salestax_smoke.py`.)

- [ ] **Step 2: Fresh-clone safety — `make up` with no generated server.py**

```bash
make stage-reset            # ensure no sales-tax/server.py
make up && make seed
make smoke                  # gateway health → OK
```
Expected: the full base mesh comes up green; no attempt to build `sales-tax`; `make smoke` prints `OK`.

- [ ] **Step 3: Stage 1 — scaffold (stands in for Bob) + proof-of-life**

```bash
make stage1-scaffold
uv run --with fastmcp==3.3.1 python scripts/salestax_smoke.py
```
Expected: prints `add_tax(100, 8.5) -> tax=8.50, total=108.50 …`.

- [ ] **Step 4: Stage 2 — container + register + grant + Bob-callable**

```bash
make salestax-up
curl -sf localhost:8001/health && echo CONTAINER_OK     # container answers on :8001
make salestax-register
make salestax-grant                                      # builds Builder vserver + writes .bob/mcp.json
```
Then verify the tool is callable through the gateway (admin token, the Builder vserver's `/mcp`):
```bash
ADMIN=$(DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- python -m mcpgateway.utils.create_jwt_token -u admin@finbyte.demo --admin -e 600 -s demo-only-change-me-0123456789abcdef 2>/dev/null | tail -1)
BUILDER=$(curl -s -H "Authorization: Bearer $ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='Builder']" | head -1)
echo "Builder vserver = $BUILDER"
curl -s -H "Authorization: Bearer $ADMIN" "localhost:4444/servers/$BUILDER" | python3 -c "import sys,json;d=json.load(sys.stdin);print('associated tools:',[t.get('name') if isinstance(t,dict) else t for t in d.get('associated_tools',[])])"
```
Expected: `CONTAINER_OK`; `register.py` prints a 200/201; `Builder vserver = <uuid>`; the associated-tools list contains the `add_tax` tool. (Optional: launch `bob -y` from repo root and prompt `Add sales tax to $100.` → expect a `108.50` total.)

- [ ] **Step 5: Stage 2b — extend fx-rates + re-discover + grant**

```bash
make fxrates-extend
curl -s -H "Authorization: Bearer $ADMIN" localhost:4444/tools | python3 -c "import sys,json;print('convert present:', any('convert' in (t.get('name') or '') for t in json.load(sys.stdin)))"
```
Expected: prints `convert present: True` (proves D8: the delete-then-recreate re-discovered the new tool).

- [ ] **Step 6: Stage 3 controls still green**

```bash
make stage3-controls >/dev/null 2>&1 || true
make verify-controls
```
Expected: `16 passed, 0 failed`.

- [ ] **Step 7: Reset leaves a clean tree**

```bash
make stage-reset
git status --porcelain mcp-servers/fx-rates/server.py mcp-servers/sales-tax/server.py
```
Expected: empty output (fx-rates restored to committed version; generated sales-tax/server.py removed).

- [ ] **Step 8: Bring the stack down**

```bash
make salestax-down
make down
```
Expected: containers stopped/removed.

---

## Task 12: PR + Codespaces re-test note

- [ ] **Step 1: Push the branch + open the PR**

```bash
git push -u origin feature/issue-9-artifact-continuity
gh pr create --base main --title "Carry the Bob-built server through Stages 1→2 + dev-focus the build page (#9)" \
  --body "Closes #9. Follow-up to #8. See docs/superpowers/specs/2026-06-13-progressive-build-artifact-continuity-design.md and docs/superpowers/plans/2026-06-13-progressive-build-artifact-continuity.md.

Stage 2 now carries the sales-tax server Bob builds in Stage 1: containerize → register → **grant** (Builder vserver + persona) → Bob **calls** it governed (108.50). Adds a co-equal fx-rates 'extend an existing service' beat, a Stage-1 proof-of-life call, a 'just Bob (Codespaces)' build-page twisty, and dev-voiced copy. Codex-reviewed (register≠callable + stale-tool-list fixes folded in).

**Codespaces re-test (required — item #1 changes behavior):** stack up in a Codespace, port 4444 Public, \`make connect\`, then a laptop Bob (\`-t http\` + \`/mcp\`) registers/grants/calls the governed sales-tax tool. To be run by the author before merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 2: Confirm CI is green** — `gh pr checks` until build-scan/lint/rust/scan/test pass.

- [ ] **Step 3: Author runs the Codespaces re-test** (manual; the author has the Codespace) and adds a "Run it from Codespaces (verified)" comment, mirroring #8.

---

## Self-review (completed during planning)

- **Spec coverage:** D1 (Task 4), D2/2b (Tasks 6, 8), D3 (4 stages preserved — Tasks 8), D4 (Task 7), D5 (Task 9), D6 (Task 10 step 2), D7 grant loop (Tasks 1–3, 5, 6, 8), D8 delete-then-recreate (Tasks 2, 6). Goals 1–6 all map to tasks. Fresh-clone safety = Task 11 step 2.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; the one "verify the snippet matches `_solution.py`" note in Task 10 is a guard, not a placeholder (the block is fully written).
- **Type/name consistency:** `match_tool_ids`/`norm` defined in Task 1 and used in Tasks 3; `Builder` vserver name and `sales-tax-add-tax`/`fx-rates-convert` tool names consistent across Tasks 3, 5, 6; `salestax-grant`→`bob-install-builder`→`bob-config-builder`→`mcp.builder.json.template` chain consistent; `SALESTAX_COMPOSE` defined once (Task 6) and used in `salestax-up`/`salestax-down`.
