pub mod auth;
pub mod db;
pub mod error;
pub mod finance;
pub mod models;
pub mod money;
pub mod security;

use axum::{
    Json, Router,
    body::{Body, to_bytes},
    extract::{DefaultBodyLimit, Request, State},
    http::{HeaderValue, Method, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{delete, get, post},
};
use error::{ApiError, ApiResult};
use redis::aio::ConnectionManager;
use serde_json::json;
use sqlx::PgPool;
use tower_http::{cors::CorsLayer, limit::RequestBodyLimitLayer, timeout::TimeoutLayer};
use utoipa::{
    Modify, OpenApi,
    openapi::{
        OpenApi as OpenApiDocument,
        security::{Http, HttpAuthScheme, SecurityScheme},
    },
};
use uuid::Uuid;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub cache: ConnectionManager,
}

/// Bound the complete operation including any reconnect wait, not just socket reads.
pub async fn cache_operation<T>(
    future: impl std::future::Future<Output = redis::RedisResult<T>>,
) -> ApiResult<T> {
    tokio::time::timeout(std::time::Duration::from_millis(750), future)
        .await
        .map_err(|_| ApiError::unavailable())?
        .map_err(Into::into)
}

pub fn router(state: AppState, origins: Vec<HeaderValue>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(origins)
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers([
            header::AUTHORIZATION,
            header::CONTENT_TYPE,
            header::HeaderName::from_static("idempotency-key"),
        ])
        .expose_headers([header::HeaderName::from_static("x-request-id")]);
    Router::new()
        .route("/health/live", get(live))
        .route("/health/ready", get(ready))
        .route("/openapi.json", get(openapi))
        .route("/api/v1/accounts", post(auth::register))
        .route("/api/v1/auth/challenges", post(auth::challenge))
        .route("/api/v1/auth/sessions", post(auth::session))
        .route("/api/v1/auth/session", delete(auth::logout))
        .route(
            "/api/v1/profile",
            get(auth::profile).put(auth::update_profile),
        )
        .route(
            "/api/v1/wallets",
            get(finance::wallets).post(finance::create_wallet),
        )
        .route(
            "/api/v1/transactions",
            get(finance::transactions).post(finance::create_transaction),
        )
        .route("/api/v1/summary", get(finance::summary))
        .fallback(|| async { ApiError::not_found() })
        .layer(DefaultBodyLimit::max(16 * 1024))
        .layer(RequestBodyLimitLayer::new(16 * 1024))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            std::time::Duration::from_secs(15),
        ))
        .layer(cors)
        .layer(middleware::from_fn(response_metadata))
        .with_state(state)
}

async fn response_metadata(request: Request, next: Next) -> Response {
    let request_id = Uuid::new_v4();
    let started = std::time::Instant::now();
    let mut response = next.run(request).await;
    // Axum extractor failures must use the same bounded RFC 9457 problem shape.
    if response.status().is_client_error() || response.status().is_server_error() {
        let original_status = response.status();
        let status = if original_status == StatusCode::UNPROCESSABLE_ENTITY {
            StatusCode::BAD_REQUEST
        } else {
            original_status
        };
        let (mut parts, body) = response.into_parts();
        let parsed = match to_bytes(body, 16 * 1024).await {
            Ok(bytes) => serde_json::from_slice::<serde_json::Value>(&bytes).ok(),
            Err(_) => None,
        };
        let code = parsed
            .as_ref()
            .and_then(|v| v.get("code"))
            .and_then(|v| v.as_str())
            .unwrap_or(match status.as_u16() {
                400 => "INVALID_REQUEST",
                401 => "UNAUTHORIZED",
                404 => "NOT_FOUND",
                405 => "METHOD_NOT_ALLOWED",
                408 => "REQUEST_TIMEOUT",
                413 => "BODY_TOO_LARGE",
                415 => "UNSUPPORTED_MEDIA_TYPE",
                _ => "REQUEST_FAILED",
            });
        let payload = json!({"status":status.as_u16(),"title":status.canonical_reason().unwrap_or("Request failed"),"code":code,"request_id":request_id});
        parts.status = status;
        parts.headers.remove(header::CONTENT_LENGTH);
        parts.headers.insert(
            header::CONTENT_TYPE,
            HeaderValue::from_static("application/problem+json"),
        );
        response = Response::from_parts(parts, Body::from(payload.to_string()));
    }
    response.headers_mut().insert(
        "x-request-id",
        HeaderValue::from_str(&request_id.to_string()).expect("UUID is ASCII"),
    );
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response.headers_mut().insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    tracing::info!(%request_id,status=response.status().as_u16(),elapsed_ms=started.elapsed().as_millis(),"request completed");
    response
}

#[utoipa::path(get,path="/health/live",responses((status=200,description="Process is alive")))]
async fn live() -> Json<serde_json::Value> {
    Json(json!({"status":"alive"}))
}
#[utoipa::path(get,path="/health/ready",responses((status=200,description="PostgreSQL schema and cache available"),(status=503,body=models::Problem)))]
async fn ready(State(state): State<AppState>) -> ApiResult<Json<serde_json::Value>> {
    let version: Option<i32> =
        sqlx::query_scalar("SELECT version FROM palmy.schema_metadata WHERE version=1")
            .fetch_optional(&state.db)
            .await
            .map_err(|_| ApiError::unavailable())?;
    if version != Some(1) {
        return Err(ApiError::unavailable());
    }
    let _: String =
        cache_operation(redis::cmd("PING").query_async(&mut state.cache.clone())).await?;
    Ok(Json(json!({"status":"ready"})))
}
#[utoipa::path(get,path="/openapi.json",responses((status=200,description="Implemented OpenAPI 3.1 contract")))]
async fn openapi() -> impl IntoResponse {
    Json(api_document())
}

struct BearerSecurity;
impl Modify for BearerSecurity {
    fn modify(&self, openapi: &mut OpenApiDocument) {
        if let Some(components) = openapi.components.as_mut() {
            components.add_security_scheme(
                "bearer",
                SecurityScheme::Http(Http::new(HttpAuthScheme::Bearer)),
            );
        }
    }
}
#[derive(OpenApi)]
#[openapi(info(title="Palmy API",version="0.1.0",description="Implemented pseudonymous identity and exact finance API. Only encrypted profile envelopes are stored; readable finance can still disclose identity through its content. See docs/protocol.md."),paths(auth::register,auth::challenge,auth::session,auth::logout,auth::profile,auth::update_profile,finance::wallets,finance::create_wallet,finance::transactions,finance::create_transaction,finance::summary,live,ready,openapi),modifiers(&BearerSecurity))]
struct ApiDocument;
pub fn api_document() -> OpenApiDocument {
    use utoipa::openapi::{Content, Ref, RefOr, response::ResponseBuilder};
    let mut document = ApiDocument::openapi();
    for path in document.paths.paths.values_mut() {
        for operation in [
            &mut path.get,
            &mut path.post,
            &mut path.put,
            &mut path.delete,
        ]
        .into_iter()
        .flatten()
        {
            for (status, response) in &mut operation.responses.responses {
                if status.parse::<u16>().is_ok_and(|value| value >= 400)
                    && let RefOr::T(response) = response
                    && let Some(content) = response.content.shift_remove("application/json")
                {
                    response
                        .content
                        .insert("application/problem+json".into(), content);
                }
            }
            operation.responses.responses.insert("default".into(), ResponseBuilder::new()
                .description("Protocol or dependency failure. All failures use RFC 9457 problem JSON with a server-generated request ID.")
                .content("application/problem+json", Content::new(Some(Ref::from_schema_name("Problem"))))
                .build().into());
        }
    }
    document
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn contract_is_current_and_protected_routes_require_bearer() {
        let spec = serde_json::to_value(api_document()).unwrap();
        assert_eq!(spec["openapi"], "3.1.0");
        assert_eq!(
            spec["paths"]["/api/v1/profile"]["get"]["security"][0]["bearer"],
            json!([])
        );
        assert!(
            spec["paths"]["/api/v1/accounts"]["post"]
                .get("security")
                .is_none()
        );
        assert_eq!(
            spec["components"]["schemas"]["RegisterRequest"]["additionalProperties"],
            false
        );
        assert!(
            spec["paths"]["/api/v1/profile"]["get"]["responses"]["401"]["content"]
                .get("application/problem+json")
                .is_some()
        );
        assert!(
            spec["paths"]["/health/live"]["get"]["responses"]["default"]["content"]
                .get("application/problem+json")
                .is_some()
        );
    }
    #[test]
    fn shared_crypto_vectors_verify_in_rust() {
        let vectors: serde_json::Value =
            serde_json::from_str(include_str!("../../contracts/crypto-vectors.json")).unwrap();
        // The fixture's structure is asserted here so drift cannot silently skip interoperability.
        let public = vectors["public_key"].as_str().unwrap();
        let key =
            security::decode(public, 32).unwrap_or_else(|_| panic!("invalid fixture public key"));
        for label in ["registration", "authentication"] {
            assert!(
                security::verify(
                    &key,
                    vectors[format!("{label}_signature")].as_str().unwrap(),
                    vectors[format!("{label}_message")].as_str().unwrap()
                )
                .is_ok()
            );
        }
    }

    #[tokio::test]
    async fn malformed_requests_are_sanitized_and_correlated() {
        use tower::ServiceExt;
        let app = Router::new()
            .route(
                "/test",
                post(|Json(_): Json<models::CreateWallet>| async { StatusCode::CREATED }),
            )
            .layer(RequestBodyLimitLayer::new(16 * 1024))
            .layer(middleware::from_fn(response_metadata));
        for (body, expected) in [
            (
                r#"{"name":"test","email":"never-echo@example.invalid"}"#.to_owned(),
                StatusCode::BAD_REQUEST,
            ),
            ("x".repeat(16 * 1024 + 1), StatusCode::PAYLOAD_TOO_LARGE),
        ] {
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/test")
                        .header(header::CONTENT_TYPE, "application/json")
                        .body(Body::from(body))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(response.status(), expected);
            assert_eq!(
                response.headers()[header::CONTENT_TYPE],
                "application/problem+json"
            );
            assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
            let request_id = response.headers()["x-request-id"]
                .to_str()
                .unwrap()
                .to_owned();
            let bytes = to_bytes(response.into_body(), 16 * 1024).await.unwrap();
            let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(value["request_id"], request_id);
            assert!(!String::from_utf8_lossy(&bytes).contains("never-echo"));
        }
    }

    #[tokio::test]
    async fn cache_reconnection_cannot_hold_requests_indefinitely() {
        let result = cache_operation(std::future::pending::<redis::RedisResult<()>>()).await;
        assert!(matches!(
            result,
            Err(ApiError {
                status: StatusCode::SERVICE_UNAVAILABLE,
                ..
            })
        ));
    }
}
