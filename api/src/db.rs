use crate::{
    error::{ApiError, ApiResult},
    security,
};
use axum::http::HeaderMap;
use sqlx::{PgPool, Postgres, Row, Transaction};
use uuid::Uuid;

pub struct Auth {
    pub owner: Uuid,
    pub token_hash: Vec<u8>,
}

pub async fn authenticate(pool: &PgPool, headers: &HeaderMap) -> ApiResult<Auth> {
    let token = headers
        .get("authorization")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .ok_or_else(ApiError::unauthorized)?;
    security::decode(token, 32).map_err(|_| ApiError::unauthorized())?;
    let token_hash = security::digest(token.as_bytes());
    let owner: Option<Uuid> = sqlx::query_scalar(
        "SELECT account_id FROM palmy.sessions WHERE token_hash = $1 AND expires_at > now()",
    )
    .bind(&token_hash)
    .fetch_optional(pool)
    .await?;
    Ok(Auth {
        owner: owner.ok_or_else(ApiError::unauthorized)?,
        token_hash,
    })
}

pub async fn owner_tx(pool: &PgPool, owner: Uuid) -> ApiResult<Transaction<'_, Postgres>> {
    let mut tx = pool.begin().await?;
    sqlx::query("SELECT set_config('palmy.account_id', $1, true)")
        .bind(owner.to_string())
        .execute(&mut *tx)
        .await?;
    Ok(tx)
}

pub async fn lock_owner(tx: &mut Transaction<'_, Postgres>, owner: Uuid) -> ApiResult<()> {
    sqlx::query("SELECT revision FROM palmy.ledger_state WHERE owner_id = $1 FOR UPDATE")
        .bind(owner)
        .fetch_one(&mut **tx)
        .await?;
    Ok(())
}

pub fn idempotency_key(headers: &HeaderMap) -> ApiResult<Uuid> {
    headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(|| ApiError::bad("IDEMPOTENCY_KEY_REQUIRED"))
}

pub async fn replay(
    tx: &mut Transaction<'_, Postgres>,
    owner: Uuid,
    route: &str,
    key: Uuid,
    hash: &[u8],
) -> ApiResult<Option<serde_json::Value>> {
    let row = sqlx::query("SELECT body_hash, response FROM palmy.idempotency WHERE owner_id=$1 AND route=$2 AND key=$3")
        .bind(owner).bind(route).bind(key).fetch_optional(&mut **tx).await?;
    match row {
        Some(row) if row.get::<Vec<u8>, _>("body_hash") == hash => Ok(Some(row.get("response"))),
        Some(_) => Err(ApiError::conflict("IDEMPOTENCY_CONFLICT")),
        None => Ok(None),
    }
}

pub async fn save_replay(
    tx: &mut Transaction<'_, Postgres>,
    owner: Uuid,
    route: &str,
    key: Uuid,
    hash: &[u8],
    response: &serde_json::Value,
) -> ApiResult<()> {
    sqlx::query("INSERT INTO palmy.idempotency(owner_id,route,key,body_hash,response) VALUES ($1,$2,$3,$4,$5)")
        .bind(owner).bind(route).bind(key).bind(hash).bind(response).execute(&mut **tx).await?;
    Ok(())
}

pub async fn verify_runtime_role(pool: &PgPool) -> ApiResult<()> {
    let unsafe_role: bool = sqlx::query_scalar("SELECT r.rolsuper OR r.rolbypassrls OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='palmy' AND c.relowner=r.oid) FROM pg_roles r WHERE r.rolname=current_user")
        .fetch_one(pool).await?;
    if unsafe_role {
        return Err(ApiError::internal());
    }
    Ok(())
}
