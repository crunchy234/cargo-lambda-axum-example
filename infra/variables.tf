variable "region" {
  default = "ap-southeast-2"
}

variable "hosted_zone_index" {
  default = 0
}

variable "package_name" {
  //Note this must always match the name in Cargo.toml
  default = "cargo-lambda-axum-example"
}