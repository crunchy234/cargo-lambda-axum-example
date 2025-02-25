mod error;
mod example_endpoint;

use crate::example_endpoint::hello_world;
use axum::http::StatusCode;
use axum::routing::get;
use axum::Router;
use lambda_http::{run, tracing, Error};

async fn health_check() -> (StatusCode, String) {
    let health = true;
    match health {
        true => (StatusCode::OK, "Healthy!".to_string()),
        false => (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Not healthy!".to_string(),
        ),
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .json()
        .with_max_level(tracing::Level::TRACE)
        .with_current_span(false)
        .with_ansi(false)
        .without_time()
        .with_target(true)
        .init();

    let other_route = Router::new().route("/health", get(health_check));
    let hello_world = Router::new().route("/hello", get(hello_world));

    // Add support for cors later when needed
    // Also add HTST support in future
    let app = Router::new().merge(other_route).merge(hello_world);

    run(app).await
}
