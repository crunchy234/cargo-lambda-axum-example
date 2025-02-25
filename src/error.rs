use axum::extract::rejection::StringRejection;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use serde::Deserialize;
use std::str::Utf8Error;
use thiserror::Error;
#[derive(Debug, Error, PartialEq, Eq, Clone, Deserialize)]
pub enum ServerError {
    #[error("Database error: {0}")]
    Database(String),
    #[error("Configuration error: {0}")]
    Configuration(String),
    #[error("Migration error: {0}")]
    Migration(String),
    #[error("Deserialize error: {0}")]
    DeserializeError(String),
    #[error("Request body error {0}")]
    RequestBodyError(String),
}

impl IntoResponse for ServerError {
    fn into_response(self) -> axum::response::Response {
        let (status, error_message) = match self {
            ServerError::Database(err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Database error: {err}"),
            ),
            ServerError::Configuration(err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Configuration error: {err}"),
            ),
            ServerError::Migration(err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Migration error: {err}"),
            ),
            ServerError::DeserializeError(err) => {
                (StatusCode::BAD_REQUEST, format!("Deserialize error: {err}"))
            }
            ServerError::RequestBodyError(err) => (
                StatusCode::BAD_REQUEST,
                format!("Request body error: {err}"),
            ),
        };
        (status, Json(error_message)).into_response()
    }
}

impl From<StringRejection> for ServerError {
    fn from(rejection: StringRejection) -> Self {
        ServerError::DeserializeError(rejection.to_string())
    }
}

impl From<Utf8Error> for ServerError {
    fn from(err: Utf8Error) -> Self {
        ServerError::RequestBodyError(err.to_string())
    }
}
