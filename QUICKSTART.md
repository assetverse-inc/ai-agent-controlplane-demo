# QUICKSTART — IBM Bob × ContextForge, live on your laptop

You'll bring up a governed agent mesh, point **IBM Bob** at it, and watch
**ContextForge** govern every move — using the real ecosystem tools (ContextForge's
monitor, **MCP Inspector**, **A2A Inspector**).

---

## 0. Prerequisites (install BEFORE the session — pulls are slow on conference wifi)

| Tool | Why | Get it |
|---|---|---|
| **Docker Desktop** (running) | runs the gateway + servers | docker.com |
| **uv** | mints the gateway token offline | `https://docs.astral.sh/uv/` |
| **IBM Bob Shell** (`bob`) | the AI agent you'll drive | your IBM Bob install |
| **Node.js ≥ 18** (`npx`) | runs MCP Inspector | nodejs.org |

~5 GB free disk; the ContextForge image (~pinned) pulls once on first run.

---

## 1. One command

```bash
git clone <REPO_URL> ai-agent-controlplane-demo
cd ai-agent-controlplane-demo
make quickstart
```

`quickstart` checks your laptop, starts ContextForge + 4 MCP servers + 2 A2A
agents + the operator, registers them, configures Bob, proves all controls
(**16/16**), and prints a walkthrough card. Re-run it any time it stalls.

> If a check says MISSING, install that tool and re-run. If anything drifts
> later: `make demo-reset`, then `make bob-install`.

---

## 2. Arrange your screen — 3 panes

| Pane | Command | Shows |
|---|---|---|
| **Bob** (terminal) | `bob` (from this folder) | the agent acting |
| **ContextForge monitor** (browser) | `make monitor` → `/admin` | the catalog + Overview/Metrics/**Logs** (governance, live) |
| **Inspector** (browser) | `make inspect-mcp` / `make inspect-a2a` | the governed MCP tools / the A2A agent cards |

- **MCP Inspector** (`make inspect-mcp`): connect with **Streamable HTTP**, the
  printed gateway URL, and the `Authorization: Bearer …` header. You'll see **8
  tools — `erp-payments-wire` is absent** (least-privilege, visible in the tool).
- **A2A Inspector** (`make inspect-a2a`, builds once): point at
  `http://host.docker.internal:9001` (Python Auditor) and `:3000` (Rust Payments)
  to fetch + validate the cross-language agent cards.

---

## 3. Act 1 — Bob as the FinOps analyst (least-privilege, governed)

In Bob (the default persona after `quickstart`):

| Prompt | What ContextForge does | Where to watch |
|---|---|---|
| *"Use the finbyte-gateway tools to fetch receipt `rcpt_pii`, verbatim."* | **redacts** SSN/card/secret before Bob sees it | Bob's output (masked) |
| *"Fetch receipt `rcpt_injection`."* | **neutralizes** the embedded prompt-injection | Bob's output (`[INJECTION_BLOCKED]`) |
| *"Ask the auditor agent to pay $50,000 to Acme LLC."* | **blocks** at OPA — cross-language (Python auditor → Rust payments) | Bob says "BLOCKED by control-plane policy"; monitor **Logs** |
| *"Now wire $50k yourself, directly."* | Bob has **no `wire` tool** (the FinOps server hides it) | Bob can't; MCP Inspector confirms wire absent |

> Tell Bob to **use the tool** (not read files). Confirm it's real, not narrated:
> the masked data only exists on the gateway path, and blocks appear in the
> monitor's Logs.

## 4. Act 2 — Bob as the platform operator (Bob operates the control plane)

```bash
make bob-install-operator      # swap personas; restart bob
```
The analyst persona *can't* do any of this — the operator persona can (RBAC):

| Prompt | Tool | Result |
|---|---|---|
| *"List everything ContextForge is governing."* | `list_control_plane` | the federated catalog + virtual-server scopes |
| *"Would a $50,000 wire be allowed? With dual approval?"* | `evaluate_policy` | OPA live: **deny** + reason, then **allow** |
| *"Register the fx-rates service at http://fx-rates:8000/mcp."* | `register_mcp_server` | a NEW server joins the catalog (watch the monitor / re-list) |
| *"Show me what got blocked today."* | `recent_blocks` | the audit trail |

Swap back to the analyst with `make bob-install`.

---

## 5. Reset & troubleshoot

| Symptom | Fix |
|---|---|
| Anything drifts / 16/16 fails | `make demo-reset` → `make verify-controls` |
| Bob lists no tools / "Disconnected" then connects | the FinOps/Operator UUID changes on reseed → re-run `make bob-install` (or `bob-install-operator`), restart Bob |
| Bob *describes* a result instead of calling a tool | tell it to **use the finbyte-gateway tool**; verify via the monitor Logs (no log = it narrated) |
| Want the automated walkthrough instead | `make demo` (stage-gated, pauses each step) |

**Prove every control at any time:** `make verify-controls` → `16 passed, 0 failed`.
