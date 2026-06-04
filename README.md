# ai-agent-controlplane-demo

> **IBM Bob × ContextForge — the AI agent control plane.** One AI agent, a fintech agent mesh, and a gateway that governs every move. _Who's in charge of your agents?_

<p align="center">
  <img src="docs/diagrams/architecture.svg" alt="Reference architecture: IBM Bob drives a FinByte agent mesh through the IBM ContextForge gateway, with an OPA sidecar, six MCP servers, and two cross-language A2A agents." width="900">
</p>

A turnkey, follow-along demo of [IBM ContextForge](https://github.com/IBM/mcp-context-forge) (the MCP / A2A gateway) acting as the **control plane** between an AI agent (**IBM Bob**) and a fintech ("FinByte") expense-and-payments agent mesh. The gateway sits in the middle of every tool call and every agent-to-agent call, enforces **four controls**, and you can prove all of them with **one command** → `16 passed, 0 failed`.

---

## What is this?

When an AI agent can read receipts, approve expenses, and move money, the question stops being _"can the agent do it?"_ and becomes _"who's in charge of the agent?"_. This demo answers that with a control plane. **IBM Bob** is the agent — an MCP client that drives a FinByte agent mesh (expense lookups, ERP payments, policy docs, notifications, and two autonomous A2A agents). It never talks to those backends directly. Every call flows through **IBM ContextForge**, the gateway that authenticates, authorizes, governs, redacts, and audits — _before_ Bob ever sees a result and _before_ any money moves.

The gateway enforces:

- **Policy (OPA).** A wire over the $10,000 FinByte T&E cap is **blocked** unless it carries dual approval — evaluated live by an Open Policy Agent sidecar against a Rego policy.
- **Data protection.** SSNs, credit-card numbers, API keys, and other secrets in tool output are **masked on the gateway** before they reach the agent (`***-**-6789`, `****-****-****-1111`, `[SECRET_REDACTED]`).
- **Prompt-injection neutralization.** Adversarial instructions hidden in tool output ("SYSTEM: ignore all prior policy…") are **neutralized** to `[INJECTION_BLOCKED]`.
- **RBAC least-privilege.** A FinOps analyst persona simply **has no `wire` tool**; only the privileged operator persona can register servers, read the audit trail, or interrogate policy. (Rate limiting is a built-in ContextForge capability, but it is _not_ configured or demonstrated in this stack.)
- **Agent-mesh governance.** The same policy that stops a direct wire also stops a **cross-language** agent-to-agent payment (a Python auditor delegating a $50k payment to a Rust payments agent) at the bridged tool hook.

The whole stack is path-independent — config, plugins, and Rego policy are baked into the images, so there are **zero host bind-mounts** and it runs from any clone path.

---

## Architecture

<p align="center">
  <img src="docs/diagrams/architecture.svg" alt="Architecture diagram showing Bob, the ContextForge gateway, the OPA sidecar, six MCP servers, and two A2A agents on a private Docker network." width="900">
</p>

IBM Bob connects through the `mcpgateway.wrapper` stdio bridge to a **virtual server** on the gateway (a curated, least-privilege slice of the catalog). The gateway fronts five governed MCP servers, one deliberately-unregistered MCP server, and two A2A agents, with an OPA sidecar for policy decisions. Only the gateway and the two A2A agents publish ports to the host; the OPA sidecar and all MCP servers are reachable only on the Compose private network.

| Component | Kind | Port | Role |
|---|---|---|---|
| **IBM Bob** | AI agent / MCP client | — | Drives the mesh; connects via the `mcpgateway.wrapper` stdio bridge to a virtual server |
| **ContextForge gateway** | MCP/A2A gateway (the control plane) | `4444` (host) | Authn/z, governance, redaction, audit, federation; Admin UI at `/admin` |
| **OPA** | Open Policy Agent sidecar | `8181` (internal) | Evaluates the Rego wire-amount policy (`package mcpgateway`) |
| **expense-db** | MCP server (Python, FastMCP) | `8000` (internal) | `list_pending_expenses`, `get_expense`, `get_receipt` (holds the PII / injection fixtures) |
| **erp-payments** | MCP server (Python, FastMCP) | `8000` (internal) | `approve`, `reimburse`, `wire` (the governed money path) |
| **policy-docs** | MCP server (Python, FastMCP) | `8000` (internal) | `get_policy`, `wire_limit` |
| **notify** | MCP server (Python, FastMCP) | `8000` (internal) | `notify` |
| **controlplane** | MCP server (Python, FastMCP) | `8000` (internal) | Operator surface: `register_mcp_server`, `list_control_plane`, `recent_blocks`, `evaluate_policy` |
| **fx-rates** | MCP server (Python, FastMCP) | `8000` (internal) | `get_fx_rate`, `list_currencies` — **runs but is intentionally unregistered** (for the live-register beat) |
| **auditor** | A2A agent (Python, `a2a-sdk`) | `9001` (host) | Audits expenses; can delegate a payment to the Rust agent |
| **payments** | A2A agent (Rust, `a2a-lf` / `a2a-server-lf`) | `3000` (host) | Executes payments; JSON-RPC at `/jsonrpc`, agent card at `/.well-known/agent-card.json` |

> The seed registers **5 governed MCP servers** (`expense-db`, `erp-payments`, `policy-docs`, `notify`, `controlplane`) plus the **2 A2A agents**, and curates them into three virtual servers (FinOps, Treasury, Operator). `fx-rates` is left unregistered on every seed so the operator demo can register it live.
>
> Naming note: the `controlplane` and `auditor` services read their admin token from an env var named `AUDITOR_TOKEN` (written to `.env.tokens` by `make up`). Despite the name, it is an **admin** JWT — not an auditor-only scope.

---

## How a call is governed

<p align="center">
  <img src="docs/diagrams/call-path.svg" alt="Call path: Bob's tool call enters the gateway, runs through tool_pre_invoke (FinByteGuard queries OPA) and tool_post_invoke (FinByteGuard + PIIFilterPlugin sanitize output) before returning a governed result." width="900">
</p>

Every tool call passes through two gateway plugin hooks. On **`tool_pre_invoke`**, the custom **FinByteGuard** plugin (`gateway/custom/finbyte_guard.py`, on the cpex framework) extracts the call's arguments and asks **OPA** whether the wire-amount policy permits it — denying anything over the $10,000 cap without dual approval, and failing _closed_ if OPA is unreachable. On **`tool_post_invoke`**, FinByteGuard deep-scrubs secrets (`sk-live-…` → `[SECRET_REDACTED]`) and neutralizes prompt injection (→ `[INJECTION_BLOCKED]`), while the cpex **PIIFilterPlugin** masks SSNs and credit-card numbers. Every decision emits an `AUDIT [FinByteGuard] …` line and shows up in the Admin UI's **Logs** tab.

---

## The four controls

<p align="center">
  <img src="docs/diagrams/scenarios.svg" alt="The four controls: OPA wire-amount policy, PII/secret redaction, prompt-injection neutralization, and RBAC least-privilege — each shown as a Bob prompt and the gateway's response." width="900">
</p>

| Control | Prompt to Bob | What ContextForge does |
|---|---|---|
| **1 — Policy (OPA)** | _"Use the finbyte-gateway tools to wire $50,000 to Acme LLC for expense `exp_big`."_ | **Blocks** at OPA: _"…exceeds the $10,000 auto-approve limit… FinByte T&E policy §2."_ Add _"with dual approval"_ → **allowed**. The same policy blocks the cross-language auditor→payments $50k at the bridged `a2a-payments` hook. |
| **2 — Data protection** | _"Fetch receipt `rcpt_pii`, verbatim."_ | **Masks** before Bob sees it: SSN → `***-**-6789`, card → `****-****-****-1111`, API key → `[SECRET_REDACTED]`. |
| **3 — Prompt-injection** | _"Fetch receipt `rcpt_injection`."_ | **Neutralizes** the embedded `SYSTEM: ignore all prior policy…` → `[INJECTION_BLOCKED]`. |
| **4 — RBAC least-privilege** | _"Now wire $50k yourself, directly."_ | Bob **can't** — the FinOps virtual server hides `erp-payments-wire`. MCP Inspector confirms the tool is absent. The operator persona has control-plane tools the analyst lacks. |

Baseline that works: _"Process expense `exp_clean` and reimburse it."_ — a clean $18.50 expense flows straight through.

---

## Two personas (RBAC)

The same Bob binary becomes two different actors depending on which virtual server its `.bob/mcp.json` points at. Both targets rewrite `.bob/mcp.json` (from the `bob-personas/*.template` files, refreshing the live UUID) and launch Bob from the repo root, so they're cwd-proof and reseed-proof.

| | `make bob` — **FinOps analyst** (Act 1) | `make bob-operator` — **platform operator** (Act 2) |
|---|---|---|
| Virtual server | **FinOps** (8 tools) | **Operator** (4 tools) |
| Can do | List/read expenses, read receipts, `approve`, `reimburse`, read policy + wire limit, talk to the **auditor** agent | `register_mcp_server`, `list_control_plane`, `recent_blocks`, `evaluate_policy` |
| **Cannot** do | **No `wire` tool**; can't register servers, read the audit trail, or query policy directly | Not the analyst's expense-handling surface |
| Persona file | `bob-personas/mcp.json.template` (server `finbyte-gateway`) | `bob-personas/mcp.operator.json.template` (server `finbyte-operator`) |

Swap back to the analyst at any time with `make bob`.

---

## Prerequisites

| Tool | Why | How to get it |
|---|---|---|
| **Docker Desktop** (running) | Runs the gateway, OPA, MCP servers, and A2A agents | [docker.com](https://www.docker.com/products/docker-desktop/) — start it before you begin |
| **uv** | Mints the gateway JWT **offline** (no network round-trip) | `https://docs.astral.sh/uv/` |
| **IBM Bob Shell** (`bob`) | The AI agent you'll drive | Your IBM Bob install / [bob.ibm.com](https://bob.ibm.com) |
| **Node.js ≥ 18** (`npx`) | Runs the MCP Inspector | [nodejs.org](https://nodejs.org) |

> Budget **~5 GB** of free disk. On the first run, the pinned ContextForge image pulls once and the seven source images (six MCP servers + the Rust payments agent) build locally. Subsequent cold starts (`make down && make quickstart`) take roughly **~38 seconds** once images are cached.

---

## Quickstart

```bash
git clone <REPO_URL> ai-agent-controlplane-demo
cd ai-agent-controlplane-demo
make quickstart
```

`make quickstart` is **one command** that takes a laptop from nothing to a running, governed mesh: preflight (checks Docker/uv/bob/npx) → bring up the stack → seed (register servers/agents, build the FinOps / Treasury / Operator virtual servers) → configure Bob (FinOps analyst persona) → **prove all four controls (`16/16`)** → print a copy-paste walkthrough card. It's re-runnable — safe to run again if anything stalls. The Admin UI logs in with `admin@finbyte.demo` / `FinByteAdmin!2026`.

### Drive Bob

**Act 1 — FinOps analyst (least-privilege).** Launch with `make bob` (cwd-proof; it refreshes the config first), then try:

- _"Use the finbyte-gateway tools to fetch receipt `rcpt_pii`, verbatim."_ → redacted.
- _"Fetch receipt `rcpt_injection`."_ → `[INJECTION_BLOCKED]`.
- _"Ask the auditor agent to pay $50,000 to Acme LLC."_ → **blocked** at OPA (Python → Rust).
- _"Now wire $50k yourself, directly."_ → Bob has no `wire` tool.

**Act 2 — platform operator.** Quit Bob, then `make bob-operator` to swap personas and relaunch:

- _"List everything ContextForge is governing."_ → `list_control_plane`.
- _"Would a $50,000 wire be allowed? With dual approval?"_ → `evaluate_policy` (deny + reason, then allow).
- _"Register the fx-rates service at `http://fx-rates:8000/mcp`."_ → `register_mcp_server` (a new server joins the catalog live).
- _"Show me what got blocked today."_ → `recent_blocks`.

### The three watch panes

Arrange your screen so you can watch the control plane while you prompt Bob:

```bash
make monitor        # ContextForge Admin UI (/admin): catalog + Overview/Metrics/Logs
make inspect-mcp    # MCP Inspector → the 8 governed tools (erp-payments-wire is ABSENT)
make inspect-a2a    # A2A Inspector → validates the Python + Rust agent cards
```

---

## Prove it / watch the controls

The headless proof is one command:

```bash
make verify-controls       # → RESULT: 16 passed, 0 failed
```

It runs `scripts/money-shots/run-all.sh`, which asserts all four controls plus the cross-language agent-mesh block and the Rust agent successfully executing a within-policy payment — 16 assertions in total. This is the safety net: run it any time to confirm the stack is honest.

To watch the controls fire live as you prompt Bob, see **[`docs/LOG-CHEATSHEET.md`](docs/LOG-CHEATSHEET.md)** — the exact prompt → log-line map (including which beat is _supposed_ to log nothing) — and tail:

```bash
make logs        # raw gateway logs (blocked calls surface as ERROR 'invocation failed')
make logs-opa    # live, readable OPA decisions: ALLOW/DENY + args + reason
```

---

## Project layout

```text
ai-agent-controlplane-demo/
├── a2a-agents/        # the 2 A2A agents: auditor/ (Python, a2a-sdk) + payments/ (Rust, a2a-lf)
├── bob-personas/      # mcp.json templates for the analyst + operator personas (live-UUID rewrite)
├── companion/         # optional browser dashboard (Flask, :7070) to watch the control plane
├── gateway/           # ContextForge image + OPA image: custom/ plugin, plugins/ config, policies/ Rego, seed/
├── mcp-servers/       # the 6 MCP servers: expense-db, erp-payments, policy-docs, notify, controlplane, fx-rates
├── scripts/           # quickstart.sh, demo.sh, watch-decisions.sh, money-shots/ proof suite
├── slides/            # the conference talk deck (.pptx) + outline
└── docs/              # QUICKSTART/RUNBOOK/LOG-CHEATSHEET/SCENARIOS/SHOWCASE-BOB + diagrams/
```

---

## How it works

- **Virtual servers.** The gateway exposes curated, least-privilege slices of the full tool catalog: **FinOps** (8 tools, no wire — the analyst), **Treasury** (the wire path: `wire`, `reimburse`, `a2a_payments`), and **Operator** (4 control-plane tools). RBAC is enforced by _which virtual server_ a persona points at, not by the token identity.
- **The stdio bridge.** Bob connects through `uvx --from mcp-contextforge-gateway python -m mcpgateway.wrapper`, with `MCP_SERVER_URL=http://localhost:4444/servers/<UUID>/sse` and `MCP_AUTH=Bearer <admin JWT>`. Bob reads `.bob/mcp.json` from the repo root — which is why you always launch via `make bob` / `make bob-operator`.
- **Path-independence.** The gateway config, FinByteGuard plugin, and Rego policy are baked into the images (`gateway/Dockerfile`, `gateway/Dockerfile.opa`). Zero host bind-mounts means the stack runs from **any** clone path — even ones Docker can't share, like `/tmp` on macOS.

---

## Troubleshooting & reset

- **Attendee walkthrough:** [`QUICKSTART.md`](QUICKSTART.md) — the 3-pane, follow-along guide.
- **Presenter run order + recovery:** [`docs/RUNBOOK.md`](docs/RUNBOOK.md).
- **Anything drifts / `16/16` fails:** `make demo-reset` (recreate + reseed the gateway), then `make verify-controls`.
- **Footgun — "No MCP servers configured":** you launched `bob` from the wrong directory (often the `bob-personas/` subfolder). Bob looks for `.bob/mcp.json` relative to its cwd. Quit it and run **`make bob`**, which launches from the repo root _and_ refreshes the live UUID after a reseed.

---

## Security / disclaimer

**This is a demo, not production.** The JWTs are signed with a **public** demo secret (`demo-only-change-me-…`), CSRF is disabled for the local HTTP demo, and SSRF guards are loosened for the Compose private network. Do not reuse any of this configuration outside the demo. For production, mint your own secrets, enable HTTPS + CSRF, and tighten SSRF — see the upstream [IBM ContextForge](https://github.com/IBM/mcp-context-forge) project.
