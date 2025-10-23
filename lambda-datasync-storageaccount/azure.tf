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

resource "azurerm_role_assignment" "lambda_blob_reader" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_storage_container" "main" {
  name                  = "test-container"
  container_access_type = "blob"
  storage_account_id    = azurerm_storage_account.main.id
}

resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.main.location
  name                = "${var.app_name_prefix}-id-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_federated_identity_credential" "this" {
  name                = "${var.app_name_prefix}-fed-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  audience            = [aws_cognito_identity_pool.main.id]
  issuer              = "https://cognito-identity.amazonaws.com"
  parent_id           = azurerm_user_assigned_identity.this.id
  subject             = trimspace(data.local_file.cognito_identity_id.content)
}