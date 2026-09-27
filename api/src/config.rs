use axum::http::HeaderValue;
use std::collections::HashSet;
use url::{Host, Url};

/// Browser origins are exact allowlist entries, never URLs, patterns, or reflected input.
/// Production is the default; local HTTP requires an explicit development environment.
pub fn cors_origins(
    environment: Option<&str>,
    configured: Option<&str>,
) -> Result<Vec<HeaderValue>, &'static str> {
    let development = match environment.unwrap_or("production") {
        "production" => false,
        "development" => true,
        _ => return Err("PALMY_ENV must be production or development"),
    };
    let configured = match configured {
        Some(value) => value,
        None if development => "http://localhost:3100,http://127.0.0.1:3100",
        None => return Err("production requires explicit CORS_ORIGINS"),
    };
    let mut seen = HashSet::new();
    let mut origins = Vec::new();
    for value in configured.split(',').map(str::trim) {
        let url = Url::parse(value).map_err(|_| "invalid CORS origin")?;
        if value.contains('*')
            || !matches!(url.scheme(), "http" | "https")
            || url.origin().ascii_serialization() != value
            || (!development && url.scheme() != "https")
        {
            return Err("CORS origins must be canonical HTTPS origins in production");
        }
        if development {
            let loopback = match url.host() {
                Some(Host::Domain(domain)) => domain == "localhost",
                Some(Host::Ipv4(address)) => address.is_loopback(),
                Some(Host::Ipv6(address)) => address.is_loopback(),
                None => false,
            };
            if !loopback {
                return Err("development CORS origins must be loopback");
            }
        }
        if !seen.insert(value) || origins.len() == 16 {
            return Err("CORS allowlist must contain at most 16 distinct origins");
        }
        origins.push(HeaderValue::from_str(value).map_err(|_| "invalid CORS origin")?);
    }
    Ok(origins)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn production_is_default_and_requires_explicit_https_origins() {
        assert!(cors_origins(None, None).is_err());
        assert!(cors_origins(Some("production"), Some("http://app.example")).is_err());
        let origins = cors_origins(None, Some("https://app.example, https://app.example:8443"))
            .expect("two explicitly permitted HTTPS origins");
        assert_eq!(origins.len(), 2);
        assert_eq!(origins[0], "https://app.example");
        assert_eq!(origins[1], "https://app.example:8443");
    }

    #[test]
    fn origins_reject_url_components_wildcards_and_noncanonical_forms() {
        for value in [
            "",
            "*",
            "null",
            "https://*.example",
            "https://app.example/",
            "https://app.example/path",
            "https://app.example?secret=value",
            "https://app.example#fragment",
            "https://owner@app.example",
            "https://owner:password@app.example",
            "https://APP.example",
            "https://app.example:443",
            "https://app.example\\path",
            "https://app.example\r\nX-Injected: value",
            "ftp://app.example",
            "https://app.example,",
            "https://app.example https://other.example",
        ] {
            assert!(
                cors_origins(None, Some(value)).is_err(),
                "invalid origin accepted"
            );
        }
    }

    #[test]
    fn development_only_allows_explicit_loopback_transport() {
        assert_eq!(cors_origins(Some("development"), None).unwrap().len(), 2);
        for value in [
            "http://localhost:3100",
            "http://127.0.0.1:3100",
            "http://[::1]:3100",
            "https://localhost:3443",
        ] {
            assert!(cors_origins(Some("development"), Some(value)).is_ok());
        }
        for value in [
            "http://localhost.example",
            "http://192.168.1.2",
            "https://app.example",
            "http://127.1",
        ] {
            assert!(cors_origins(Some("development"), Some(value)).is_err());
        }
    }

    #[test]
    fn invalid_modes_duplicates_and_unbounded_lists_fail_closed() {
        assert!(cors_origins(Some("prod"), Some("https://app.example")).is_err());
        assert!(cors_origins(Some(""), Some("https://app.example")).is_err());
        assert!(cors_origins(None, Some("https://app.example,https://app.example")).is_err());
        let origins = (0..17)
            .map(|i| format!("https://app{i}.example"))
            .collect::<Vec<_>>();
        assert!(cors_origins(None, Some(&origins[..16].join(","))).is_ok());
        assert!(cors_origins(None, Some(&origins.join(","))).is_err());
    }
}
