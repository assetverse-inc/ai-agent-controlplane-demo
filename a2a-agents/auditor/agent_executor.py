"""Auditor agent executor.

Parses an expense approval request from the user message, then calls the
gateway tool `a2a_payments` over HTTP. Gateway errors / policy violations are
surfaced as a clean "BLOCKED by control plane" artifact instead of crashing.
"""

import os
import re

import httpx

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


GATEWAY_URL = os.environ.get('GATEWAY_URL', 'http://gateway:4444')
GATEWAY_TOKEN = os.environ.get('GATEWAY_TOKEN', '')


def parse_amount(text: str) -> float:
    """Extract the first dollar amount from text.

    Handles '$50,000', '50000', '50,000.50', etc. Returns 0.0 if none found.
    """
    # Match the first number, allowing an optional leading '$', thousands
    # separators and a decimal portion.
    match = re.search(r'\$?\s*(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)', text)
    if not match:
        return 0.0
    return float(match.group(1).replace(',', ''))


def parse_approval(text: str) -> bool:
    """Return True if the text indicates the expense is approved."""
    lowered = text.lower()
    return 'approv' in lowered  # matches 'approved', 'approval', 'approve'


def parse_payee(text: str) -> str:
    """Extract a payee from the text, defaulting to 'Acme LLC'."""
    # Look for a phrase like "to <Payee>" / "payee <Payee>" / "pay <Payee>".
    match = re.search(
        r'(?:payee|pay(?:ment)?(?:\s+to)?|to|for)\s+'
        r'([A-Z][A-Za-z0-9&.\'-]*(?:\s+[A-Z][A-Za-z0-9&.\'-]*)*'
        r'(?:\s+(?:LLC|Inc\.?|Corp\.?|Ltd\.?|Co\.?))?)',
        text,
    )
    if match:
        candidate = match.group(1).strip()
        if candidate:
            return candidate
    return 'Acme LLC'


class AuditorAgent:
    """Calls the gateway `a2a_payments` tool and reports the outcome."""

    async def audit(self, payee: str, amount: float, approval: bool) -> str:
        """Call the gateway tool over HTTP. Never raises; returns a message."""
        url = f'{GATEWAY_URL.rstrip("/")}/rpc'
        headers = {'Authorization': f'Bearer {GATEWAY_TOKEN}'}
        body = {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {
                'name': 'a2a_payments',
                'arguments': {
                    'payee': payee,
                    'amount': amount,
                    'approval': approval,
                },
            },
        }

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(url, json=body, headers=headers)
        except Exception as exc:  # noqa: BLE001 - any transport error -> BLOCKED
            return f'BLOCKED by control plane: {exc}'

        # Non-2xx status -> blocked by the control plane.
        if response.status_code < 200 or response.status_code >= 300:
            detail = _short(response.text) or f'HTTP {response.status_code}'
            return f'BLOCKED by control plane: {detail}'

        # Parse the JSON-RPC response body.
        try:
            data = response.json()
        except Exception:  # noqa: BLE001
            return f'Payment requested: {_short(response.text)}'

        # JSON-RPC level error.
        if isinstance(data, dict) and data.get('error'):
            return f'BLOCKED by control plane: {_short(str(data["error"]))}'

        result = data.get('result', data) if isinstance(data, dict) else data

        # Tool-level policy violation. MCP-style results may carry isError, or
        # the policy detail may appear in the textual content.
        if isinstance(result, dict):
            if result.get('isError') or result.get('is_error'):
                return f'BLOCKED by control plane: {_short(_extract_text(result))}'
            text = _extract_text(result)
            if text and _looks_like_violation(text):
                return f'BLOCKED by control plane: {_short(text)}'

        return f'Payment requested: {_short(str(result))}'


def _extract_text(result: dict) -> str:
    """Pull human-readable text out of an MCP tools/call result."""
    content = result.get('content')
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'text':
                parts.append(str(item.get('text', '')))
            elif isinstance(item, str):
                parts.append(item)
        if parts:
            return ' '.join(parts)
    return str(result)


def _looks_like_violation(text: str) -> bool:
    lowered = text.lower()
    return any(
        kw in lowered
        for kw in ('blocked', 'denied', 'policy', 'violation', 'not allowed', 'forbidden')
    )


def _short(text: str, limit: int = 500) -> str:
    text = (text or '').strip()
    return text if len(text) <= limit else text[:limit] + '...'


class AuditorAgentExecutor(AgentExecutor):
    """A2A executor for the Auditor agent."""

    def __init__(self) -> None:
        self.agent = AuditorAgent()

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        """Process an audit/approval request and call the gateway tool."""
        if context.current_task:
            task = context.current_task
        else:
            task = new_task_from_user_message(context.message)
            await event_queue.enqueue_event(task)

        task_updater = TaskUpdater(
            event_queue=event_queue, task_id=task.id, context_id=task.context_id
        )
        await task_updater.update_status(
            state=TaskState.TASK_STATE_WORKING,
            message=new_text_message('Auditing expense...'),
        )

        query = get_message_text(context.message) or ''
        amount = parse_amount(query)
        approval = parse_approval(query)
        payee = parse_payee(query)

        result = await self.agent.audit(payee=payee, amount=amount, approval=approval)
        print('Auditor result:', result)

        await task_updater.add_artifact(
            parts=[new_text_part(text=result, media_type='text/plain')]
        )
        await task_updater.update_status(
            state=TaskState.TASK_STATE_COMPLETED,
            message=new_text_message('Audit complete.'),
        )

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        """Cancel is not supported."""
        raise NotImplementedError('Cancel is not supported.')
