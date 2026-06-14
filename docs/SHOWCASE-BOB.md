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
| ② Govern | `make stage2-govern` | **Carry the tool Bob just built into the mesh** — `register → grant → call`. The `sales-tax` server is **containerised** on the mesh network (host `:8001`; the gateway reaches `sales-tax:8000`), Bob **registers** it (catalog + token — but **not callable yet**: the grant is the least-privilege gate), then `make salestax-grant` adds `add_tax` to a **`Builder`** virtual server so Bob **calls it governed** → `108.50`. **2b bonus:** Bob **extends an existing** service (`fx-rates` gains a `convert` tool). Built → governed → **used**. | registers + grants the `sales-tax` it built; extends `fx-rates` | `make salestax-register` · `make salestax-grant` · `make fxrates-extend` |
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

## Beat 2 — Bob's tool gets governed, and Bob extends an existing one  *(Act 2 · the agentic-IDE showcase)*

The signature move: the tool **Bob wrote in Stage 1** doesn't get abandoned — it's
carried into the governed mesh and Bob ends up **calling it back, governed**. Then,
for contrast, Bob **extends a service it didn't write**. Persona: **operator** for
the registration, switching to **builder** to call the granted tool (the stage
targets handle the swaps; `make stage2-govern` narrates the whole beat).

### 2a — Govern the tool you built (`register → grant → call`)

1. **Containerise** — the `sales-tax` server Bob wrote runs as a container on the
   mesh network (host `:8001`; the gateway reaches it at `sales-tax:8000`):
   ```bash
   make salestax-up
   ```
2. **Register** — Bob (operator) onboards it:
   > **"Register the sales-tax service at http://sales-tax:8000/mcp."**

   It's in the catalog, token-gated — **but Bob still can't call it.** Exposing a
   tool to an agent is a separate grant. *That gate is least-privilege.*
3. **Grant + call** — add the tool to a minimal `Builder` virtual server and switch
   Bob to the builder persona, then Bob uses the tool it built:
   ```bash
   make salestax-grant
   ```
   > **"Add sales tax to $100."**   → governed call through `:4444` → **`108.50`**

   The line to land: ***"The tool you ran wide-open two minutes ago now runs
   token-gated through the one seam — and your agent calls it."*** Built → governed → **used**.

### 2b — Bob extends an existing service (the contrast)

The repo ships `mcp-servers/fx-rates/server.py` as a **base** (`get_fx_rate` +
`list_currencies`) so Bob has something it *didn't* write to extend:

> **"Add a `convert(amount, base, quote)` tool to `mcp-servers/fx-rates/server.py`,
> then rebuild it."**
> **"Re-register fx-rates and convert 1000 USD to EUR."**   → `{"converted": 920.0}`

So Bob does **both** kinds of work — build-from-scratch (`sales-tax`) *and*
extend-existing (`fx-rates`) — and the control plane governs each the same way.

**Reliability nets** (live coding is variable):
- The whole 2a path has a deterministic fallback: `make salestax-register`,
  `make salestax-grant` (and `make salestax-up` if the container isn't up).
- For 2b: **`make fxrates-extend`** does it all in one keystroke — drops in the
  finished `server_with_convert.py`, rebuilds, re-registers (delete-then-recreate so
  the new tool is discovered), and grants `convert` to the `Builder` vserver.
- Repeat cleanly: **`make stage-reset`** stops the bare server + the `sales-tax`
  container, removes the generated `server.py`, and restores base `fx-rates`.

> **No Docker on the attendee's laptop?** They can drive this whole governed mesh with
> *only* Bob — `make connect` prints a `bob mcp add … -t http` line pointed at the
> gateway (a teammate's box, a VM, or a **Codespace**). See `docs/ONBOARDING.md`.

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
| The whole progressive build (Stage 1+2) | `make stage-reset` (stops the bare server + `sales-tax` container, removes the generated `server.py`, restores base `fx-rates`) |
| fx-rates back to base (repeat 2b) | `make fxrates-reset` then `make seed` |
| Bob persona | `make bob-install` (analyst) / `make bob-install-operator` / `make bob-install-builder` |
| Prove everything still works | `make verify-controls` → 16/16 |

> After any reseed the FinOps/Operator UUID changes — re-run `make bob-install`
> (or `bob-install-operator`) and restart Bob.
