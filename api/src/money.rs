//! Money crosses JSON as decimal strings and is never represented as a float.
pub fn parse_positive(value: &str) -> Option<i64> {
    let (whole, fraction) = value.split_once('.').unwrap_or((value, ""));
    if whole.is_empty()
        || whole.len() > 16
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || (whole.len() > 1 && whole.starts_with('0'))
        || fraction.len() > 2
        || (value.contains('.') && fraction.is_empty())
        || !fraction.bytes().all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let units = whole.parse::<i64>().ok()?.checked_mul(100)?;
    let cents = match fraction.len() {
        0 => 0,
        1 => fraction.parse::<i64>().ok()?.checked_mul(10)?,
        _ => fraction.parse().ok()?,
    };
    let amount = units.checked_add(cents)?;
    (amount > 0).then_some(amount)
}

pub fn format(minor: i64) -> String {
    let abs = minor.unsigned_abs();
    format!(
        "{}{}.{:02}",
        if minor < 0 { "-" } else { "" },
        abs / 100,
        abs % 100
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn keeps_fraction_and_range_exact() {
        for (input, expected) in [
            ("1234.56", 123456),
            ("0.01", 1),
            ("1", 100),
            ("1.2", 120),
            ("9999999999999999.99", 999999999999999999),
        ] {
            assert_eq!(parse_positive(input), Some(expected));
            assert_eq!(parse_positive(&format(expected)), Some(expected));
        }
        assert_eq!(format(-123456), "-1234.56");
    }
    #[test]
    fn rejects_rounding_and_non_money() {
        for input in [
            "0",
            "0.00",
            "-1",
            "+1",
            "01",
            "1.",
            ".1",
            "1.234",
            "1e2",
            "1,000",
            "NaN",
            " 1",
            "10000000000000000",
            "１",
        ] {
            assert_eq!(parse_positive(input), None, "accepted {input}");
        }
    }
}
