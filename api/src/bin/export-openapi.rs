fn main() {
    println!(
        "{}",
        serde_json::to_string_pretty(&palmy_api::api_document()).expect("OpenAPI serializes")
    );
}
