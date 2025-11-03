data "aws_caller_identity" "current" {}


locals {
  building_path        = "${path.module}/dist/aws_lambda"
  lambda_code_filename = "function.zip"
  lambda_src_path      = "${path.module}/src/aws_lambda"

  lambda_src_files = fileset(local.lambda_src_path, "**")
  lambda_src_hash = md5(join("", [
    for f in local.lambda_src_files : filemd5("${local.lambda_src_path}/${f}")
  ]))
}

resource "terraform_data" "build_lambda_function" {
  triggers_replace = {
    build_number = local.lambda_src_hash
  }

  provisioner "local-exec" {
    command = substr(pathexpand("~"), 0, 1) == "/" ? "./py_build.sh \"${local.lambda_src_path}\" \"${local.building_path}\" \"${local.lambda_code_filename}\" Function" : "powershell.exe -File .\\PyBuild.ps1 ${local.lambda_src_path} ${local.building_path} ${local.lambda_code_filename} Function"
  }
}


# 1. THE COGNITO IDENTITY POOL
# This service will mint OIDC tokens for our Lambda
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.app_name_prefix}-id-pool"
  allow_unauthenticated_identities = false # We don't need unauthenticated access

  # Configure our Lambda as a "Developer Identity Provider"
  developer_provider_name = "lambda.orchestrator"
}

resource "terraform_data" "cognito_identity_id" {
  triggers_replace = {
    build_number = aws_cognito_identity_pool.main.id
  }

  provisioner "local-exec" {
    command = "aws cognito-identity get-open-id-token-for-developer-identity --identity-pool-id ${aws_cognito_identity_pool.main.id} --logins ${aws_cognito_identity_pool.main.developer_provider_name}=${aws_lambda_function.orchestrator.arn} --query 'IdentityId' --output text --region ${var.aws_region} > ${path.module}/cognito_identity_id.txt"
  }
}

data "local_file" "cognito_identity_id" {
  filename = "${path.module}/cognito_identity_id.txt"
  depends_on = [ terraform_data.cognito_identity_id ]
}

# ephemeral "aws_cognito_identity_openid_token_for_developer_identity" "main" {
#   identity_pool_id = aws_cognito_identity_pool.main.id
#   logins = {
#     "lambda.orchestrator": aws_lambda_function.orchestrator.arn
#   }
# }
# resource "terraform_data" "cognito_token_invocation" {
#   triggers_replace = {
#     identity_pool_id = aws_cognito_identity_pool.main.id
#     lambda_arn     = aws_lambda_function.orchestrator.arn
#   }
#   input = ephemeral.aws_cognito_identity_openid_token_for_developer_identity.main.identity_id
# }
# 2. THE LAMBDA'S IAM ROLE
resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 3. IAM POLICY TO ALLOW LAMBDA TO USE COGNITO
resource "aws_iam_policy" "cognito_policy" {
  name        = "${var.app_name_prefix}-cognito-policy"
  description = "Allows Lambda to get a token from the Cognito Identity Pool"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action   = "cognito-identity:GetOpenIdTokenForDeveloperIdentity"
        Effect   = "Allow"
        Resource = aws_cognito_identity_pool.main.arn
      }
    ]
  })
}

# Attach Cognito and basic execution policies to the Lambda's role
resource "aws_iam_role_policy_attachment" "cognito_policy_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.cognito_policy.arn
}
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 4. THE LAMBDA FUNCTION ITSELF
resource "aws_lambda_function" "orchestrator" {
  depends_on = [ terraform_data.build_lambda_function ]
  function_name = "${var.app_name_prefix}-orchestrator"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.13"
  architectures = ["x86_64"]
  filename         = "${local.building_path}/${local.lambda_code_filename}"
  source_code_hash = local.lambda_src_hash
  timeout          = 30

  environment {
    variables = {
      AZURE_TENANT_ID    = data.azurerm_client_config.current.tenant_id
      AZURE_CLIENT_ID    = azuread_application.lambda_app.client_id
      AZURE_API_SCOPE    = "${azuread_application.lambda_app.client_id}/.default"
      # AZURE_API_SCOPE    = "${azuread_application.lambda_app.client_id}/user_impersonation"
      AZURE_FUNCTION_URL = "https://${azurerm_linux_function_app.main.default_hostname}/api/GetUserID"
      
      # Cognito and GCP variables remain the same
      COGNITO_IDENTITY_POOL_ID = aws_cognito_identity_pool.main.id
      COGNITO_DEV_PROVIDER_NAME = aws_cognito_identity_pool.main.developer_provider_name
      # GCP_FUNCTION_URL   = google_cloudfunctions2_function.main.url
    }
  }
}