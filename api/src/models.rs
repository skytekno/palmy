use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Serialize, Deserialize, ToSchema, Clone, Debug)]
#[serde(deny_unknown_fields)]
pub struct ProfileEnvelope {
    #[schema(minimum = 1, maximum = 1)]
    pub version: u8,
    #[schema(pattern = "^A256GCM$")]
    pub algorithm: String,
    #[schema(pattern = "^[A-Za-z0-9_-]{16}$")]
    pub nonce: String,
    #[schema(min_length = 23, max_length = 10923, pattern = "^[A-Za-z0-9_-]+$")]
    pub ciphertext: String,
}
#[derive(Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct RegisterRequest {
    pub account_id: Uuid,
    #[schema(pattern = "^[A-Za-z0-9_-]{43}$")]
    pub public_key: String,
    pub profile: ProfileEnvelope,
    #[schema(pattern = "^[A-Za-z0-9_-]{86}$")]
    pub signature: String,
}
#[derive(Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct ChallengeRequest {
    pub account_id: Uuid,
}
#[derive(Serialize, ToSchema)]
pub struct Challenge {
    pub challenge_id: Uuid,
    pub nonce: String,
    pub expires_at: DateTime<Utc>,
}
#[derive(Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct SessionRequest {
    pub account_id: Uuid,
    pub challenge_id: Uuid,
    #[schema(pattern = "^[A-Za-z0-9_-]{86}$")]
    pub signature: String,
}
#[derive(Serialize, ToSchema)]
pub struct Session {
    pub access_token: String,
    pub expires_at: DateTime<Utc>,
}
#[derive(Serialize, ToSchema)]
pub struct Account {
    pub account_id: Uuid,
}
#[derive(Serialize, ToSchema)]
pub struct Profile {
    pub account_id: Uuid,
    pub profile: ProfileEnvelope,
    pub version: i64,
}
#[derive(Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct UpdateProfile {
    pub profile: ProfileEnvelope,
    #[schema(minimum = 1)]
    pub version: i64,
}
#[derive(Serialize, Deserialize, ToSchema, Clone)]
pub struct Wallet {
    pub id: Uuid,
    pub name: String,
    pub balance: String,
    pub currency: String,
}
#[derive(Deserialize, Serialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct CreateWallet {
    #[schema(min_length = 1, max_length = 80)]
    pub name: String,
}
#[derive(Serialize, Deserialize, ToSchema, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Income,
    Expense,
}
impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Income => "income",
            Self::Expense => "expense",
        }
    }
}
#[derive(Deserialize, Serialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct CreateTransaction {
    pub wallet_id: Uuid,
    pub kind: Kind,
    /// Positive exact decimal string, at most 16 integer and 2 fractional digits.
    #[schema(
        pattern = r"^(0|[1-9][0-9]{0,15})(\.[0-9]{1,2})?$",
        example = "1234.56"
    )]
    pub amount: String,
    #[schema(min_length = 1, max_length = 60)]
    pub category: String,
    #[schema(max_length = 280)]
    pub description: String,
    pub effective_on: NaiveDate,
}
#[derive(Serialize, Deserialize, ToSchema)]
pub struct Transaction {
    pub id: Uuid,
    pub wallet_id: Uuid,
    pub kind: Kind,
    pub amount: String,
    pub category: String,
    pub description: String,
    pub effective_on: NaiveDate,
    pub created_at: DateTime<Utc>,
}
#[derive(Serialize, Deserialize, ToSchema)]
pub struct Summary {
    pub balance: String,
    pub income: String,
    pub expense: String,
    pub currency: String,
}
#[derive(Serialize, ToSchema)]
pub struct Data<T> {
    pub data: T,
}
#[derive(Serialize, ToSchema)]
pub struct TransactionPage {
    pub data: Vec<Transaction>,
    pub next_cursor: Option<Uuid>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pagination {
    pub limit: Option<i64>,
    pub before: Option<Uuid>,
}
#[derive(Serialize, ToSchema)]
pub struct Problem {
    pub status: u16,
    pub title: String,
    pub code: String,
    pub request_id: Uuid,
}
