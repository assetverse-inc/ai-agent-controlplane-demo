# Showcasing Bob — making the demo snazzy

The control-plane story is strong, but don't let Bob look like a button. Bob is an
**agentic IDE**: it plans, writes software, runs commands, and chains many steps
autonomously. These beats put *Bob's* capabilities on stage, with governance
visible the instant it acts. All verified live (IBM Bob v1.0.4 + this stack).

---

## Dev Day track — the progressive build (`make stage1-build` … `stage4-mesh`)

For a **developer** audience the most compelling path is *bottom-up*: start with a
bare tool they recognise, then watch ContextForge earn its place one layer at a
time. That's the inverse of `make quickstart` (which drops you into the finished
mesh). Four scene-setting targets walk the room up the stack — each prepares
state, opens the right window, prints the exact line to type at Bob, and ships a
deterministic fallback so a wobbly live edit never strands the talk:

| Stage | Command | The beat | Bob does | Fallback |
|---|---|---|---|---|
| ① Build | `make stage1-build` | Bob writes a **brand-new MCP server from scratch** (`mcp-servers/sales-tax/server.py`), run bare on `:8000` — **no gateway, no policy, no auth**. The Inspector opens with *no token field*: anyone calls anything. "This works — and that's the problem." | creates the `sales-tax` server live; re-run to serve + inspect it | `make stage1-scaffold` |
| ② Govern | `make stage2-govern` | A real mesh service, now **in the catalog + reachable only through `:4444` with a token** (Bob onboards it). It lands governed but **not yet callable** by Bob — granting it to an agent is a further least-privilege step. (Brings up the stack and seeds the catalog so Bob's operator tools exist; fx-rates stays unregistered for Bob to onboard live.) | `Register the fx-rates service at http://fx-rates:8000/mcp.` | `make fxrates-register` |
| ③ Controls | `make stage3-controls` | The four controls **bite a real call** — run the Beat 1 queue prompt as the analyst; watch `make logs-opa`. | the batch prompt below | `make verify-controls` → 16/16 |
| ④ Mesh | `make stage4-mesh` | The full governed picture — **== the `quickstart` end-state**, but the room watched it get built. Hands off to `make cockpit` / `companion`. | drive Act 1 / Act 2 | — |

The individual beats below are the *content* of stages ①–③; the stage targets just
sequence and narrate them. `make stage-reset` stops the bare Stage-1 server if you
need to bail out. Use this track for the live talk; use `make quickstart` to get an
attendee from zero to the finished stack on their own laptop.

---

## Stage setup — two panes, cause → effect

Arrange your screen so the room sees the agent and the control plane at once:

```
┌──────────────────────────────┬───────────────────────────────┐
│  IBM Bob  (terminal)         │  ContextForge monitor (browser)│
│  the agent acting            │  /admin → Logs / Metrics       │
│  `bob`                       │  `make monitor`                │
└──────────────────────────────┴───────────────────────────────┘
        (optionally a 3rd pane: `make inspect-mcp`)
```

- **Narrative framing** (say it out loud): *"We've handed Bob the keys to FinByte's
  expense & payments workflow. Watch what it tries — and how the control plane keeps
  it safe."* Before the $50k beat: *"Bob is about to wire fifty thousand dollars to a
  vendor it met two minutes ago."*
- **Punchy act order:** end **Act 1** on the $50k block (the gasp); open **Act 2**
  with Bob *building and onboarding* a service (the "wait — it operates the control
  plane too?").
- **Reality check, every beat:** tell Bob to **use the finbyte-gateway tools**, and
  glance at the monitor's **Logs** — a real gateway line means Bob actually called;
  no line means it narrated from the repo. (See Troubleshooting in the RUNBOOK.)

---

## Beat 1 — Bob autonomously works the queue  *(Act 1 · the orchestration showcase)*

Persona: **analyst** — `make bob-install` (8 tools, no wire). One prompt, one
autonomous run that hits **all four controls** in a realistic task:

> **"Process today's pending expenses end to end. For each one: read it, check its
> receipt, approve and reimburse anything clean, and flag anything that needs a wire."**

What the room watches Bob do (4 expenses in the queue):

| Expense | Bob's step | Control that fires |
|---|---|---|
| `exp_clean` ($18) | reads, approves, reimburses | — (clean baseline) |
| `exp_pii` ($240) | reads the receipt | **PII/secret redacted** (`***-**-6789`, `[SECRET_REDACTED]`) |
| `exp_injection` ($65) | reads the receipt | **injection neutralized** (`[INJECTION_BLOCKED]`) |
| `exp_big` ($50,000) | needs a wire → delegates to the **auditor agent** | **OPA blocks it** (cross-language Python→Rust) |

This is the snazzy version of the money shots: not contrived single calls, but Bob
**planning and orchestrating** a batch — and the $50k block lands as a dramatic
interruption mid-flow. Reset fixtures between runs with `make demo-reset`.

---

## Beat 2 — Bob builds & onboards a tool  *(Act 2 opener · the agentic-IDE showcase)*

The signature move: Bob **writes code**, then onboards it to the governed mesh. The
repo ships `mcp-servers/fx-rates/server.py` as a **base** (just `get_fx_rate` +
`list_currencies`) so Bob has something to extend.

Persona: **operator** — `make bob-install-operator` (Bob can edit files *and* call
the operator tools in one session).

1. **Build** — Bob writes the tool:
   > **"Finance needs currency conversion. Add a `convert(amount, base, quote)` tool
   > to `mcp-servers/fx-rates/server.py` that uses the existing rates."**
2. **Deploy** — rebuild the container (you run it, or let Bob run it for extra flair):
   ```bash
   docker compose up -d --build fx-rates
   ```
3. **Onboard + use** — Bob registers it and immediately uses the new governed tool:
   > **"Register the fx-rates service at http://fx-rates:8000/mcp."**
   > **"Now convert 1000 USD to EUR with the new tool."**   → `{"converted": 920.0}`

The line to land: ***"An AI just wrote a service — and the control plane is already
governing it."*** (`fx-rates-convert` now shows up in `make inspect-mcp` and the monitor.)

**Reliability nets** (live coding is variable):
- If Bob's edit wobbles: **`make fxrates-convert`** drops in the finished version
  (`server_with_convert.py`) and rebuilds — one keystroke, then continue at step 3.
- To repeat the beat cleanly: **`make fxrates-reset`** restores the base, and
  **`make seed`** un-registers fx-rates so Bob can onboard it again.

---

## Beat 3 — Bob thinks out loud  *(plan mode)*

Make the agent's reasoning legible. Run a beat (Beat 1 is ideal) in plan mode so the
room sees Bob's plan before it executes:

```bash
bob --chat-mode plan "Process today's pending expenses end to end."
```

Bob lays out the steps it intends to take, then proceeds — a cheap way to show that
this is genuine multi-step reasoning, not a script.

---

## Reset / repeatability cheatsheet

| To reset… | Command |
|---|---|
| The stack + fixtures (between runs) | `make demo-reset` |
| fx-rates back to base (repeat Beat 2) | `make fxrates-reset` then `make seed` |
| Bob persona | `make bob-install` (analyst) / `make bob-install-operator` |
| Prove everything still works | `make verify-controls` → 16/16 |

> After any reseed the FinOps/Operator UUID changes — re-run `make bob-install`
> (or `bob-install-operator`) and restart Bob.
