# ai-agent-controlplane-demo

**IBM Bob × ContextForge — "Who's in charge of your agents?"**

A turnkey, follow-along demo of [IBM ContextForge](https://github.com/IBM/mcp-context-forge)
(the MCP/A2A gateway) acting as the **control plane** between an AI agent (IBM Bob)
and a fintech agent mesh: 4 Python MCP servers + a **Python** Auditor A2A agent and a
**Rust** Payments A2A agent. The gateway enforces four controls and you can prove them
with one command.

```
        IBM Bob ──(MCP over SSE + bearer)──▶  ContextForge gateway  ─┬─▶ expense-db (MCP, Py)
                                              :4444                  ├─▶ erp-payments (MCP, Py)
        enforced at the tool hooks:                                  ├─▶ policy-docs / notify (MCP, Py)
          • OPA wire-amount policy                                   ├─▶ a2a_auditor  (A2A, Python)
          • PII / secret redaction                                  └─▶ a2a_payments (A2A, Rust)
          • prompt-injection neutralization                              + OPA sidecar :8181
          • RBAC least-privilege + rate limit
```

## Prerequisites

- **Docker** + Docker Compose, and **`uv`** (`pip install uv`) for minting demo tokens.
- **IBM Bob** (to drive the demo as an agent): sign up for the 30-day trial at
  [bob.ibm.com](https://bob.ibm.com) (IBMid required) and install it **before the session**.
  Bob is an MCP client; you'll point it at the gateway. *(The stack runs and is fully
  provable without Bob — Bob is the agent that drives it.)*

## Quickstart (3 commands)

```bash
cp .env.example .env
make up        # build + start the lite stack (gateway, OPA, 4 MCP servers, 2 A2A agents)
make seed      # register everything + build the FinOps & Treasury virtual servers
```

Prove the controls work:

```bash
make verify-controls     # 16 assertions — all four controls + cross-language A2A
```

## Point IBM Bob at the gateway

```bash
make bob-config          # prints a ready .bob/mcp.json (live FinOps UUID + a Bob token)
```

Paste the output into `~/.bob/mcp_settings.json` (global) or `<project>/.bob/mcp.json`.
It uses the gateway's SSE endpoint for the **FinOps** virtual server:

```json
{ "mcpServers": { "finbyte-gateway": {
    "url": "http://localhost:4444/servers/<FINOPS_UUID>/sse",
    "headers": { "Authorization": "Bearer <token>" },
    "alwaysAllow": [ "...", "a2a-auditor" ]
} } }
```

> If your Bob build prefers the newer streamable-HTTP notation, try
> `"type": "streamable-http"` + `"url"`, or the `"httpURL"` key — the gateway serves SSE
> at `/servers/<uuid>/sse` in this build; confirm against your installed Bob version.

## The four money shots (try these prompts in Bob)

| # | Control | Prompt to Bob | What happens |
|---|---------|---------------|--------------|
| 1 | **Policy (OPA)** | "Wire $50,000 to Acme LLC for expense exp_big." | **BLOCKED** — *"Wire amount 50000 exceeds the $10,000 auto-approve limit… FinByte T&E policy §2."* Add "with dual approval" → allowed. |
| 2 | **Data protection** | "Show me the receipt for expense exp_pii." | SSN/card masked, API key → `[SECRET_REDACTED]` before Bob sees it. |
| 3 | **Prompt-injection** | "Process expense exp_injection." | The receipt's "SYSTEM: ignore all prior policy…" is `[INJECTION_BLOCKED]`. |
| 4 | **Least-privilege** | "Wire funds directly." | Bob can't — the raw `wire` tool isn't in its FinOps server (only the Treasury path reaches it). |

Baseline (works): "Process expense exp_clean and reimburse it."

The same OPA policy also blocks the **agent-to-agent** payment: when the Auditor delegates
a $50k payment to the Rust agent (`a2a-payments`), the gateway blocks it at the tool hook —
the control plane governs the mesh, not just one agent.

## What's in the box

`make help` lists all targets. Lite profile (`make up`) is the attendee default; the full
presenter profile (`make up-full`) adds Postgres/Redis/nginx/Phoenix (OTEL traces).

- `docs/RUNBOOK.md` — on-stage run order + recovery.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — the design + build plan.
- `gateway/custom/finbyte_guard.py` — the policy/redaction plugin.
- `gateway/policies/finops.rego` — the OPA amount-cap policy.
- `slides/` — the talk deck.

Gateway pinned to ContextForge **v1.0.2** (`gateway/IMAGE_DIGEST.txt`).
