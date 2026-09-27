use crate::{
    error::{ApiError, ApiResult},
    models::ProfileEnvelope,
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256};

pub fn decode(value: &str, expected: usize) -> ApiResult<Vec<u8>> {
    let bytes = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| ApiError::bad("INVALID_ENCODING"))?;
    if bytes.len() != expected || URL_SAFE_NO_PAD.encode(&bytes) != value {
        return Err(ApiError::bad("INVALID_ENCODING"));
    }
    Ok(bytes)
}
pub fn random_token() -> ApiResult<String> {
    let mut bytes = [0; 32];
    getrandom::fill(&mut bytes).map_err(|_| ApiError::internal())?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}
pub fn digest(bytes: impl AsRef<[u8]>) -> Vec<u8> {
    Sha256::digest(bytes).to_vec()
}
pub fn validate_profile(profile: &ProfileEnvelope) -> ApiResult<()> {
    if profile.version != 1 || profile.algorithm != "A256GCM" {
        return Err(ApiError::bad("INVALID_PROFILE"));
    }
    decode(&profile.nonce, 12)?;
    let bytes = URL_SAFE_NO_PAD
        .decode(&profile.ciphertext)
        .map_err(|_| ApiError::bad("INVALID_PROFILE"))?;
    if !(17..=8192).contains(&bytes.len()) || URL_SAFE_NO_PAD.encode(bytes) != profile.ciphertext {
        return Err(ApiError::bad("INVALID_PROFILE"));
    }
    Ok(())
}
pub fn verify(public_key: &[u8], signature: &str, message: &str) -> ApiResult<()> {
    let key: &[u8; 32] = public_key
        .try_into()
        .map_err(|_| ApiError::unauthorized())?;
    let key = VerifyingKey::from_bytes(key).map_err(|_| ApiError::unauthorized())?;
    let sig = decode(signature, 64).map_err(|_| ApiError::unauthorized())?;
    let signature = Signature::from_slice(&sig).map_err(|_| ApiError::unauthorized())?;
    key.verify_strict(message.as_bytes(), &signature)
        .map_err(|_| ApiError::unauthorized())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    #[test]
    fn proof_is_bound_to_exact_context() {
        let key = SigningKey::from_bytes(&[17; 32]);
        let message = "palmy:auth:v1:account:challenge:nonce";
        let signature = URL_SAFE_NO_PAD.encode(key.sign(message.as_bytes()).to_bytes());
        assert!(verify(key.verifying_key().as_bytes(), &signature, message).is_ok());
        assert!(
            verify(
                key.verifying_key().as_bytes(),
                &signature,
                "palmy:auth:v1:other:challenge:nonce"
            )
            .is_err()
        );
        assert!(decode("AAAA=", 3).is_err());
    }
    #[test]
    fn rejects_unknown_envelope_fields() {
        let value = serde_json::json!({"version":1,"algorithm":"A256GCM","nonce":"a","ciphertext":"b","email":"plaintext"});
        assert!(serde_json::from_value::<ProfileEnvelope>(value).is_err());
    }
}
