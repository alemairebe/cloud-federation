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
  sku_name            = "B1" # Consumption Plan
}

# Zip the Azure function code
data "archive_file" "azure_func_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/azure_function"
  output_path = "${path.module}/dist/azure_function.zip"
}



# REPLACED: Updated for azuread v3.x
# resource "azuread_application" "api_app" {
#   display_name = "${var.app_name_prefix}-api-function"

#   # NEW: Explicitly expose the API and define a permission scope
#   api {
#     oauth2_permission_scope {
#       admin_consent_description = "Allow the application to access the user data API."
#       admin_consent_display_name  = "Access User Data API"
#       enabled                     = true
#       id                          = random_uuid.api_scope_id.result
#       type                        = "User"
#       value                       = "data.read"
#     }
#   }
# }

# resource "random_uuid" "api_scope_id" {}

# resource "azuread_service_principal" "api_sp" {
#   client_id = azuread_application.api_app.client_id
# }

# # --- 2. DEFINE THE CLIENT (AWS LAMBDA) ---

# # REPLACED: Updated for azuread v3.x
# resource "azuread_application" "client_app" {
#   display_name = "${var.app_name_prefix}-lambda-client"

#   required_resource_access {
#     resource_app_id = azuread_application.api_app.id

#     resource_access {
#       # UPDATED: Reference the ID of the new scope we defined above
#       id   = random_uuid.api_scope_id.result
#       type = "Scope"
#     }
#   }
# }

# resource "azuread_application_federated_identity_credential" "main" {
#   application_id = azuread_application.client_app.id
#   display_name          = "cognito-identity-pool-federation"
#   audiences             = [aws_cognito_identity_pool.main.id]
#   issuer                = "https://cognito-identity.${var.aws_region}.amazonaws.com"
#   subject               = var.cognito_lambda_identity_id
# }

# --- 3. CONFIGURE THE AZURE FUNCTION APP ---

# REPLACED: Updated for azurerm v4.x
resource "azurerm_linux_function_app" "main" {
  name                = "${var.app_name_prefix}-func-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  service_plan_id     = azurerm_service_plan.main.id  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }
  site_config {
    application_stack { node_version = "22" }
  }
  # Configure authentication to accept tokens for our Managed Identity
  auth_settings_v2 {
    auth_enabled         = true
    unauthenticated_action = "Return401"

    login {
      token_store_enabled = false
    }
    active_directory_v2 {
      client_id = azuread_application.lambda_app.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
    }
    # custom_oidc_v2 {
    #   name                = "CognitoIdentityPool"
    #   client_id          = aws_cognito_identity_pool.main.id
    #   openid_configuration_endpoint = "https://cognito-identity.amazonaws.com/.well-known/openid-configuration"
    # }
  }


  zip_deploy_file = data.archive_file.azure_func_zip.output_path
}


# resource "azurerm_linux_function_app" "main" {
#   name                = "${var.app_name_prefix}-func-${random_string.suffix.result}"
#   resource_group_name = azurerm_resource_group.main.name
#   location            = azurerm_resource_group.main.location

#   storage_account_name       = azurerm_storage_account.main.name
#   storage_account_access_key = azurerm_storage_account.main.primary_access_key
#   service_plan_id            = azurerm_service_plan.main.id

#   site_config {
#     application_stack {
#       node_version = "18"
#     }
#   }
#   zip_deploy_file = data.archive_file.azure_func_zip.output_path
# }


# # App Registration for our API (the Azure Function)
# resource "azuread_application" "api_app" {
#   display_name     = "${var.app_name_prefix}-api-function"
#   identifier_uris = ["api://${var.app_name_prefix}-api"]
# }

# # Service Principal for our API (the instance in the tenant)
# resource "azuread_service_principal" "api_sp" {
#   application_id = azuread_application.api_app.application_id
# }

# # THE FEDERATED TRUST RELATIONSHIP WITH COGNITO
# resource "azuread_application_federated_identity_credential" "main" {
#   application_id = azuread_application.main.id
#   display_name          = "cognito-identity-pool-federation"
#   description           = "Trusts tokens issued by the AWS Cognito Identity Pool"
#   audiences             = [aws_cognito_identity_pool.main.id]
  
#   # The issuer is now the regional Cognito Identity service
#   issuer                = "https://cognito-identity.amazonaws.com"

#   # Cognito Identity ID ('{region}:{guid}') that Azure AD sees in the token.
#   subject               = "eu-west-1:293c25a4-f059-c3b2-140d-81253fa0c26e"
# }










resource "azuread_application" "lambda_app" {
  display_name = "${var.app_name_prefix}-lambda-app"
    api {
    requested_access_token_version = 2
    oauth2_permission_scope {
      admin_consent_description  = "Allow access to the Azure Function"
      admin_consent_display_name = "Access Azure Function"
      enabled                    = true
      id                         = "00000000-0000-0000-0000-000000000001" # or use random_uuid
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
  issuer        = "https://cognito-identity.amazonaws.com"
  subject               = trimspace(data.local_file.cognito_identity_id.content)
}

















resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.main.location
  name                = "${var.app_name_prefix}-lambda-identity"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_federated_identity_credential" "this" {
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.this.id


  name          = "cognito-identity-pool-federation"
  audience             = [aws_cognito_identity_pool.main.id]
  issuer                = "https://cognito-identity.amazonaws.com"

  # Cognito Identity ID ('{region}:{guid}') that Azure AD sees in the token.
  subject               = trimspace(data.local_file.cognito_identity_id.content)
}

resource "azurerm_storage_container" "main" {
  name                  = "test-container"
  container_access_type = "blob"
  storage_account_id    = azurerm_storage_account.main.id
}

resource "azurerm_storage_blob" "main" {
  name                  = "azure_function.zip"
  storage_account_name  = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.main.name
  type = "Block"
  source = data.archive_file.azure_func_zip.output_path
}

resource "azurerm_role_assignment" "lambda_blob_reader" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}