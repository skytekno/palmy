FROM rust:1.98.1-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY api ./api
COPY contracts ./contracts
RUN cargo build --locked --release -p palmy-api --bin palmy-api

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --create-home palmy
COPY --from=build /src/target/release/palmy-api /usr/local/bin/palmy-api
USER 10001:10001
EXPOSE 8100
ENTRYPOINT ["palmy-api"]
CMD ["serve"]
