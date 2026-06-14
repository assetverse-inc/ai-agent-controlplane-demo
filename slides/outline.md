# IBM Bob × ContextForge — Who's in charge of your agents? (Bob Developer Day)

Conference talk, ~40 min, **Bob Developer Day** (developer-leaning audience).
This file is the **source of truth**: `build_deck.py` renders these slides and
speaker notes into `bob-controlplane-talk.pptx`.

- **Story:** A FinByte developer uses IBM Bob (an agentic IDE / MCP client) to
  **build an MCP server from scratch**, then **earn it a control plane** —
  ContextForge (IBM/mcp-context-forge), the **AI agent control plane** — one
  layer at a time. The talk is told bottom-up, the inverse of `make quickstart`:
  you assemble the finished governed mesh by hand and watch each layer go in.
- **Spine:** the progressive build — **build → govern → use → control → mesh** —
  carrying ONE artifact (the `sales-tax` server Bob writes in Stage ①) the whole
  way. The throughline is **`register → grant → call`**: works-but-ungoverned →
  in the catalog but not callable → granted & callable through the one governed
  seam. Three personas (**builder / analyst / operator**) make RBAC concrete.
- **Stage ③ = the four controls** (Policy/OPA, Data protection, Prompt-injection,
  RBAC + rate limits), each proven deterministically by `make verify-controls`
  (`16 passed, 0 failed`).
- **Delivery:** attendees run it **live on their laptops** — `make dev-start`
  walks the build path; `make quickstart` is the one-command finished mesh. They
  watch governance with the real ecosystem tools: **ContextForge's monitor**,
  **MCP Inspector**, **A2A Inspector** (or `make cockpit` for all of it).
- **Theme:** IBM-ish blue `#0F62FE`; dark title/section/close slides, light
  content slides; monospace for prompts / code / blocked-reasons.

All facts below are validated live in this repo (gateway plugins, Rego policy,
fixtures, Python + Rust agents, the operator MCP server, the seed/grant scripts,
the sales-tax stage-1→2 flow, and a real IBM Bob v1.0.4 session).

---

## Part A — The Talk (~13 slides, the dev journey)

1. **Title** — "IBM Bob × ContextForge — Who's in charge of your agents?"
   (Bob Developer Day). Tagline: *build an agent tool with Bob, then watch it
   earn a control plane, one layer at a time.*
2. **The problem** — *You just built an agent tool. Who's in charge of it?* In 30
   seconds Bob stands up an MCP server that moves money — and it's wide open (no
   token/policy/audit). Now it calls peers (A2A). MCP/A2A say how agents connect;
   neither says who's allowed to do what, or proves it.
3. **MCP vs A2A** — vertical (model→tools) vs horizontal (agent→agent); two
   protocols, one missing layer. The same enforcement seam must sit on both.
4. **The progressive build (spine)** — build → govern → use → control → mesh; the
   inverse of `make quickstart`. ONE artifact carried the whole way; the
   throughline is `register → grant → call`.
5. **① Build** — Bob writes `mcp-servers/sales-tax/server.py` from scratch
   (`make stage1-build`). Runs bare on `:8000`; `add_tax(100) → 108.50`. It
   works — and it's totally ungoverned (no token/policy/audit). That exposure is
   what Stage ② fixes, without changing a line.
6. **② Govern** — `register → grant → call`. REGISTER (operator): the same server,
   containerised onto the mesh, joins the catalog — *not callable yet*. GRANT
   (privileged): add `add_tax` to a `Builder` virtual server — *a separate step;
   this boundary is least-privilege*. CALL (builder): Bob calls the tool it built,
   through the gateway → `108.50`. Mechanism folded in: enforced at
   `tool_pre_invoke` / `tool_post_invoke`. 2b bonus: Bob extends a service it
   didn't write (`fx-rates` gains `convert`).
7. **Three personas** — builder (`make bob-install-builder`, calls your granted
   tools) / analyst (`make bob`, 8 tools no wire) / operator (`make bob-operator`,
   4 control-plane tools). Same binary, three actors — RBAC by which virtual
   server the persona points at.
8. **③ Control — Policy (OPA/Rego).** $50,000 wire BLOCKED; $5k or $50k+approval
   ALLOWED; the SAME block fires on the bridged `a2a-payments` agent call.
9. **③ Control — Data protection.** SSN/card/api-key masked before the model sees it.
10. **③ Control — Prompt-injection.** Malicious receipt memo → `[INJECTION_BLOCKED]`.
11. **③ Control — Least-privilege/RBAC + rate limits.** FinOps server has no
    `wire`; only Treasury reaches it. Same grant boundary, deny side.
12. **④ Mesh** — *you just built the quickstart.* The architecture diagram + the
    deterministic proof (`make verify-controls → 16 passed, 0 failed`). Identical
    to the `quickstart` end-state, but the room watched it get built. Watch it in
    monitor / MCP Inspector / A2A Inspector.
13. **Takeaways + also-in-the-box + CTA** — one throughline (build→govern→use);
    `register → grant → call`; enforce at the hook (a2a governed too); three
    personas; prove it (16/16 + audit log). Named-not-demoed: SSO/IdPs, Cedar,
    federation, SIEM. CTA: IBM Bob trial + the repo; walk it with `make dev-start`.

## Part B — Follow-Along Appendix (~7 slides), run LIVE

14. **Before you arrive** — IBM Bob trial + `bob` CLI; Docker (running), `uv`,
    Node.js ≥ 22.15; clone the repo.
15. **Bring it up — two front doors** — `make quickstart` (top-down: finished
    governed mesh, 16/16, no Bob needed) and `make dev-start` (bottom-up: opens
    `docs/cockpit.html` → 🎓 Progressive Build card with the copy-paste prompts).
16. **Drive Bob — ① build & ② govern** — `make stage1-build` (write server.py →
    108.50, ungoverned); `make stage2-govern` (register, not callable) →
    `make salestax-grant` + `make bob-install-builder` (call → 108.50 governed);
    2b `fx-rates` `convert`. Fallback `make stage1-scaffold`; reset `make stage-reset`.
17. **Stage ③ in Bob (analyst)** — `make bob`; exact prompts: `rcpt_pii`
    (redacted), `rcpt_injection` (neutralised), "ask the auditor agent to pay
    $50,000" (blocked, cross-language), "wire $50k yourself" (no wire tool). Tell
    Bob to USE the tool; verify in the monitor Logs.
18. **Operator + BYOB** — `make bob-operator`; list / evaluate policy / register
    fx-rates / recent blocks. Plus `make connect` — drive the whole governed mesh
    from a teammate's box, a VM, or a GitHub Codespace with only Bob installed
    (verified end-to-end).
19. **Watch the control plane — the 3 tools** — `make monitor` (Admin UI),
    `make inspect-mcp` (MCP Inspector → 8 governed tools, wire absent; get_receipt
    → redacted), `make inspect-a2a` (Python + Rust agent cards). One-command:
    `make cockpit` (tmux tiles Bob + 4 watch panes + HOW-TO + Companion :7070).
20. **Troubleshooting** — stage-1 wobble → `make stage1-scaffold` / `make stage-reset`;
    "registered but not callable" → `make salestax-grant` + `bob-install-builder`;
    UUID-changes-on-reseed → re-run the matching install; "Bob narrates" → tell it
    to use the tool, check Logs; wrapper/401 gotchas; `make demo-reset`.

---

## Speaker-notes conventions
- Each slide's notes carry the full talk track + exact commands. ≈28 talk + 12
  live + 3 Q&A.
- Verbatim strings to keep on slides + notes:
  - Stage-1 proof: `add_tax(100, 8.5) → tax=8.50, total=108.50`
  - Block: `Plugin Violation: Wire amount 50000 exceeds the $10,000 auto-approve
    limit and requires dual approval (approval=true). FinByte T&E policy §2.`
  - Masked: `SSN ***-**-6789, card ****-****-****-1111 ... api key [SECRET_REDACTED]`
  - Injection neutralized to: `[INJECTION_BLOCKED]`
  - Rust agent success: `Payment executed: ...`
- The throughline to repeat: **register → grant → call** — registering a backend
  only catalogs its tools; granting it to an agent is a separate, privileged step;
  that boundary is least-privilege.
- Connectivity reality (Part B): wrapper crashes without
  `DATABASE_URL=sqlite:////tmp/mcpwrapper.db`; token must be a REGISTERED user
  (admin@finbyte.demo) — a bob@finbyte.demo token 401s; least-privilege is the
  virtual server scope, not the token identity. The virtual-server UUID changes on
  every reseed — re-run the matching `make bob` / `bob-operator` / `bob-install-builder`.
