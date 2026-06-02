// Payments Agent — an A2A (Agent2Agent) agent that serves its agent card at
// `/.well-known/agent-card.json` and handles an A2A task to "execute a payment".
//
// Built on the official a2aproject/a2a-rs crates:
//   a2a        (package a2a-lf        0.3.0)
//   a2a-server (package a2a-server-lf 0.4.0)
//
// The executor is self-contained: it accepts the task, logs the instruction,
// and returns success. It makes no outbound calls.

use std::sync::Arc;

use a2a::event::StreamResponse;
use a2a::*;
use a2a_server::*;
use futures::stream::{self, BoxStream};

/// Business logic for the Payments agent.
struct PaymentExecutor;

impl AgentExecutor for PaymentExecutor {
    fn execute(
        &self,
        ctx: ExecutorContext,
    ) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        let message = ctx.message.clone();
        let task_id = ctx.task_id.clone();
        let context_id = ctx.context_id.clone();

        // Extract the payment instruction from the incoming message text.
        let instruction = match &message {
            Some(msg) => {
                let parts: Vec<String> = msg
                    .parts
                    .iter()
                    .filter_map(|p| match &p.content {
                        PartContent::Text(t) => Some(t.clone()),
                        _ => None,
                    })
                    .collect();
                if parts.is_empty() {
                    "(no instruction)".to_string()
                } else {
                    parts.join(", ")
                }
            }
            None => "(no instruction)".to_string(),
        };

        tracing::info!(task_id = %task_id, instruction = %instruction, "Executing payment");

        // Emit a Working status, then a Completed Task carrying an agent message.
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

        let response_text = format!("Payment executed: {instruction}");

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
                    parts: vec![Part::text(response_text)],
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
        let task_id = ctx.task_id.clone();
        let context_id = ctx.context_id.clone();

        Box::pin(stream::once(async {
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

/// Build the public agent card describing the Payments agent and its skill.
fn build_agent_card(interfaces: Vec<AgentInterface>) -> AgentCard {
    AgentCard {
        name: "Payments Agent".to_string(),
        description: "Executes payments on request and reports success.".to_string(),
        version: a2a::VERSION.to_string(),
        provider: Some(AgentProvider {
            organization: "A2A Payments Demo".to_string(),
            url: "https://github.com/a2aproject/a2a-rs".to_string(),
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
            description: "Executes a payment described by the instruction and returns success."
                .to_string(),
            tags: vec!["payments".to_string(), "finance".to_string()],
            examples: Some(vec!["Pay $50 to Acme Corp".to_string()]),
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
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

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
        .nest(
            "/jsonrpc",
            a2a_server::jsonrpc::jsonrpc_router(handler.clone()),
        )
        .nest("/rest", a2a_server::rest::rest_router(handler.clone()))
        .merge(a2a_server::agent_card::agent_card_router(card_producer));

    tracing::info!("Payments Agent starting");
    tracing::info!("Agent card:  http://localhost:3000/.well-known/agent-card.json");
    tracing::info!("JSON-RPC:    http://localhost:3000/jsonrpc");
    tracing::info!("REST:        http://localhost:3000/rest");

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .expect("failed to bind 0.0.0.0:3000");

    if let Err(e) = axum::serve(listener, app).await {
        tracing::error!(error = %e, "HTTP server exited");
    }
}
