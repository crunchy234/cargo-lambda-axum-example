resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${terraform.workspace}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "null_resource" "build_lambda" {
  // Trigger on any change in ../src directory
  triggers = {
    src_directory_content_change = join("", [
      for file in fileset("../src", "**") :filebase64sha256("${path.module}/../src/${file}")
    ])
    cargo_lock_file_change = filebase64sha256("../Cargo.lock")
    cargo_toml_file_change = filebase64sha256("../Cargo.toml")
  }
  provisioner "local-exec" {
    command    = <<-EOT
        set -e
        pushd ${path.module}/..
        cargo lambda build --release --arm64 --output-format zip
        popd
      EOT
    on_failure = fail
  }
}

resource "aws_lambda_function" "cargo_lambda_function" {
  function_name = "auxm-example-function-${terraform.workspace}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler = "bootstrap" # This is the default handler for `cargo-lambda`
  runtime = "provided.al2023" # Lambda runtime for Rust
  timeout       = 10
  architectures = ["arm64"]

  filename = "${path.module}/../target/lambda/${var.package_name}/bootstrap.zip"
  # Adjust this as needed if your zip file has a different name
  source_code_hash = fileexists("${path.module}/tmp/git_tag.json") ? filebase64sha256("${path.module}/../target/lambda/${var.package_name}/bootstrap.zip") : "file-doesn't-exist"
  # Ensures deployment only when code changes
  depends_on = [null_resource.build_lambda]
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "cargo-lambda-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway_invoke_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cargo_lambda_function.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cargo_lambda_function.invoke_arn
  payload_format_version = "2.0"
  connection_type        = "INTERNET"
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_cognito_user_pool" "auth_user_pool" {
  name = "cargo-lambda-user-pool-${terraform.workspace}"
}

resource "aws_cognito_user_pool_client" "auth_client" {
  name            = "cargo-lambda-user-pool-client-${terraform.workspace}"
  user_pool_id    = aws_cognito_user_pool.auth_user_pool.id
  generate_secret = false
  allowed_oauth_flows = ["implicit"]
  allowed_oauth_scopes = ["openid"]
  callback_urls = ["https://example.com/callback"]
  logout_urls = ["https://example.com/logout"]

  allowed_oauth_flows_user_pool_client = true
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  name            = "cognito-authorizer-${terraform.workspace}"
  api_id          = aws_apigatewayv2_api.http_api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.auth_user_pool.id}"
    audience = [aws_cognito_user_pool_client.auth_client.id]
  }
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

// Options route can't be authed as browser never passes in auth credentials when calling options route
resource "aws_apigatewayv2_route" "options_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "OPTIONS /{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "NONE"
}

output "api_url" {
  value       = aws_apigatewayv2_stage.default_stage.invoke_url
  description = "URL to invoke the API Gateway"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.auth_user_pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.auth_client.id
}
