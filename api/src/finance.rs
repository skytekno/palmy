use crate::{
    AppState, db,
    error::{ApiError, ApiResult},
    models::*,
    money, security,
};
use axum::{
    Json,
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
};
use chrono::Datelike;
use redis::AsyncCommands;
use serde_json::{Value, json};
use sqlx::Row;
use uuid::Uuid;

fn validate_text(value: &str, min: usize, max: usize) -> ApiResult<()> {
    if !(min..=max).contains(&value.chars().count()) || value.chars().any(char::is_control) {
        return Err(ApiError::bad("INVALID_TEXT"));
    }
    Ok(())
}

#[utoipa::path(get, path="/api/v1/wallets", security(("bearer"=[])), responses((status=200, body=Data<Vec<Wallet>>), (status=401, body=Problem)))]
pub async fn wallets(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Data<Vec<Wallet>>>> {
    let auth = db::authenticate(&state.db, &headers).await?;
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    let rows = sqlx::query("SELECT w.id,w.name,w.currency,coalesce(sum(e.amount),0.00)::text AS balance FROM palmy.wallets w LEFT JOIN palmy.entries e ON e.owner_id=w.owner_id AND e.wallet_id=w.id WHERE w.owner_id=$1 GROUP BY w.id ORDER BY w.created_at,w.id LIMIT 100")
        .bind(auth.owner).fetch_all(&mut *tx).await?;
    let data = rows
        .iter()
        .map(|row| Wallet {
            id: row.get("id"),
            name: row.get("name"),
            currency: row.get("currency"),
            balance: row.get("balance"),
        })
        .collect();
    tx.commit().await?;
    Ok(Json(Data { data }))
}

#[utoipa::path(post, path="/api/v1/wallets", request_body=CreateWallet, params(("Idempotency-Key"=Uuid, Header, description="Unique request UUID")), security(("bearer"=[])), responses((status=201, body=Data<Wallet>), (status=400, body=Problem), (status=409, body=Problem)))]
pub async fn create_wallet(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<CreateWallet>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    let auth = db::authenticate(&state.db, &headers).await?;
    let key = db::idempotency_key(&headers)?;
    validate_text(body.name.trim(), 1, 80)?;
    let hash = security::digest(serde_json::to_vec(&body).map_err(|_| ApiError::internal())?);
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    db::lock_owner(&mut tx, auth.owner).await?;
    if let Some(response) = db::replay(&mut tx, auth.owner, "wallets", key, &hash).await? {
        tx.commit().await?;
        return Ok((StatusCode::CREATED, Json(response)));
    }
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM palmy.wallets WHERE owner_id=$1")
        .bind(auth.owner)
        .fetch_one(&mut *tx)
        .await?;
    if count >= 100 {
        return Err(ApiError::conflict("WALLET_LIMIT"));
    }
    let wallet = Wallet {
        id: Uuid::new_v4(),
        name: body.name.trim().to_owned(),
        balance: "0.00".into(),
        currency: "IDR".into(),
    };
    sqlx::query("INSERT INTO palmy.wallets(id,owner_id,name) VALUES ($1,$2,$3)")
        .bind(wallet.id)
        .bind(auth.owner)
        .bind(&wallet.name)
        .execute(&mut *tx)
        .await?;
    let response = json!({"data":wallet});
    db::save_replay(&mut tx, auth.owner, "wallets", key, &hash, &response).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(response)))
}

fn transaction(row: &sqlx::postgres::PgRow) -> ApiResult<Transaction> {
    let kind = match row.get::<&str, _>("kind") {
        "income" => Kind::Income,
        "expense" => Kind::Expense,
        _ => return Err(ApiError::internal()),
    };
    Ok(Transaction {
        id: row.get("id"),
        wallet_id: row.get("wallet_id"),
        kind,
        amount: row.get("amount"),
        category: row.get("category"),
        description: row.get("description"),
        effective_on: row.get("effective_on"),
        created_at: row.get("created_at"),
    })
}

#[utoipa::path(post, path="/api/v1/transactions", request_body=CreateTransaction, params(("Idempotency-Key"=Uuid, Header, description="Unique request UUID")), security(("bearer"=[])), responses((status=201, body=Data<Transaction>), (status=400, body=Problem), (status=404, body=Problem), (status=409, body=Problem)))]
pub async fn create_transaction(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<CreateTransaction>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    let auth = db::authenticate(&state.db, &headers).await?;
    let key = db::idempotency_key(&headers)?;
    let amount =
        money::parse_positive(&body.amount).ok_or_else(|| ApiError::bad("INVALID_AMOUNT"))?;
    if !(1..=9999).contains(&body.effective_on.year()) {
        return Err(ApiError::bad("INVALID_DATE"));
    }
    validate_text(body.category.trim(), 1, 60)?;
    validate_text(&body.description, 0, 280)?;
    let hash = security::digest(serde_json::to_vec(&body).map_err(|_| ApiError::internal())?);
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    db::lock_owner(&mut tx, auth.owner).await?;
    if let Some(response) = db::replay(&mut tx, auth.owner, "transactions", key, &hash).await? {
        tx.commit().await?;
        return Ok((StatusCode::CREATED, Json(response)));
    }
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM palmy.wallets WHERE id=$1 AND owner_id=$2)",
    )
    .bind(body.wallet_id)
    .bind(auth.owner)
    .fetch_one(&mut *tx)
    .await?;
    if !exists {
        return Err(ApiError::not_found());
    }
    let id = Uuid::new_v4();
    let row = sqlx::query("INSERT INTO palmy.journals(id,owner_id,wallet_id,kind,amount,category,description,effective_on) VALUES ($1,$2,$3,$4,$5::text::numeric,$6,$7,$8) RETURNING id,wallet_id,kind,amount::text,category,description,effective_on,created_at")
        .bind(id).bind(auth.owner).bind(body.wallet_id).bind(body.kind.as_str()).bind(money::format(amount)).bind(body.category.trim()).bind(&body.description).bind(body.effective_on).fetch_one(&mut *tx).await?;
    let signed = match body.kind {
        Kind::Income => amount,
        Kind::Expense => -amount,
    };
    sqlx::query("INSERT INTO palmy.entries(id,owner_id,journal_id,wallet_id,account_kind,amount) VALUES ($1,$2,$3,$4,'wallet',$5::text::numeric),($6,$2,$3,NULL,'counterparty',$7::text::numeric)")
        .bind(Uuid::new_v4()).bind(auth.owner).bind(id).bind(body.wallet_id).bind(money::format(signed)).bind(Uuid::new_v4()).bind(money::format(-signed)).execute(&mut *tx).await?;
    sqlx::query("UPDATE palmy.ledger_state SET revision=revision+1 WHERE owner_id=$1")
        .bind(auth.owner)
        .execute(&mut *tx)
        .await?;
    let response = json!({"data":transaction(&row)?});
    db::save_replay(&mut tx, auth.owner, "transactions", key, &hash, &response).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(response)))
}

#[utoipa::path(get, path="/api/v1/transactions", params(("limit"=Option<i64>, Query, minimum=1, maximum=100), ("before"=Option<Uuid>, Query)), security(("bearer"=[])), responses((status=200, body=TransactionPage), (status=400, body=Problem), (status=401, body=Problem)))]
pub async fn transactions(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<Pagination>,
) -> ApiResult<Json<TransactionPage>> {
    let auth = db::authenticate(&state.db, &headers).await?;
    let limit = query.limit.unwrap_or(25);
    if !(1..=100).contains(&limit) {
        return Err(ApiError::bad("INVALID_LIMIT"));
    }
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    let before_time: Option<chrono::DateTime<chrono::Utc>> = match query.before {
        Some(id) => Some(
            sqlx::query_scalar("SELECT created_at FROM palmy.journals WHERE id=$1 AND owner_id=$2")
                .bind(id)
                .bind(auth.owner)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| ApiError::bad("INVALID_CURSOR"))?,
        ),
        None => None,
    };
    let rows = sqlx::query("SELECT id,wallet_id,kind,amount::text,category,description,effective_on,created_at FROM palmy.journals WHERE owner_id=$1 AND ($2::timestamptz IS NULL OR (created_at,id)<($2,$3)) ORDER BY created_at DESC,id DESC LIMIT $4")
        .bind(auth.owner).bind(before_time).bind(query.before).bind(limit+1).fetch_all(&mut *tx).await?;
    let mut data = rows
        .iter()
        .map(transaction)
        .collect::<ApiResult<Vec<_>>>()?;
    let next_cursor = if data.len() > limit as usize {
        data.truncate(limit as usize);
        data.last().map(|t| t.id)
    } else {
        None
    };
    tx.commit().await?;
    Ok(Json(TransactionPage { data, next_cursor }))
}

#[utoipa::path(get, path="/api/v1/summary", security(("bearer"=[])), responses((status=200, body=Data<Summary>), (status=401, body=Problem)))]
pub async fn summary(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Data<Summary>>> {
    let auth = db::authenticate(&state.db, &headers).await?;
    let mut tx = db::owner_tx(&state.db, auth.owner).await?;
    // A shared lock prevents a writer changing revision until the authoritative read finishes.
    let revision: i64 =
        sqlx::query_scalar("SELECT revision FROM palmy.ledger_state WHERE owner_id=$1 FOR SHARE")
            .bind(auth.owner)
            .fetch_one(&mut *tx)
            .await?;
    let key = format!("palmy:summary:v1:{}:{revision}", auth.owner);
    let mut cache = state.cache.clone();
    if let Ok(Some(value)) = crate::cache_operation(cache.get::<_, Option<String>>(&key)).await
        && let Ok(data) = serde_json::from_str::<Summary>(&value)
    {
        tx.commit().await?;
        return Ok(Json(Data { data }));
    }
    let row = sqlx::query("SELECT coalesce(sum(CASE WHEN kind='income' THEN amount ELSE -amount END),0.00)::text AS balance,coalesce(sum(amount) FILTER(WHERE kind='income'),0.00)::text AS income,coalesce(sum(amount) FILTER(WHERE kind='expense'),0.00)::text AS expense FROM palmy.journals WHERE owner_id=$1")
        .bind(auth.owner).fetch_one(&mut *tx).await?;
    let data = Summary {
        balance: row.get("balance"),
        income: row.get("income"),
        expense: row.get("expense"),
        currency: "IDR".into(),
    };
    tx.commit().await?;
    // A writer may now commit; this old revision key can never serve its newer revision.
    if let Ok(value) = serde_json::to_string(&data) {
        let _: ApiResult<()> = crate::cache_operation(cache.set_ex(key, value, 30)).await;
    }
    Ok(Json(Data { data }))
}
