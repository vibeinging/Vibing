FROM rust:1.77-slim AS builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/vibe-relay /usr/local/bin/vibe-relay

EXPOSE 8766
VOLUME /data

CMD ["vibe-relay", "--bind", "0.0.0.0:8766", "--db", "/data/vibe-relay.db"]
