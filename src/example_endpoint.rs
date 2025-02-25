use axum::extract::Query;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct HelloWorldQueryParams {
    pub name: Option<String>,
}

pub async fn hello_world(Query(params): Query<HelloWorldQueryParams>) -> String {
    let name = params.name.unwrap_or("World".to_string());
    format!("Hello {}, this is an AWS Lambda HTTP request", name)
}
