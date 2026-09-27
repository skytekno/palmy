use palmy_api::{AppState, config, db, router};
use sqlx::postgres::PgPoolOptions;
use std::{env, time::Duration};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter("palmy_api=info")
        .with_target(false)
        .init();
    if run().await.is_err() {
        // Never print connection URLs, provider errors or credential-bearing config.
        tracing::error!(
            "API startup or migration failed; check configuration and dependency availability"
        );
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mode = env::args().nth(1).unwrap_or_else(|| "serve".into());
    if mode != "serve" && mode != "migrate" {
        return Err("expected serve or migrate".into());
    }
    // Validate delivery configuration before connecting to any dependencies.
    let origins = if mode == "serve" {
        config::cors_origins(
            env::var("PALMY_ENV").ok().as_deref(),
            env::var("CORS_ORIGINS").ok().as_deref(),
        )?
    } else {
        Vec::new()
    };
    let database_url = if mode == "migrate" {
        env::var("MIGRATION_DATABASE_URL").or_else(|_| env::var("DATABASE_URL"))?
    } else {
        env::var("DATABASE_URL")?
    };
    let pool = PgPoolOptions::new()
        .max_connections(20)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&database_url)
        .await?;
    if mode == "migrate" {
        sqlx::migrate!("./migrations").run(&pool).await?;
        tracing::info!("database migrations applied");
        return Ok(());
    }
    db::verify_runtime_role(&pool)
        .await
        .map_err(|_| "runtime role must not own tables, be superuser or bypass RLS")?;
    let cache_config = redis::aio::ConnectionManagerConfig::new()
        .set_response_timeout(Duration::from_millis(500))
        .set_connection_timeout(Duration::from_millis(500))
        .set_number_of_retries(1);
    let cache = tokio::time::timeout(
        Duration::from_secs(3),
        redis::Client::open(env::var("REDIS_URL")?)?
            .get_connection_manager_with_config(cache_config),
    )
    .await??;
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8100".into());
    let listener = tokio::net::TcpListener::bind(&bind).await?;
    tracing::info!("Palmy API listening");
    axum::serve(listener, router(AppState { db: pool, cache }, origins))
        .with_graceful_shutdown(shutdown())
        .await?;
    Ok(())
}
async fn shutdown() {
    #[cfg(unix)]
    {
        let mut terminate =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
                .expect("install SIGTERM handler");
        tokio::select! { _=tokio::signal::ctrl_c()=>{}, _=terminate.recv()=>{} }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
