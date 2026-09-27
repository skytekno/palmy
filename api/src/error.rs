use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;

pub type ApiResult<T> = Result<T, ApiError>;
pub struct ApiError {
    pub status: StatusCode,
    pub code: &'static str,
}
impl ApiError {
    pub fn bad(code: &'static str) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            code,
        }
    }
    pub fn conflict(code: &'static str) -> Self {
        Self {
            status: StatusCode::CONFLICT,
            code,
        }
    }
    pub fn unauthorized() -> Self {
        Self {
            status: StatusCode::UNAUTHORIZED,
            code: "UNAUTHORIZED",
        }
    }
    pub fn internal() -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            code: "INTERNAL_ERROR",
        }
    }
    pub fn unavailable() -> Self {
        Self {
            status: StatusCode::SERVICE_UNAVAILABLE,
            code: "DEPENDENCY_UNAVAILABLE",
        }
    }
    pub fn not_found() -> Self {
        Self {
            status: StatusCode::NOT_FOUND,
            code: "NOT_FOUND",
        }
    }
}
impl From<sqlx::Error> for ApiError {
    fn from(_: sqlx::Error) -> Self {
        Self::internal()
    }
}
impl From<redis::RedisError> for ApiError {
    fn from(_: redis::RedisError) -> Self {
        Self::unavailable()
    }
}
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(json!({"status":self.status.as_u16(),"code":self.code,"title":self.status.canonical_reason().unwrap_or("Request failed")}))).into_response()
    }
}
