Layout confirmed: Python `auditor`, Rust `payments`, four MCP servers, gateway, no `pyproject.toml`, no `.github/workflows` yet. I have everything needed to write the brief.

---

# Control-Plane Demo: Maintainer Brief

Synthesized for `ai-agent-controlplane-demo`. Layout confirmed on disk: `a2a-agents/{auditor (Python a2a-sdk), payments (Rust)}`, `mcp-servers/{erp-payments, expense-db, notify, policy-docs}`, `gateway/{custom,plugins,policies,seed}`, `companion`, `scripts`. No `pyproject.toml`, no `.github/workflows/` yet — both are net-new. Tooling is `uv`/`uvx`, matching upstream IBM `mcp-context-forge` v1.0.2.

---

## 1. Makefile targets to adopt/adapt

Source: `/tmp/cf-repo/Makefile` (IBM/mcp-context-forge v1.0.2). Adapted to this repo's polyglot layout (Python + Rust + compose). The `check` aggregate is the single gate to wire into CI.

| Target | Why |
|---|---|
| `format` | ruff `--fix` + black auto-fix on all Python dirs — upstream's highest-value pair. |
| `lint` | ruff + black `--check`, non-mutating gate for CI. |
| `lint-rust` | `cargo fmt --check` + `clippy -D warnings` on the Rust Payments agent (not in upstream; required here). |
| `test` | pytest on Python components; tolerates exit 5 (no tests collected) so it won't break the build. |
| `bandit` | Source-level Python security scan (`-ll`). |
| `pip-audit` | Dependency CVE scan. |
| `gitleaks` | Secret scan — **you requested this; upstream actually uses `detect-secrets`** (see note). Needs a `.gitleaks.toml` allowlist for the deliberate demo SECRET/JWTs. |
| `secrets-baseline` | The real upstream mechanism (`detect-secrets`), kept as the maintained alternative to gitleaks. |
| `sbom` | CycloneDX SBOM + markdown render into `docs/`. |
| `trivy` / `grype` | Image CVE scan — **you requested these; upstream actually uses `osv-scan-image` + `dockle`** (see note). |
| `hadolint` | Dockerfile lint (this one *is* upstream). |
| `compose-validate` | `docker compose config` guard. |
| `smoke` | Post-up gateway health probe. |
| `check` | Aggregate gate: lint + bandit + gitleaks + compose-validate. Wire this into CI. |

**Divergence flags (uncertain — verify before pasting):**
- Upstream uses `detect-secrets-scan`, **not** gitleaks. Both targets are below; pick one. If you keep `gitleaks`, you must add `.gitleaks.toml` allowlisting the demo's intentional `SECRET`/JWT values or the gate will always fail.
- Upstream uses `osv-scan-image` + `dockle` (+ `hadolint`), **not** trivy/grype. `trivy`/`grype` targets are provided as requested but are a divergence.
- No `pyproject.toml` exists, so `bandit -c` was dropped and ruff/black run on defaults (not `-l 200`). Add ruff/black version pins for reproducibility.
- `IMAGES` names are inferred — verify with `docker compose images` (compose project dir is the repo root, so the prefix is likely `ai-agent-controlplane-demo-*`).
- Python tests under `mcp-servers`/`auditor` are unconfirmed; `test` no-ops on pytest exit 5 by design.

```makefile
PY_DIRS  := mcp-servers a2a-agents/auditor companion gateway/seed scripts
COMPOSE  := docker compose
IMAGES  ?= ai-agent-controlplane-demo-auditor:latest ai-agent-controlplane-demo-payments:latest

# --- format / lint / test ---
format: ; uvx ruff check --fix $(PY_DIRS); uvx black $(PY_DIRS)
lint:   ; uvx ruff check $(PY_DIRS); uvx black --check $(PY_DIRS)
lint-rust: ; cd a2a-agents/payments && cargo fmt --check && cargo clippy -- -D warnings
test:   ; @uv run --with pytest pytest -q mcp-servers a2a-agents/auditor || { c=$$?; [ $$c -eq 5 ] || exit $$c; }

# --- security / sbom ---
bandit:    ; uvx bandit -r $(PY_DIRS) -ll
pip-audit: ; uvx pip-audit --strict || true
gitleaks:  ; gitleaks detect --no-git --redact --config .gitleaks.toml        # REQUESTED — upstream uses detect-secrets
secrets-baseline: ; uvx --from detect-secrets detect-secrets scan --update .secrets.baseline   # upstream-faithful
sbom: ; uvx --from cyclonedx-bom cyclonedx-py environment --output-format JSON --output-file docs/sbom.json --no-validate $$(command -v python3); \
        uvx sbom2doc -i docs/sbom.json -f markdown -o docs/sbom.md

# --- docker ---
trivy:  ; @for i in $(IMAGES); do trivy image --severity HIGH,CRITICAL --ignore-unfixed $$i; done   # REQUESTED — upstream uses osv-scan-image
grype:  ; @for i in $(IMAGES); do grype $$i --fail-on high; done                                    # REQUESTED — upstream uses dockle
hadolint:         ; @find . -name Dockerfile -not -path '*/target/*' -exec hadolint {} +
compose-validate: ; $(COMPOSE) config --quiet && echo OK
smoke:            ; @curl -sf localhost:4444/health && echo OK || exit 1

# --- aggregate gate (wire this into CI) ---
check: lint bandit gitleaks compose-validate ; @echo passed
pre-commit: ; @[ -f .pre-commit-config.yaml ] && uvx pre-commit run --all-files || $(MAKE) check
```

Explicitly **skipped** as out of scope for a demo: `mypy`/`ty`/`pyright` (type-check), docs (`handsdown`), `release`/`helm`/`ocp`/`container-push`, `sonar`/`snyk`/`mutmut`, and load/perf (`jmeter`).

---

## 2. CI workflows to adopt

> **Uncertainty (important):** The `ci` topic result was only a *smoke test of schema shape* — it inventoried "23 workflows; lint/pytest/rust/docker/security" from `lint.yml` and `rust.yml` but did **not** return validated per-workflow YAML. The 23-workflow upstream suite is explicitly "comprehensive but heavy for a demo." The mapping below collapses it into the **3 proposed demo workflows** and reuses the verified Makefile targets above as the single source of truth (CI just calls `make`). Treat the YAML as a starting point and validate before committing. There is currently **no `.github/workflows/` directory**, so these are all net-new files.

Sources: `/tmp/cf-repo/.github/workflows/lint.yml`, `/tmp/cf-repo/.github/workflows/rust.yml`.

**Upstream → our 3 workflows:**

| Upstream workflows (of the 23) | → Our workflow | Job(s) |
|---|---|---|
| `lint.yml`, `pytest.yml`, `rust.yml` | `.github/workflows/ci.yml` | `lint` (ruff/black), `test` (pytest), `rust` (fmt/clippy) |
| `security`/`bandit`/`pip-audit`/secret-scan/`sbom` | `.github/workflows/security.yml` | `make ci` minus compose + `sbom` |
| `docker`/compose/image-scan | `.github/workflows/docker.yml` | build images, `compose-validate`, `smoke`, image CVE scan |

```yaml
# .github/workflows/ci.yml
name: ci
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: make lint
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: make test
  rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with: { components: rustfmt, clippy }
      - run: make lint-rust
```

```yaml
# .github/workflows/security.yml
name: security
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: make bandit
      - run: make pip-audit
      - run: make secrets-baseline   # upstream-faithful; swap to `make gitleaks` if you add .gitleaks.toml
      - run: make sbom
      - uses: actions/upload-artifact@v4
        with: { name: sbom, path: docs/sbom.* }
```

```yaml
# .github/workflows/docker.yml
name: docker
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  build-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker compose build
      - run: make compose-validate
      - run: docker compose up -d && sleep 10 && make smoke
      # image CVE scan — upstream uses osv/dockle; trivy shown as requested:
      - run: make trivy || true
```

**CI uncertainties to resolve:**
- Pin actions to commit SHAs (not floating tags) before merging — supply-chain hygiene.
- `astral-sh/setup-uv` / `dtolnay/rust-toolchain` versions are conventional, not verified against upstream's actual `rust.yml`.
- The `docker.yml` health gate assumes gateway on `:4444` per `smoke`; confirm against `docker-compose.yml`.
- Per-workflow upstream YAML was **not** captured — confirm job names/triggers against the real `lint.yml`/`rust.yml` if you want a closer port.

---

## 3. A2A inspector

**Is there an MCP-Inspector equivalent for A2A? Yes.** It is **[a2aproject/a2a-inspector](https://github.com/a2aproject/a2a-inspector)** — the official, language-agnostic web UI (FastAPI + TypeScript), the direct analogue of `@modelcontextprotocol/inspector`. You enter an agent's base URL; it fetches and validates the Agent Card, gives a live chat box to send `message/send`, and shows raw JSON-RPC 2.0 traffic in a debug console. Because it discovers `/.well-known/agent-card.json` and is language-agnostic, **one tool covers both our agents** — the Python a2a-sdk Auditor (`:9001`) and the Rust Payments agent (`:3000`) — with **no code changes**.

**Best tool: run `a2a-inspector` and point it at both base URLs.** Supporting tools: `a2a-cli` (terminal/CI smoke tests), `a2a-tck` (official conformance), and `curl + jq` (zero-dep quick check).

```bash
# THE EQUIVALENT — official A2A web inspector (the answer)
git clone https://github.com/a2aproject/a2a-inspector.git
cd a2a-inspector
uv sync && (cd frontend && npm install && npm run build)
bash scripts/run.sh        # UI at http://127.0.0.1:5001
# In the browser, enter each base URL — it fetches the card, validates, and lets you send a message:
#   Auditor  (Python a2a-sdk):  http://localhost:9001
#   Payments (Rust):            http://localhost:3000
```

```bash
# TERMINAL CLIENT — community a2a-cli (chrishayuk), zero-install via uvx, A2A v0.3.0 JSON-RPC/HTTP
uvx a2a-cli --server http://localhost:9001 send "Audit this transaction batch" --wait   # Auditor
uvx a2a-cli --server http://localhost:9001 chat                                          # interactive
uvx a2a-cli --server http://localhost:3000 send "Initiate a test payment of \$1" --wait  # Payments
uvx a2a-cli --server http://localhost:3000 chat
```

```bash
# CONFORMANCE — official a2aproject/a2a-tck (MUST/SHOULD/MAY spec tests)
git clone https://github.com/a2aproject/a2a-tck.git
cd a2a-tck && uv venv && source .venv/bin/activate && uv pip install -e .
./run_tck.py --sut-host http://localhost:9001 --transport jsonrpc -v   # Auditor
./run_tck.py --sut-host http://localhost:3000 --transport jsonrpc -v   # Payments
./run_tck.py --sut-host http://localhost:9001 --level must             # blocking reqs only
```

```bash
# ZERO-DEP QUICK CHECK — curl + jq (no SDK; the inspector/TCK are the real validators)
curl -s http://localhost:9001/.well-known/agent-card.json | jq .   # Auditor card
curl -s http://localhost:3000/.well-known/agent-card.json | jq .   # Payments card
# raw message/send to the JSON-RPC endpoint (adjust 'url' to the card's endpoint):
curl -s http://localhost:9001/ -H 'content-type: application/json' -d '{
  "jsonrpc":"2.0","id":"1","method":"message/send",
  "params":{"message":{"role":"user","messageId":"m1",
    "parts":[{"kind":"text","text":"Audit this transaction batch"}]}}}' | jq .
```

**Explicitly ruled out:** The Rust `a2a-rs` (EmilLindfors) has **no usable client CLI** — its only binary (`a2a` in `a2a-agents`) is an agent *runner* that launches agents from TOML, and `a2a-client` is a web-frontend library. Inspect the Rust Payments agent with the language-agnostic tools above. The official Python `a2a-sdk` likewise ships no card/message CLI (only a DB-migrations script).

**A2A uncertainties to verify:**
- Well-known path: current convention is `/.well-known/agent-card.json`; older A2A builds probe `/.well-known/agent.json`. If the installed inspector is older it may use the old path. Both our agents serve the new path.
- `a2a-cli` advertises A2A v0.3.0 and is community-maintained (not official a2aproject); if our agents target A2A 1.0, some methods may mismatch — confirm with one `send`.
- TCK defaults historically used port 9999 and `tasks/*` methods; scope with `--transport jsonrpc` and confirm it matches our `message/send` surface.
- Confirm each agent's exact `preferredTransport` and supported methods from its live Agent Card before relying on the `curl` payload.
- Not run against live agents in this environment (they may not be running).

**Source URLs:** https://github.com/a2aproject/a2a-inspector · https://a2aprotocol.ai/docs/guide/a2a-inspector · https://github.com/a2aproject/a2a-tck · https://deepwiki.com/a2aproject/a2a-tck/2.2-running-the-tck · https://github.com/chrishayuk/a2a-cli · https://pypi.org/project/a2a-cli/ · https://github.com/EmilLindfors/a2a-rs · https://crates.io/crates/a2a-client · https://github.com/a2aproject/a2a-python · https://pypi.org/project/a2a-sdk/ · https://a2aproject.github.io/A2A/v0.2.5/topics/agent-discovery/

**Makefile/CI sources:** `/tmp/cf-repo/Makefile` (IBM/mcp-context-forge v1.0.2) · `/tmp/cf-repo/.github/workflows/lint.yml` · `/tmp/cf-repo/.github/workflows/rust.yml`

**Files to create (none exist yet):** `/Users/mg/mg-work/manav/work/ai-experiments/ibm-bob/bob-day-talk/ai-agent-controlplane-demo/.github/workflows/{ci,security,docker}.yml` · `.../.gitleaks.toml` (only if using the `gitleaks` target). Edit in place: `.../Makefile`.
