# syntax=docker/dockerfile:1

# ---- Builder stage ----
FROM rust:1.85-bookworm AS builder

WORKDIR /app

# Copy manifests and source, then build with the committed lockfile.
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release --locked

# ---- Runtime stage ----
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/payment-agent /usr/local/bin/payment-agent

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/payment-agent"]
