I'll synthesize these verification results into a single reference document. Let me work through the content directly since all the data is provided.

# Code & Config Reference — M0 Verification Results

## RESOLVED vs STILL-UNKNOWN

| # | M0 Question | Status | Bottom line |
|---|---|---|---|
| 1 | **Bob `mcp.json` schema** | ✅ RESOLVED (paths/keys/auth confirmed) — ⚠️ one detail needs a live instance | Config at `~/.bob/mcp_settings.json` (global) or `.bob/mcp.json` (project, wins). Top key `mcpServers`. Streamable-HTTP uses **`httpURL`** per the property table, OR **`type:"streamable-http"` + `url`** per the transports page. Bearer via `headers.Authorization`. **STILL-UNKNOWN: whether `headers` attaches to an `httpURL` entry (only verbatim Bearer example uses `url`+`headers`), and which of the two notations the installed build parses.** |
| 2 | **Is `a2aproject/a2a-rs` official?** | ✅ RESOLVED | Real repo in the official `a2aproject` org (created 2026-04-03, Apache-2.0, AGNTCY/LF-contributed). Targets A2A v1 (`VERSION="1.0"`). Caveat: NOT yet listed in the canonical "official SDKs" table (only Python/Go/JS/Java/.NET). De-facto official Rust SDK. Crates published `-lf`-suffixed: `a2a-lf 0.3.0`, `a2a-server-lf 0.4.0`. |
| 3 | **`detect_api_keys` location** | ✅ RESOLVED (per WebFetch) — ⚠️ confirm literal file | `detect_api_keys` is a **`PIIFilterPlugin` config key** in `config-pii-guardian-policy.yaml`. **STILL-UNKNOWN: verify the literal file content (sourced via WebFetch summary, not raw file read).** |
| 4 | **Injection-on-tool-output plugin** | ✅ RESOLVED | `SecretsDetection` + `CodeSafetyLinterPlugin` hook **`tool_post_invoke`** and block. The shared `TOOL_POST_INVOKE` runs after A2A/tool branches converge. `DenyListPlugin` hooks only `prompt_pre_fetch` (NOT tool output). |
| 5 | **A2A tool hooks** | ✅ RESOLVED | `invoke_tool` A2A branch runs `TOOL_PRE_INVOKE` inline; shared `TOOL_POST_INVOKE` runs after branches converge; `unified_pdp` + filters apply. `UnifiedPDPPlugin` hooks `tool_pre_invoke`/`resource_pre_fetch`. |
| 6 | **OPA-vs-native PDP (amount cap)** | ✅ RESOLVED | **Native engine CANNOT do an `amount >= 10000` cap** — only 3 operators (exact-eq, `_prefix`, `_contains`), no numeric ops, and tool args are not exposed to native conditions. **OPA sidecar is required** for the amount-cap demo. ⚠️ STILL-UNKNOWN: the OPA query path (docstring says `/v1/data/{path}/allow`, code says `/v1/data/{path}`) — code is authoritative, verify against the running build. |

**Net: all six M0 questions are answered.** Four are fully nailed down (a2a-rs official, detect_api_keys, injection plugin, a2a hooks, OPA-vs-native). The remaining live-instance confirmations are narrow: (a) Bob `httpURL`+`headers` combination and which HTTP notation the build parses; (b) the unified_pdp OPA query-path suffix; (c) end-to-end a2a-rs ↔ a2a-python JSON-RPC interop.

---

## 1. ContextForge — API, JWT, plugins

### JWT token generation
```bash
python3 -m mcpgateway.utils.create_jwt_token
# flags: -u/--username, -e/--exp (MINUTES, 0 disables), -s/--secret,
#        --algo, --admin, --teams, --scopes, --full-name
```

### Backend / virtual-server / A2A registration
- **Backend gateway:** `POST /gateways` `{name, url, description, transport}`
- **Virtual server:** `POST /servers` wrapping a server object with `associated_tools`; bundle agents via `associated_a2a_agents`.
- **A2A agent:** `POST /a2a` `{name, endpoint_url, agent_type, description, auth_type, auth_value, tags}` → creates tool `a2a_NAME`.
- **Invoke A2A:** `/rpc` `tools/call` (`arguments`) OR `/a2a/NAME/invoke` (`parameters`).
- **MCP endpoint:** `/servers/UUID/mcp`, port **4444**.

### Register an A2A agent — `POST /a2a` (confirmed, verbatim)
Source: https://ibm.github.io/mcp-context-forge/using/agents/a2a/
```bash
curl -X POST "http://localhost:4444/a2a" -H "Authorization: Bearer $MCPGATEWAY_BEARER_TOKEN" -H "Content-Type: application/json" -d '{"name":"hello_world_agent","endpoint_url":"http://localhost:9999/","agent_type":"jsonrpc","auth_type":"api_key","auth_value":"your-api-key","tags":["ai"]}'
```

### Plugin hook map (M0 Q4/Q5)
- **A2A hooks:** `invoke_tool` A2A branch runs `TOOL_PRE_INVOKE` inline; shared `TOOL_POST_INVOKE` runs after branches converge; `unified_pdp` + filters apply.
- **`detect_api_keys`** is a `PIIFilterPlugin` key in **`config-pii-guardian-policy.yaml`**.
- **`SecretsDetection` + `CodeSafetyLinterPlugin`** hook **`tool_post_invoke`** and block.
- **`DenyListPlugin`** hooks **only `prompt_pre_fetch`**.
- **`UnifiedPDPPlugin`** hooks `tool_pre_invoke` / `resource_pre_fetch`. OPA via `engine: opa`, setting `opa_url` default `http://localhost:8181`.

### Relevant env vars
```
MCPGATEWAY_A2A_ENABLED=true
AUTH_REQUIRED=true
SSRF_*=false            # SSRF defaults are false
MAX_FAILED_LOGIN_ATTEMPTS=5
ACCOUNT_LOCKOUT_DURATION_MINUTES=60
```

**Uncertainties:** `POST /tokens` body field names — verify against live `/docs`. `detect_api_keys` in `config-pii-guardian-policy.yaml` came via WebFetch summary — confirm literal file. `--exp` is MINUTES per source.

---

## 2. FastMCP server

**Two distinct `FastMCP` classes.** Use **standalone `fastmcp` v3.x (RECOMMENDED)** for a capable/maintained server, or the **official `mcp` SDK** for the leaner dependency.

| | standalone `fastmcp` (jlowin → PrefectHQ) | official `mcp` SDK (modelcontextprotocol) |
|---|---|---|
| Version | **3.x GA** (3.0 GA Feb 18 2026; latest stable **3.3.1**, May 15 2026; 3.4.0b1 prerelease May 23) | **~1.27.2** (bundles a FastMCP 1.x-derived class) |
| Import | `from fastmcp import FastMCP` | `from mcp.server.fastmcp import FastMCP` |
| Install | `uv pip install fastmcp` / `pip install fastmcp` | `uv add "mcp[cli]"` / `pip install "mcp[cli]"` |
| Tool decorator | `@mcp.tool` (bare; `@mcp.tool()` still works) | `@mcp.tool()` |
| Run streamable HTTP | `mcp.run(transport="http", host="0.0.0.0", port=8000)` | `mcp.run(transport="streamable-http")`; host/port via `mcp.settings.host`/`.port` |
| Default mount | `/mcp` (port 8000) | `/mcp` (also `/sse`), port 8000 |

> **Transport-string difference:** v3 uses `"http"` (== streamable HTTP); v2 used `"streamable-http"`. Official SDK uses `"streamable-http"`.

### Minimal streamable-HTTP server — fastmcp v3 (RECOMMENDED, confirmed)
Source: https://gofastmcp.com/deployment/running-server + https://gofastmcp.com/servers/tools
```python
# server.py — FastMCP 3.x (jlowin/fastmcp, GA 3.0 Feb 2026; latest 3.3.1)
from fastmcp import FastMCP

mcp = FastMCP("Expenses Demo")

# Fake data store for the demo
_EXPENSES = {
    "exp_001": {"id": "exp_001", "vendor": "Acme Travel", "amount": 412.50,
                "currency": "USD", "status": "pending", "receipt_id": "rcpt_001"},
    "exp_002": {"id": "exp_002", "vendor": "CloudCo", "amount": 99.00,
                "currency": "USD", "status": "pending", "receipt_id": "rcpt_002"},
}
_RECEIPTS = {
    "rcpt_001": {"id": "rcpt_001", "text": "Flight SFO->JFK", "total": 412.50},
    "rcpt_002": {"id": "rcpt_002", "text": "Monthly SaaS subscription", "total": 99.00},
}

@mcp.tool
def list_pending_expenses() -> list[dict]:
    """Return all expenses currently awaiting approval."""
    return [e for e in _EXPENSES.values() if e["status"] == "pending"]

@mcp.tool
def get_expense(id: str) -> dict:
    """Fetch a single expense by its id."""
    return _EXPENSES.get(id, {"error": "not_found", "id": id})

@mcp.tool
def get_receipt(id: str) -> dict:
    """Fetch a receipt by its id."""
    return _RECEIPTS.get(id, {"error": "not_found", "id": id})

if __name__ == "__main__":
    # v3 transport string is "http" (== streamable HTTP). Served at /mcp.
    mcp.run(transport="http", host="0.0.0.0", port=8000)
```

### Minimal streamable-HTTP server — official mcp SDK (alternative, confirmed)
Source: https://github.com/modelcontextprotocol/python-sdk/blob/main/README.md
```python
# server.py — official mcp SDK (modelcontextprotocol/python-sdk, ~1.27.x)
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Expenses Demo")
mcp.settings.host = "0.0.0.0"   # host/port live on settings in this SDK
mcp.settings.port = 8000

@mcp.tool()
def list_pending_expenses() -> list[dict]:
    """Return all expenses currently awaiting approval."""
    return [{"id": "exp_001", "vendor": "Acme Travel", "amount": 412.50, "status": "pending"}]

@mcp.tool()
def get_expense(id: str) -> dict:
    """Fetch a single expense by id."""
    return {"id": id, "vendor": "Acme Travel", "amount": 412.50, "status": "pending"}

@mcp.tool()
def get_receipt(id: str) -> dict:
    """Fetch a receipt by id."""
    return {"id": id, "text": "Flight SFO->JFK", "total": 412.50}

if __name__ == "__main__":
    # default mount path is /mcp
    mcp.run(transport="streamable-http")
```

### Run command + default path
```bash
# Both serve streamable HTTP at:  http://<host>:8000/mcp
python server.py

# jlowin/fastmcp v3 also ships a CLI:
fastmcp run server.py --transport http --host 0.0.0.0 --port 8000
#   plus:  fastmcp list   and   fastmcp call

# IMPORTANT version difference in the run() transport string:
#   jlowin/fastmcp v3 : mcp.run(transport="http", host=..., port=...)   # "http" == streamable HTTP
#   official mcp SDK  : mcp.run(transport="streamable-http")            # host/port via mcp.settings
```

### Minimal Dockerfile
```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Pin the library you chose:
#   standalone:  fastmcp==3.3.1
#   official:    mcp[cli]==1.27.2
RUN pip install --no-cache-dir fastmcp==3.3.1

COPY server.py .

# Streamable HTTP listens on 8000 at /mcp
EXPOSE 8000

# Bind 0.0.0.0 so the gateway/container network can reach it
CMD ["python", "server.py"]
```

### Controlling exact gateway-visible tool output
For PII/injection fixtures: put the **raw/untrusted payload in the `content` TextContent block** (what the model/gateway reads), keep parseable JSON in `structuredContent`. A plain dict/list is auto-converted (primitives wrapped under `result`; annotations generate both `content` and `structuredContent`).

**fastmcp v3 — `ToolResult` (confirmed)** — source https://gofastmcp.com/servers/tools
```python
from fastmcp import FastMCP
from fastmcp.tools.tool import ToolResult
from mcp.types import TextContent

mcp = FastMCP("Expenses Demo")

@mcp.tool
def get_receipt(id: str) -> ToolResult:
    """Return a receipt; full control over what the gateway/model sees."""
    return ToolResult(
        content=[TextContent(type="text", text="Flight SFO->JFK  card ****1234")],
        structured_content={"id": id, "total": 412.50, "text": "Flight SFO->JFK"},
        meta={"source": "fixture"},
    )
```

**official SDK — `CallToolResult` (confirmed)** — source https://github.com/modelcontextprotocol/python-sdk/blob/main/README.md
```python
from mcp.server.fastmcp import FastMCP
from mcp.types import CallToolResult, TextContent

mcp = FastMCP("Expenses Demo")

@mcp.tool()
def get_receipt(id: str) -> CallToolResult:
    return CallToolResult(
        content=[TextContent(type="text", text="Response visible to model")],
        structuredContent={"status": "success", "data": {"id": id, "total": 412.50}},
        _meta={"internal": "metadata"},
    )
```

> Production behind a gateway: official SDK README recommends `stateless_http=True` and `json_response=True` on the streamable HTTP transport for scalability.

**Uncertainties:** verify the v3 `transport="http"` vs `"streamable-http"` alias behavior on running 3.3.1 (`python -c 'import fastmcp; help(fastmcp.FastMCP.run)'`); confirm `ToolResult` import path (`from fastmcp.tools.tool import ToolResult` vs a possible top-level re-export); confirm pins at build time; which field a given gateway treats as "the tool output" depends on the gateway implementation.

---

## 3. A2A Python agent (`a2a-sdk` v1.1.0)

**KEY VERSION FINDING:** the old `A2AStarletteApplication` / `A2ARequestHandler` (0.x line) **no longer exist** in v1.1.0 (zero grep hits, no `a2a/server/apps/` dir). Current pattern is **function-based routes** mounted on a plain Starlette app. `DefaultRequestHandler` is an alias for `DefaultRequestHandlerV2` and now **REQUIRES `agent_card`**. Well-known path is **`/.well-known/agent-card.json`** (NOT `/agent.json`). AgentCard fields are **snake_case**. `TaskState` is a protobuf enum.

### Install + package name (confirmed)
Source: https://github.com/a2aproject/a2a-python (v1.1.0) + helloworld pyproject.toml
```bash
# Package is 'a2a-sdk' (import root: a2a)
pip install "a2a-sdk[http-server]"
# or with uv:
uv add "a2a-sdk[http-server]"
# plus the server runtime deps used by the sample:
pip install "httpx>=0.28.1" "starlette>=0.46.2" "uvicorn>=0.34.2" "sse-starlette>=2.3.5"
```
Sample pins `a2a-sdk>=1.0.3`. SDK at tag **v1.1.0** (released ~May 29 2026). Protocol: `PROTOCOL_VERSION_CURRENT = '1.0'` (also `'0.3'` for compat); `VERSION_HEADER = 'A2A-Version'`.

### Well-known agent card path (from SDK source, confirmed)
Source: https://github.com/a2aproject/a2a-python/blob/v1.1.0/src/a2a/utils/constants.py
```python
# src/a2a/utils/constants.py (v1.1.0)
AGENT_CARD_WELL_KNOWN_PATH = '/.well-known/agent-card.json'
DEFAULT_RPC_URL = '/'
# create_agent_card_routes(agent_card) serves the card at this path by default.
```

### Key imports (current v1.1.0 API, confirmed)
```python
import uvicorn
from starlette.applications import Starlette

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import (
    create_agent_card_routes,
    create_jsonrpc_routes,
)
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
)
# executor side:
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types.a2a_pb2 import TaskState
from a2a.helpers import (
    get_message_text,
    new_task_from_user_message,
    new_text_message,
    new_text_part,
)
```

### `agent_executor.py` (verbatim, v1.1.0, confirmed)
Source: https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/agent_executor.py
```python
from a2a.helpers import (
    get_message_text,
    new_task_from_user_message,
    new_text_message,
    new_text_part,
)
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types.a2a_pb2 import TaskState


class HelloWorldAgent:
    """Hello World Agent."""

    async def invoke(self, user_request: str) -> str:
        """Invoke the Hello World agent to generate a response."""
        return f'Hello, World! I have received your request ({user_request})'


class HelloWorldAgentExecutor(AgentExecutor):
    """Test AgentProxy Implementation."""

    def __init__(self) -> None:
        self.agent = HelloWorldAgent()

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        """Process user request."""
        # 1. Collect a task from request context
        if context.current_task:
            task = context.current_task
        else:
            # 1.1 If there is no task, create one and add it event queue
            task = new_task_from_user_message(context.message)
            await event_queue.enqueue_event(task)

        # 2. Update task status in EventQueue using TaskUpdater class object
        task_updater = TaskUpdater(
            event_queue=event_queue, task_id=task.id, context_id=task.context_id
        )
        await task_updater.update_status(
            state=TaskState.TASK_STATE_WORKING,
            message=new_text_message('Processing request...'),
        )

        # 3. Collect user request from request content and invoke LLM agent to generate content
        query = get_message_text(context.message)
        if query:
            result = await self.agent.invoke(user_request=query)
        else:
            result = 'No text input is provided!'

        # 4. Add generated response as an artifact to EventQueue
        await task_updater.add_artifact(parts=[new_text_part(text=result, media_type='text/plain')])
        print('Result: ', result)

        # 5. Update task status to completed
        await task_updater.update_status(
            state=TaskState.TASK_STATE_COMPLETED,
            message=new_text_message('Request is completed!'),
        )

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        """Raise exception as cancel is not supported."""
        raise NotImplementedError('Cancel is not supported.')
```

### `__main__.py` (verbatim, v1.1.0, confirmed)
Source: https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/__main__.py
```python
import uvicorn

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import (
    create_agent_card_routes,
    create_jsonrpc_routes,
)
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
)
from agent_executor import (
    HelloWorldAgentExecutor,  # type: ignore[import-untyped]
)
from starlette.applications import Starlette


if __name__ == '__main__':
    # Defines the abilities or functions that agent can perform.
    skill = AgentSkill(
        id='echo_bot',
        name='Echo Bot',
        description='An example agent that acknowledges client request and responds with a "Hello World" message.',
        input_modes=['text/plain'],
        output_modes=['text/plain'],
        tags=['a2a', 'echo-example'],
        examples=['hi', 'how are you'],
    )

    # Define a public-facing agent card that allows clients to discover your agent's capabilities.
    public_agent_card = AgentCard(
        name='Hello World Agent',
        description='Just a hello world agent',
        version='0.0.1',
        default_input_modes=['text/plain'],
        default_output_modes=['text/plain'],
        capabilities=AgentCapabilities(streaming=True, extended_agent_card=True),
        supported_interfaces=[
            AgentInterface(
                protocol_binding='JSONRPC',
                url='http://127.0.0.1:9999',
            )
        ],
        skills=[skill],
    )

    # The RequestHandler processes incoming requests and manages tasks.
    # NOTE (v1.1.0): agent_card is now REQUIRED here.
    request_handler = DefaultRequestHandler(
        agent_executor=HelloWorldAgentExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=public_agent_card,
    )

    # Build routes (replaces the old A2AStarletteApplication).
    routes = []
    # Exposes GET /.well-known/agent-card.json
    routes.extend(create_agent_card_routes(public_agent_card))
    # Exposes the JSON-RPC endpoint at '/'
    routes.extend(create_jsonrpc_routes(request_handler, '/'))

    # Plain Starlette ASGI app, served by uvicorn.
    app = Starlette(routes=routes)
    uvicorn.run(app, host='127.0.0.1', port=9999)
```

> `DefaultRequestHandler(agent_executor=..., task_store=..., agent_card=..., extended_agent_card=...optional)`. For v0.3-compat endpoint on the same route, pass `enable_v0_3_compat=True` to `create_jsonrpc_routes` (default False). `create_jsonrpc_routes` can mount GRPC / HTTP_JSON instead of JSONRPC — confirm which binding the gateway expects (sample uses `'JSONRPC'`).

### Outbound HTTP call from inside the executor (httpx, confirmed pattern)
```python
import httpx

# Inside your AgentExecutor.execute(), call another service's REST API.
# Example: the Auditor calls the gateway's `a2a_payments` tool over the gateway
# REST API with a bearer token.
async def call_gateway_a2a_payments(token: str, payload: dict) -> dict:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            'https://gateway.internal/api/tools/a2a_payments',
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json',
            },
            json=payload,
        )
        resp.raise_for_status()
        return resp.json()

# e.g. within execute():
#   result = await call_gateway_a2a_payments(
#       token=my_bearer_token,
#       payload={'amount': 100, 'currency': 'USD', 'to': 'acct_123'},
#   )
```

### Minimal Dockerfile (adapted — `likely`)
```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install the SDK + server deps
RUN pip install --no-cache-dir \
    "a2a-sdk[http-server]" \
    "uvicorn>=0.34.2" \
    "httpx>=0.28.1"

# Copy your agent code (e.g. __main__.py + agent_executor.py)
COPY . /app

EXPOSE 9999

# __main__.py calls uvicorn.run(..., host=..., port=9999).
# For containers, bind 0.0.0.0 (edit __main__.py: host='0.0.0.0').
CMD ["python", "__main__.py"]
```

**Uncertainties:** Dockerfile is adapted (official sample ships a `Containerfile` on `ubi8/python-312` + `uv sync --frozen`/`uv run . --host 0.0.0.0`); the sample binds `127.0.0.1` — change to `0.0.0.0` for containers. Verify installed sub-version with `python -c 'import importlib.metadata as m; print(m.version("a2a-sdk"))'`. Gateway's real `a2a_payments` path/body/auth must be confirmed against its REST spec.

---

## 4. A2A Rust agent (official `a2aproject/a2a-rs`)

**RESOLVED:** `github.com/a2aproject/a2a-rs` IS a real repo in the official `a2aproject` org (created 2026-04-03, last push 2026-05-27, 29 stars, Apache-2.0, maintainer Luca Muscariello / AGNTCY Contributors). Targets A2A v1 (`pub const VERSION = "1.0"`). **Caveat:** not yet listed in the canonical "official SDKs" table (only Python/Go/JS/Java/.NET) — treat as de-facto official Rust SDK. Built on **axum 0.8 + tonic 0.14**, **Rust 1.85+, edition 2024, resolver 2**.

**Recommendation:** use the official-org crates **`a2a-server-lf 0.4.0` + `a2a-lf 0.3.0`**.
- Community alt #1 — `EmilLindfors/a2a-rs` → crate `a2a-rs 0.3.0` (85 stars, ~5947 downloads, hexagonal) but tracks **older A2A v0.3.0** protocol rev, not in the org.
- Community alt #2 — `tomtom215/a2a-rust` → crate `a2a-protocol-sdk 0.5.0` (claims v1.0+TCK, only ~257 downloads, self-asserted).

### Crate names / versions (confirmed)
Source: https://crates.io/api/v1/crates/a2a-server-lf — repo https://github.com/a2aproject/a2a-rs
```
# Published crate names on crates.io (NOTE the -lf suffix; lib names differ):
#   a2a-lf        0.3.0   lib: a2a          "A2A v1 protocol types and core definitions"
#   a2a-client-lf 0.2.0   lib: a2a_client   "A2A v1 ... client"
#   a2a-server-lf 0.4.0   lib: a2a_server   "A2A v1 async server framework"
#   a2a-pb        0.1.8   lib: a2a_pb       protobuf schema + conversions
#   a2a-grpc      0.3.0   lib: a2a_grpc     tonic gRPC bindings
#   a2a-cli       0.1.5   bin: a2acli       standalone CLI
```

### Cargo.toml (confirmed)
Source: https://github.com/a2aproject/a2a-rs/blob/main/Cargo.toml
```toml
[package]
name = "payment-agent"
version = "0.1.0"
edition = "2024"          # workspace uses edition 2024, rust-version 1.85
rust-version = "1.85"

[dependencies]
# Rename the published -lf packages back to the lib names used in examples.
a2a        = { package = "a2a-lf",        version = "0.3.0" }
a2a-server = { package = "a2a-server-lf", version = "0.4.0", default-features = false }

tokio   = { version = "1", features = ["full"] }
axum    = { version = "0.8", features = ["macros"] }
futures = "0.3"
chrono  = { version = "0.4", features = ["serde"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# NOTE: a2a-server-lf default feature is ["rustls-tls"]; we disable it above
# to avoid pulling rustls for a plain-HTTP demo. Drop default-features=false
# if you want the bundled TLS server helper (a2a_server::tls).
```

### v1.0 evidence + transport constants (confirmed)
Source: https://github.com/a2aproject/a2a-rs/blob/main/a2a/src/lib.rs
```rust
// a2a/src/lib.rs
pub const VERSION: &str = "1.0";
pub const SVC_PARAM_VERSION: &str = "A2A-Version";

// a2a/src/types.rs
pub const TRANSPORT_PROTOCOL_JSONRPC: &str = "JSONRPC";
pub const TRANSPORT_PROTOCOL_GRPC: &str = "GRPC";
pub const TRANSPORT_PROTOCOL_HTTP_JSON: &str = "HTTP+JSON";
pub const TRANSPORT_PROTOCOL_SLIMRPC: &str = "SLIMRPC";
```

### Agent-card path served (verbatim, confirmed)
Source: https://github.com/a2aproject/a2a-rs/blob/main/a2a-server/src/agent_card.rs
```rust
/// Well-known path for the public agent card.
pub const WELL_KNOWN_AGENT_CARD_PATH: &str = "/.well-known/agent-card.json";

/// Create an axum router serving the agent card at `/.well-known/agent-card.json`
/// with CORS headers for public discovery.
pub fn agent_card_router<P: AgentCardProducer>(producer: Arc<P>) -> axum::Router {
    axum::Router::new()
        .route(
            WELL_KNOWN_AGENT_CARD_PATH,
            axum::routing::get(handle_agent_card::<P>),
        )
        .with_state(producer)
}
```

### `main.rs` — agent card + payment executor (adapted, `likely`)
Source: https://github.com/a2aproject/a2a-rs/blob/main/examples/src/helloworld/server.rs + examples/src/lib.rs
```rust
// Adapted from a2aproject/a2a-rs examples/src/helloworld/server.rs
// and examples/src/lib.rs (EchoExecutor / build_agent_card). Plain HTTP only.
use std::future::IntoFuture;
use std::sync::Arc;

use a2a::*;                       // re-exports types::*, agent_card::*, event::*, etc.
use a2a::event::StreamResponse;
use a2a_server::*;                // DefaultRequestHandler, AgentExecutor, ExecutorContext,
                                  // ExecutorContext, InMemoryTaskStore, StaticAgentCard ...
use futures::stream::{self, BoxStream};

// ---- 1. The business logic: an AgentExecutor that "executes a payment" ----
struct PaymentExecutor;

impl AgentExecutor for PaymentExecutor {
    fn execute(
        &self,
        ctx: ExecutorContext,
    ) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        let task_id = ctx.task_id.clone();
        let context_id = ctx.context_id.clone();

        // Pull the user's instruction text out of the incoming message parts.
        let instruction = ctx
            .message
            .as_ref()
            .and_then(|m| m.parts.first())
            .and_then(|p| match &p.content {
                PartContent::Text(t) => Some(t.clone()),
                _ => None,
            })
            .unwrap_or_default();

        // Emit a Working status, then a Completed task carrying an agent reply.
        let working = StreamResponse::StatusUpdate(TaskStatusUpdateEvent {
            task_id: task_id.clone(),
            context_id: context_id.clone(),
            status: TaskStatus {
                state: TaskState::Working,
                message: None,
                timestamp: Some(chrono::Utc::now()),
            },
            metadata: None,
        });

        // ... here you'd call your real payment rail ...
        let result_text = format!("Payment executed for instruction: {instruction}");

        let completed = StreamResponse::Task(Task {
            id: task_id.clone(),
            context_id: context_id.clone(),
            status: TaskStatus {
                state: TaskState::Completed,
                message: Some(Message {
                    role: Role::Agent,
                    message_id: new_message_id(),
                    task_id: Some(task_id),
                    context_id: Some(context_id),
                    parts: vec![Part::text(result_text)],
                    metadata: None,
                    extensions: None,
                    reference_task_ids: None,
                }),
                timestamp: Some(chrono::Utc::now()),
            },
            artifacts: None,
            history: None,
            metadata: None,
        });

        Box::pin(stream::iter([Ok(working), Ok(completed)]))
    }

    fn cancel(&self, ctx: ExecutorContext) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        let (task_id, context_id) = ctx.task_info();
        Box::pin(stream::once(async move {
            Ok(StreamResponse::StatusUpdate(TaskStatusUpdateEvent {
                task_id,
                context_id,
                status: TaskStatus {
                    state: TaskState::Canceled,
                    message: None,
                    timestamp: Some(chrono::Utc::now()),
                },
                metadata: None,
            }))
        }))
    }
}

// ---- 2. The agent card ----
fn build_agent_card(interfaces: Vec<AgentInterface>) -> AgentCard {
    AgentCard {
        name: "Payment Agent".to_string(),
        description: "Executes payment instructions.".to_string(),
        version: a2a::VERSION.to_string(), // "1.0"
        provider: Some(AgentProvider {
            organization: "Demo".to_string(),
            url: "https://example.com".to_string(),
        }),
        capabilities: AgentCapabilities {
            streaming: Some(true),
            push_notifications: Some(false),
            extensions: None,
            extended_agent_card: None,
        },
        skills: vec![AgentSkill {
            id: "execute_payment".to_string(),
            name: "Execute Payment".to_string(),
            description: "Executes a payment given an instruction.".to_string(),
            tags: vec!["payment".to_string()],
            examples: None,
            input_modes: None,
            output_modes: None,
            security_requirements: None,
        }],
        default_input_modes: vec!["text/plain".to_string()],
        default_output_modes: vec!["text/plain".to_string()],
        supported_interfaces: interfaces,
        security_schemes: None,
        security_requirements: None,
        documentation_url: None,
        icon_url: None,
        signatures: None,
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt().init();

    let handler = Arc::new(DefaultRequestHandler::new(
        PaymentExecutor,
        InMemoryTaskStore::new(),
    ));
    let agent_card = build_agent_card(vec![
        AgentInterface::new("http://localhost:3000/jsonrpc", TRANSPORT_PROTOCOL_JSONRPC),
        AgentInterface::new("http://localhost:3000/rest", TRANSPORT_PROTOCOL_HTTP_JSON),
    ]);
    let card_producer = Arc::new(StaticAgentCard::new(agent_card));

    let app = axum::Router::new()
        .nest("/jsonrpc", a2a_server::jsonrpc::jsonrpc_router(handler.clone()))
        .nest("/rest", a2a_server::rest::rest_router(handler.clone()))
        .merge(a2a_server::agent_card::agent_card_router(card_producer));

    tracing::info!("Agent card: http://localhost:3000/.well-known/agent-card.json");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).into_future().await.unwrap();
}
```

> Server exports: `DefaultRequestHandler::new(executor, store)`; trait `AgentExecutor { fn execute(&self, ctx: ExecutorContext) -> BoxStream<'static, Result<StreamResponse, A2AError>>; fn cancel(...) }`; `InMemoryTaskStore::new()`; `StaticAgentCard::new(card)`; routers `jsonrpc_router` / `rest_router` / `agent_card_router`. `RequestHandler` implements all A2A methods (send_message, send_streaming_message, get_task, list_tasks, cancel_task, subscribe_to_task, create/get/list/delete_push_config, get_extended_agent_card).

### Endpoints + interop (confirmed)
Source: https://github.com/a2aproject/a2a-rs/blob/main/README.md
```bash
# From a2aproject/a2a-rs README.md:
# "The REST and JSON-RPC bindings are intended to stay wire-compatible with
#  other A2A SDKs, including Go and C# implementations."
#
# Endpoints exposed by the bundled example agent:
#   Agent card:        http://localhost:3000/.well-known/agent-card.json
#   JSON-RPC endpoint: http://localhost:3000/jsonrpc
#   REST endpoint:     http://localhost:3000/rest
#
# The same a2aproject org also owns the conformance kit: a2aproject/a2a-tck.
```

### Multi-stage Dockerfile (`likely`)
```dockerfile
# ---- build stage ----
FROM rust:1.85-bookworm AS builder
WORKDIR /app
# Cargo.toml pins a2a-lf=0.3.0 and a2a-server-lf=0.4.0 (see deps snippet).
COPY Cargo.toml Cargo.lock ./
COPY src ./src
# Commit Cargo.lock so the exact resolved versions are reproduced.
RUN cargo build --release --locked

# ---- runtime stage ----
FROM debian:bookworm-slim AS runtime
# a2a-server-lf default-features were disabled (no rustls); plain HTTP needs no extra libs,
# but keep ca-certificates for outbound TLS (e.g. push notifications / payment rail).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/payment-agent /usr/local/bin/payment-agent
EXPOSE 3000
ENV RUST_LOG=info
ENTRYPOINT ["/usr/local/bin/payment-agent"]
```

**Uncertainties:** Live JSON-RPC interop between `a2a-server-lf 0.4.0` and `a2a-python` was NOT executed (README names Go/C# wire-compat, not Python explicitly — run a2a-python's client or the a2a-tck to confirm). `main.rs` and Dockerfile are `likely`, not test-built. `jsonrpc_router`/`rest_router` signatures taken from example usage, not the source body. Struct/enum fields taken from main branch — pin to a2a-lf 0.3.0 docs.rs to confirm no field drift. TCK pass not confirmed.

---

## 5. OPA unified PDP (amount-cap demo)

**RESOLVED (M0 Q6):** The **native RBAC engine CANNOT do an `amount >= 10000` cap** — only 3 operators (exact-equality, `_prefix`=startswith, `_contains`=set-membership), no numeric comparison, and tool args are not exposed to native conditions. **An OPA sidecar is required.**

### unified_pdp OPA-engine wire facts (confirmed)
- Defaults (`engines/opa_engine.py _DEFAULTS`): `opa_url='http://localhost:8181'`, `policy_path='mcpgateway'`, `timeout_ms=5000`, `max_retries=3`.
- POSTs `{"input": input_doc}` to **`/v1/data/{policy_path}`** (i.e. `/v1/data/mcpgateway`), **no `/allow` suffix** in the actual `evaluate()` code (the module docstring's `/allow` is wrong; code is authoritative).
- Reads `result.allow` (bool) and `result.deny` (array of reason strings). Empty/undefined `result` ⇒ **DENY (fail-closed)**.
- For `tool_pre_invoke`: `action = f'tools.invoke.{payload.name}'`, `resource.type='tool'`, `resource.id=payload.name`, `resource.annotations={'args_keys': [...]}`, `context.extra={'tool_args': payload.args or {}}` ⇒ **tool args appear in Rego at `input.context.tool_args.<argname>`**.
- Plugin class: `plugins.unified_pdp.unified_pdp.UnifiedPDPPlugin`; hooks `tool_pre_invoke` + `resource_pre_fetch`.
- `EngineType`: `opa, cedar, native, mac`. `CombinationMode`: `all_must_allow` (AND), `any_allow` (OR), `first_match`. `default_decision` default = `deny`.
- Separate `plugins/external/opa` plugin uses a DIFFERENT shape (`package example`, `input.mode`, `input.payload.args`, `allow_tool_pre_invoke`) — **do not confuse**.

### 1a. Run OPA sidecar on :8181 (confirmed)
Source: https://hub.docker.com/r/openpolicyagent/opa + https://www.openpolicyagent.org/docs/deployments
```bash
# Simplest: ephemeral server on 8181
docker run -p 8181:8181 openpolicyagent/opa:latest run --server

# Recommended for a demo: mount a local ./policies dir and load it
#   put your wire.rego (package mcpgateway) in ./policies/
docker run -p 8181:8181 \
  -v "$PWD/policies:/policies" \
  openpolicyagent/opa:latest \
  run --server --log-level debug --log-format json-pretty /policies
```

### 1b. Load / sanity-check a policy via REST (confirmed)
Source: https://www.openpolicyagent.org/docs/rest-api
```bash
# Create/update a named policy (use --data-binary so newlines are preserved)
curl -X PUT --data-binary @wire.rego \
  -H "Content-Type: text/plain" \
  http://localhost:8181/v1/policies/mcpgateway

# Sanity-check the decision the way unified_pdp will call it
curl -X POST -H "Content-Type: application/json" \
  -d '{"input":{"subject":{"email":"u@x","roles":["developer"]},"action":"tools.invoke.wire","resource":{"type":"tool","id":"wire"},"context":{"tool_args":{"amount":25000}}}}' \
  http://localhost:8181/v1/data/mcpgateway
# => {"result":{"allow":false,"deny":["Wire amount 25000 ... requires an approval flag"]}}
```

### 2. unified_pdp plugin config pointing at OPA (`likely`)
Source: unified_pdp.py docstring/_build_pdp + opa_engine.py _DEFAULTS
```yaml
- name: "UnifiedPDPPlugin"
  kind: "plugins.unified_pdp.unified_pdp.UnifiedPDPPlugin"
  hooks: ["tool_pre_invoke", "resource_pre_fetch"]
  mode: "enforce"
  priority: 10
  config:
    engines:
      - name: opa
        enabled: true
        priority: 1
        settings:
          opa_url: "http://localhost:8181"
          policy_path: "mcpgateway"   # POSTs to /v1/data/mcpgateway
          timeout_ms: 5000
          max_retries: 3
    combination_mode: "all_must_allow"
    default_decision: "deny"
    cache:
      enabled: true
      ttl_seconds: 60
      max_entries: 10000
    performance:
      timeout_ms: 1000
      parallel_evaluation: true
```

### 2b. Verbatim minimal config (from unified_pdp.py docstring — native; swap to opa above) (confirmed)
```yaml
config:
  engines:
    - name: native
      enabled: true
      priority: 1
      settings:
        rules_file: "plugins/unified_pdp/default_rules.json"
  combination_mode: "all_must_allow"
  default_decision: "deny"
  cache:
    enabled: true
    ttl_seconds: 60
    max_entries: 10000
  performance:
    timeout_ms: 1000
    parallel_evaluation: true
```

### 3. Minimal Rego policy (package `mcpgateway`, amount cap) (`likely`)
Source: derived from opa_engine.py _build_input + _parse_response and unified_pdp.py tool_pre_invoke
```rego
package mcpgateway

# unified_pdp posts {"input": {subject, action, resource, context}} to /v1/data/mcpgateway
# tool args land at input.context.tool_args.* ; action is "tools.invoke.<tool>"
# The OPA engine reads result.allow (bool) and result.deny (array of reason strings).

default allow := false

# Is this an invocation of the wire/payment tool?
is_wire_call if {
    startswith(input.action, "tools.invoke.")
    input.resource.id == "wire"
}
is_wire_call if {
    startswith(input.action, "tools.invoke.")
    input.resource.id == "payment"
}

amount := to_number(input.context.tool_args.amount)
approved if input.context.tool_args.approval == true

# DENY: large wire with no approval flag -> human-readable reason
deny contains msg if {
    is_wire_call
    amount >= 10000
    not approved
    msg := sprintf("Wire amount %v exceeds the 10000 cap and requires an approval flag (approval=true).", [amount])
}

# ALLOW when nothing denied it
allow if {
    is_wire_call
    count(deny) == 0
}

# Allow non-wire tool calls (tune for your demo's default posture)
allow if {
    startswith(input.action, "tools.invoke.")
    not is_wire_call
}
```

### 3b. Exact OPA input document the plugin builds (verbatim, confirmed)
Source: https://github.com/IBM/mcp-context-forge/blob/main/plugins/unified_pdp/engines/opa_engine.py
```python
return {
    "subject": {
        "email": subject.email,
        "roles": subject.roles,
        "team_id": subject.team_id,
        "mfa_verified": subject.mfa_verified,
        "clearance_level": subject.clearance_level,
        **subject.attributes,
    },
    "action": action,
    "resource": {
        "type": resource.type,
        "id": resource.id,
        "server": resource.server,
        "classification_level": resource.classification_level,
        **resource.annotations,
    },
    "context": {
        "ip": context.ip,
        "timestamp": context.timestamp.isoformat(),
        "user_agent": context.user_agent,
        "session_id": context.session_id,
        **context.extra,   # tool_pre_invoke sets extra={"tool_args": payload.args or {}}
    },
}
# -> tool args are reachable in Rego as input.context.tool_args.<argname>
```

### 3c. How the OPA response is parsed (must expose `allow` + `deny`) (confirmed)
```python
result = body.get("result", {})
if not result:
    return EngineDecision(engine=EngineType.OPA, decision=Decision.DENY,
        reason="OPA: no matching policy (undefined result – fail closed)", ...)
allowed = result.get("allow", False)
deny_reasons: List[str] = result.get("deny", [])
return EngineDecision(
    engine=EngineType.OPA,
    decision=Decision.ALLOW if allowed else Decision.DENY,
    reason="; ".join(deny_reasons) if deny_reasons else ("OPA: allowed" if allowed else "OPA: denied"),
    matching_policies=deny_reasons if not allowed else [],
    ...)
```

### 4. How DENY surfaces to the caller (verbatim, confirmed)
Source: https://github.com/IBM/mcp-context-forge/blob/main/plugins/unified_pdp/unified_pdp.py
```python
if decision.decision == Decision.DENY:
    logger.warning("PDP DENY tool_pre_invoke | tool=%s | user=%s | reason=%s",
                   payload.name, subject.email, decision.reason)
    violation = PluginViolation(
        reason="Policy decision: DENY",
        description=decision.reason or "Access denied by unified PDP",
        code="PDP_DENY",
        details={
            "tool": payload.name,
            "user": subject.email,
            "engines": [ed.engine.value for ed in decision.engine_decisions],
        },
    )
    return ToolPreInvokeResult(
        continue_processing=False,
        modified_payload=payload,
        violation=violation,
    )
```

### 5. Why native engine CANNOT do the amount cap (verbatim, confirmed)
Source: https://github.com/IBM/mcp-context-forge/blob/main/plugins/unified_pdp/engines/native_engine.py
```python
# engines/native_engine.py _conditions_match - the ONLY operators:
if key.endswith("_prefix"):           # startswith
    ...
if key.endswith("_contains"):         # set membership
    base_key = key[: -len("_contains")]
    actual = flat.get(base_key, set())
    if expected not in actual:
        return False
    continue
# Default: exact equality
actual = flat.get(key)
if actual != expected:
    return False
# flat lookup exposes ONLY subject.email/mfa_verified/team_id/clearance_level/roles
# and context.ip/session_id/user_agent.  tool_args are NOT present -> no amount cap.
```

> Native rule shape: `{id, roles[], actions[] (fnmatch glob), resource_types[], resource_ids[] (glob), conditions{}, reason}`. Deny rules (`id` starting `deny:`) evaluated first. Subject built from `context.global_context.user` (needs `include_user_info` enabled); defaults `email='anonymous@internal'`, `roles=[]`, `mfa_verified=False`; `session_id` from `request_id`, `server` from `server_id`.

**Uncertainties:** **OPA query path** — docstring says `/v1/data/{path}/allow`, code says `/v1/data/{path}` (code authoritative; verify against your build — if it appends `/allow`, the `deny[]` reasons won't surface). Whether a top-level `hooks:` key is honored on the plugin entry (plugin always implements both hooks). Roles only populate with `include_user_info` + an authenticated user. Pin the OPA image version. `to_number()` assumes amount may be a string; drop it if your tool always sends a JSON number.

---

## 6. IBM Bob `mcp.json` schema

**RESOLVED (M0 Q1):** Config at `~/.bob/mcp_settings.json` (global, also written `<USER_HOME>/.bob/mcp_settings.json`) or `.bob/mcp.json` (project root, **takes precedence**). Top-level key **`mcpServers`** (object of named server configs). **BobShell uses the SAME paths + SAME `mcpServers` schema + SAME property set** as the Bob IDE.

**The `httpURL`-vs-`type/url` conflict resolves by source:** the property table lists `httpURL` = "HTTP endpoint URL for streamable http" and `url` = "SSE endpoint URL for remote servers"; the standalone transports page shows streamable-HTTP via `type:"streamable-http"` + `url`. **Both notations coexist in the live docs.**

### Property reference (confirmed) — resolves `httpURL` vs `url` vs `type`
Source: https://bob.ibm.com/docs/shell/configuration/mcp/mcp-bobshell
```
// Required (choose one):
// command : "Path to the executable for Stdio transport"
// url     : "SSE endpoint URL for remote servers"
// httpURL : "HTTP endpoint URL for streamable http"
//
// Optional:
// args       : "Command-line arguments for Stdio transport"
// headers    : "Custom HTTP headers for SSE transport"
// env        : "Environment variables for the server process"
// cwd        : "Working directory for Stdio transport"
// timeout    : "Request timeout in milliseconds (default: 600,000ms; 10min)"
// alwaysAllow: "Tool names to approve automatically"
// disabled   : "Set to `true` to disable the server"
```

### Streamable-HTTP server entry (confirmed, verbatim)
Source: https://bob.ibm.com/docs/ide/configuration/mcp/server-transports
```json
{
  "mcpServers": {
    "StreamableHTTPMCPName": {
      "type": "streamable-http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

### Remote server with Bearer auth + alwaysAllow (confirmed, verbatim — the ONLY verbatim Bearer example; SSE-style `url`+`headers`)
Source: https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob
```json
{
  "mcpServers": {
    "remote-server": {
      "url": "https://your-server-url.com/mcp",
      "headers": {
        "Authorization": "Bearer your-token"
      },
      "alwaysAllow": ["tool3"],
      "disabled": false
    }
  }
}
```

### Best-known streamable-HTTP + Bearer entry for the demo (SYNTHESIZED — `likely`, verify live)
Source: mcp-bobshell (`httpURL` property) + mcp-in-bob (headers/alwaysAllow example)
```json
{
  "mcpServers": {
    "my-remote-server": {
      "httpURL": "https://your-server-url.com/mcp",
      "headers": {
        "Authorization": "Bearer your-token"
      },
      "alwaysAllow": ["tool1", "tool2"],
      "disabled": false
    }
  }
}
```

### Alternative streamable-HTTP + Bearer using `type`/`url` (SYNTHESIZED — `likely`, verify live)
Source: server-transports (type/url) + mcp-in-bob (headers)
```json
{
  "mcpServers": {
    "my-remote-server": {
      "type": "streamable-http",
      "url": "https://your-server-url.com/mcp",
      "headers": {
        "Authorization": "Bearer your-token"
      },
      "alwaysAllow": ["tool1", "tool2"]
    }
  }
}
```

### Other facts
- Transport guidance (verbatim): "Use SSE transport for remote servers accessed over HTTP/HTTPS. For new remote servers, use Streamable HTTP transport instead."
- Streamable HTTP (verbatim): "the modern standard for remote MCP server communication, replacing the older HTTP+SSE transport… Uses a single URL path for all MCP communication."
- `timeout` default 600000ms (10min). IDE network timeout also adjustable via UI (30s–5min, default 1min).
- Install: standalone desktop app, OS-specific installers — macOS (.pkg ARM/Intel), Windows (.exe), Linux (Debian + Red Hat/Fedora). **IBMid required** to authenticate ("An IBMid is required to authenticate."). 30-day free trial (bob.ibm.com/trial), 40 Bobcoins.

**Uncertainties (need a live instance):** (1) whether `headers`/Bearer attaches to an `httpURL` entry — docs describe `headers` as "for SSE transport" and the only verbatim Bearer example uses `url`+`headers`; (2) which of `httpURL` vs `type:"streamable-http"`+`url` the installed build parses (may be aliases or one deprecated); (3) field-level merge vs override when both config files define the same server; (4) whether `alwaysAllow` accepts `["*"]` wildcard; (5) IBM Think tutorial (ibm.com/think/tutorials/mcp-integration-ibm-bob) returned HTTP 403 — may hold another concrete `httpURL` example; (6) credit-card requirement for trial asserted by secondary sources only.

### Source URLs (Bob)
- https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob
- https://bob.ibm.com/docs/shell/configuration/mcp/mcp-bobshell
- https://bob.ibm.com/docs/ide/configuration/mcp/server-transports
