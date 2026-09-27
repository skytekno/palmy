use crate::{
    AppState, db,
    error::{ApiError, ApiResult},
    models::*,
    security,
};
use axum::{
    Json,
    extract::State,
    http::{HeaderMap, StatusCode},
};
use chrono::{Duration, Utc};
use sqlx::Row;
use uuid::Uuid;

async fn rate_limit(state: &AppState, account: Uuid, namespace: &str) -> ApiResult<()> {
    // Atomic, expiring counters; cache failure rejects issuance instead of bypassing limits.
    let script = redis::Script::new(
        "local g=redis.call('INCR',KEYS[1]); if g==1 then redis.call('EXPIRE',KEYS[1],60) end; local a=redis.call('INCR',KEYS[2]); if a==1 then redis.call('EXPIRE',KEYS[2],120) end; if g>600 or a>10 then return 0 else return 1 end",
    );
    let mut cache = state.cache.clone();
    let result: i32 = crate::cache_operation(
        script
            .key(format!("palmy:limit:{namespace}:global"))
            .key(format!("palmy:limit:{namespace}:{account}"))
            .invoke_async(&mut cache),
    )
    .await?;
    if result == 0 {
        return Err(ApiError {
            status: StatusCode::TOO_MANY_REQUESTS,
            code: "RATE_LIMITED",
        });
    }
    Ok(())
}

#[utoipa::path(post, path="/api/v1/accounts", request_body=RegisterRequest, responses((status=201, body=Data<Account>), (status=400, body=Problem), (status=401, body=Problem), (status=409, body=Problem), (status=429, body=Problem)))]
pub async fn register(
    State(state): State<AppState>,
    Json(body): Json<RegisterRequest>,
) -> ApiResult<(StatusCode, Json<Data<Account>>)> {
    if body.account_id.get_version_num() != 4 {
        return Err(ApiError::bad("INVALID_ACCOUNT_ID"));
    }
    security::validate_profile(&body.profile)?;
    let key = security::decode(&body.public_key, 32)?;
    let message = format!(
        "palmy:register:v1:{}:{}:{}:{}",
        body.account_id, body.public_key, body.profile.nonce, body.profile.ciphertext
    );
    security::verify(&key, &body.signature, &message)?;
    rate_limit(&state, body.account_id, "register").await?;
    let mut tx = db::owner_tx(&state.db, body.account_id).await?;
    let inserted = sqlx::query(
        "INSERT INTO palmy.accounts(id, public_key) VALUES ($1,$2) ON CONFLICT DO NOTHING",
    )
    .bind(body.account_id)
    .bind(key)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted != 1 {
        return Err(ApiError::conflict("ACCOUNT_EXISTS"));
    }
    sqlx::query("INSERT INTO palmy.profiles(owner_id,envelope) VALUES ($1,$2)")
        .bind(body.account_id)
        .bind(sqlx::types::Json(body.profile))
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO palmy.ledger_state(owner_id) VALUES ($1)")
        .bind(body.account_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok((
        StatusCode::CREATED,
        Json(Data {
            data: Account {
                account_id: body.account_id,
            },
        }),
    ))
}

#[utoipa::path(post, path="/api/v1/auth/challenges", request_body=ChallengeRequest, responses((status=200, body=Data<Challenge>), (status=429, body=Problem), (status=503, body=Problem)))]
pub async fn challenge(
    State(state): State<AppState>,
    Json(body): Json<ChallengeRequest>,
) -> ApiResult<Json<Data<Challenge>>> {
    rate_limit(&state, body.account_id, "challenge").await?;
    let response = Challenge {
        challenge_id: Uuid::new_v4(),
        nonce: security::random_token()?,
        expires_at: Utc::now() + Duration::seconds(120),
    };
    // Unknown account IDs follow exactly the same persistence and response path.
    sqlx::query(
        "INSERT INTO palmy.challenges(id,account_id,nonce,expires_at) VALUES ($1,$2,$3,$4)",
    )
    .bind(response.challenge_id)
    .bind(body.account_id)
    .bind(&response.nonce)
    .bind(response.expires_at)
    .execute(&state.db)
    .await?;
    sqlx::query("DELETE FROM palmy.challenges WHERE expires_at < now() - interval '1 day'")
        .execute(&state.db)
        .await?;
    Ok(Json(Data { data: response }))
}

#[utoipa::path(post, path="/api/v1/auth/sessions", request_body=SessionRequest, responses((status=200, body=Data<Session>), (status=401, body=Problem)))]
pub async fn session(
    State(state): State<AppState>,
    Json(body): Json<SessionRequest>,
) -> ApiResult<Json<Data<Session>>> {
    // Delete commits independently: even an invalid proof burns the one-use challenge.
    let row = sqlx::query(
        "DELETE FROM palmy.challenges WHERE id=$1 AND account_id=$2 RETURNING nonce, expires_at",
    )
    .bind(body.challenge_id)
    .bind(body.account_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(ApiError::unauthorized)?;
    if row.get::<chrono::DateTime<Utc>, _>("expires_at") <= Utc::now() {
        return Err(ApiError::unauthorized());
    }
    let nonce: String = row.get("nonce");
    let key: Option<Vec<u8>> =
        sqlx::query_scalar("SELECT public_key FROM palmy.accounts WHERE id=$1")
            .bind(body.account_id)
            .fetch_optional(&state.db)
            .await?;
    let message = format!(
        "palmy:auth:v1:{}:{}:{}",
        body.account_id, body.challenge_id, nonce
    );
    security::verify(
        &key.ok_or_else(ApiError::unauthorized)?,
        &body.signature,
        &message,
    )?;
    let response = Session {
        access_token: security::random_token()?,
        expires_at: Utc::now() + Duration::hours(1),
    };
    sqlx::query("INSERT INTO palmy.sessions(token_hash,account_id,expires_at) VALUES ($1,$2,$3)")
        .bind(security::digest(response.access_token.as_bytes()))
        .bind(body.account_id)
        .bind(response.expires_at)
        .execute(&state.db)
        .await?;
    sqlx::query("DELETE FROM palmy.sessions WHERE expires_at < now() - interval '1 day'")
        .execute(&state.db)
        .await?;
    Ok(Json(Data { data: response }))
}

#[utoipa::path(delete, path="/api/v1/auth/session", security(("bearer"=[])), responses((status=204), (status=401, body=Problem)))]
pub async fn logout(State(state): State<AppState>, headers: HeaderMap) -> ApiResult<StatusCode> {
    let auth = db::authenticate(&state.db, &headers).await?;
    sqlx::query("DELETE FROM palmy.sessions WHERE token_hash=$1")
        .bind(auth.token_hash)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(get, path="/api/v1/profile", security(("bearer"=[])), responses((status=200, body=Data<Profile>), (status=401, body=Problem)))]
pub async fn profile(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Data<Profile>>> {
    let auth = db::authenticate(&state.db, &headers).await?;
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    let row = sqlx::query("SELECT envelope, version FROM palmy.profiles WHERE owner_id=$1")
        .bind(auth.owner)
        .fetch_one(&mut *tx)
        .await?;
    let profile = row
        .get::<sqlx::types::Json<ProfileEnvelope>, _>("envelope")
        .0;
    tx.commit().await?;
    Ok(Json(Data {
        data: Profile {
            account_id: auth.owner,
            profile,
            version: row.get("version"),
        },
    }))
}

#[utoipa::path(put, path="/api/v1/profile", request_body=UpdateProfile, security(("bearer"=[])), responses((status=200, body=Data<Profile>), (status=401, body=Problem), (status=409, body=Problem)))]
pub async fn update_profile(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<UpdateProfile>,
) -> ApiResult<Json<Data<Profile>>> {
    let auth = db::authenticate(&state.db, &headers).await?;
    security::validate_profile(&body.profile)?;
    if body.version < 1 {
        return Err(ApiError::bad("INVALID_VERSION"));
    }
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    let version: Option<i64> = sqlx::query_scalar("UPDATE palmy.profiles SET envelope=$1,version=version+1 WHERE owner_id=$2 AND version=$3 RETURNING version")
        .bind(sqlx::types::Json(&body.profile)).bind(auth.owner).bind(body.version).fetch_optional(&mut *tx).await?;
    let version = version.ok_or_else(|| ApiError::conflict("VERSION_CONFLICT"))?;
    tx.commit().await?;
    Ok(Json(Data {
        data: Profile {
            account_id: auth.owner,
            profile: body.profile,
            version,
        },
    }))
}
