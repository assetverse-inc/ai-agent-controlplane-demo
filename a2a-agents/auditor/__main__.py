"""Entrypoint for the Auditor A2A agent.

Serves the agent card at /.well-known/agent-card.json and a JSON-RPC endpoint
at '/', bound to 0.0.0.0:9001.
"""

import uvicorn

from starlette.applications import Starlette

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill

from agent_executor import AuditorAgentExecutor


HOST = '0.0.0.0'
PORT = 9001


def build_agent_card() -> AgentCard:
    skill = AgentSkill(
        id='audit_expense',
        name='audit_expense',
        description=(
            'Audits an expense approval request and, when approved, submits a '
            'payment to the control-plane gateway for policy enforcement.'
        ),
        tags=['audit', 'expense', 'payments'],
        examples=[
            'Approve and pay $50,000 to Acme LLC',
            'Audit this expense of 1200 for Globex Inc',
        ],
        input_modes=['text/plain'],
        output_modes=['text/plain'],
    )

    return AgentCard(
        name='Auditor Agent',
        description=(
            'Audits expense approvals and requests payments via the control-plane '
            'gateway.'
        ),
        version='0.1.0',
        default_input_modes=['text/plain'],
        default_output_modes=['text/plain'],
        capabilities=AgentCapabilities(streaming=True),
        supported_interfaces=[
            AgentInterface(
                protocol_binding='JSONRPC',
                url=f'http://{HOST}:{PORT}',
            )
        ],
        skills=[skill],
    )


def build_app() -> Starlette:
    public_agent_card = build_agent_card()

    request_handler = DefaultRequestHandler(
        agent_executor=AuditorAgentExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=public_agent_card,
    )

    routes = []
    routes.extend(create_agent_card_routes(public_agent_card))
    routes.extend(create_jsonrpc_routes(request_handler, '/'))

    return Starlette(routes=routes)


def main() -> None:
    uvicorn.run(build_app(), host=HOST, port=PORT)


if __name__ == '__main__':
    main()
