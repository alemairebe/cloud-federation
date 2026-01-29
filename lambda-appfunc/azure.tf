data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = "${var.app_name_prefix}-rg-${random_string.suffix.result}"
  location = "West Europe"
}

resource "azurerm_storage_account" "main" {
  name                     = "${var.app_name_prefix}sa${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled = true
}

resource "azurerm_service_plan" "main" {
  name                = "${var.app_name_prefix}-plan-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
}

data "archive_file" "azure_func_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/azure_function"
  output_path = "${path.module}/dist/azure_function.zip"
}

resource "azurerm_linux_function_app" "main" {
  name                = "${var.app_name_prefix}-func-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  site_config {
    application_stack { node_version = "22" }
  }
  auth_settings_v2 {
    auth_enabled           = true
    unauthenticated_action = "Return401"

    login {
      token_store_enabled = false
    }
    active_directory_v2 {
      client_id            = azuread_application.lambda_app.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
    }
  }
  zip_deploy_file = data.archive_file.azure_func_zip.output_path
}

resource "random_uuid" "federation_id" {}

resource "azuread_application" "lambda_app" {
  display_name = "${var.app_name_prefix}-lambda-app"
  api {
    requested_access_token_version = 2
    oauth2_permission_scope {
      admin_consent_description  = "Allow access to the Azure Function"
      admin_consent_display_name = "Access Azure Function"
      enabled                    = true
      id                         = random_uuid.federation_id.result
      type                       = "User"
      value                      = "user_impersonation"
    }
  }
}

resource "azuread_service_principal" "lambda_sp" {
  client_id = azuread_application.lambda_app.client_id
}

resource "azuread_application_federated_identity_credential" "lambda_federation" {
  application_id = azuread_application.lambda_app.id
  display_name   = "CognitoFederation"
  description    = "Trusts tokens from Cognito Identity Pool"
  audiences      = [aws_cognito_identity_pool.main.id]
  issuer         = "https://cognito-identity.amazonaws.com"
  subject        = trimspace(data.local_file.cognito_identity_id.content)
}

resource "azuread_application_federated_identity_credential" "aws_sts_federation" {
  application_id = azuread_application.lambda_app.id
  display_name   = "AWSFederation"
  description    = "Trusts tokens from AWS STS for outbound federation"
  audiences      = [local.audience]
  issuer         = aws_iam_outbound_web_identity_federation.this.issuer_identifier
  subject        = aws_iam_role.lambda_exec.arn
}
