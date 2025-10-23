resource "aws_secretsmanager_secret" "azure_sas" {
  name                    = "datasync/azure-sas-token"
  description             = "SAS token for Azure Storage used by AWS DataSync"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "azure_sas_value" {
  secret_id     = aws_secretsmanager_secret.azure_sas.id
  secret_string = data.azurerm_storage_account_sas.this.sas
}

resource "awscc_datasync_location_s3" "s3_location" {
  s3_bucket_arn = aws_s3_bucket.destination_bucket.arn
  s3_config = {
    bucket_access_role_arn = aws_iam_role.ds_s3_access_role.arn
  }

}

resource "aws_s3_bucket" "destination_bucket" {
  force_destroy = true
  bucket        = "${var.app_name_prefix}-datasync-dest-bucket-${random_string.suffix.result}"
}

resource "aws_iam_role" "ds_s3_access_role" {
  name = "${var.app_name_prefix}-datasync-s3-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "datasync.amazonaws.com" }
    }]
  })

}
resource "aws_iam_policy" "ds-s3-access-policy" {
  name        = "${var.app_name_prefix}-datasync-s3-access-policy"
  description = "Allows DataSync to write to the S3 destination bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*Object",
          "s3:*Object*",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.destination_bucket.arn,
          "${aws_s3_bucket.destination_bucket.arn}/*"
        ]
      }
    ]
  })

}
resource "aws_iam_role_policy_attachment" "ds-s3-access-policy-attachment" {
  role       = aws_iam_role.ds_s3_access_role.name
  policy_arn = aws_iam_policy.ds-s3-access-policy.arn
}

resource "awscc_datasync_location_azure_blob" "azure_blob_location" {
  azure_blob_container_url = "https://${azurerm_storage_container.main.name}.blob.core.windows.net/${azurerm_storage_container.main.name}"
  custom_secret_config = {
    secret_access_role_arn = aws_iam_role.ds_secret_manager_role.arn
    secret_arn             = aws_secretsmanager_secret.azure_sas.arn
  }
}

resource "aws_iam_role" "ds_secret_manager_role" {
  name = "${var.app_name_prefix}-datasync-secretsmanager-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "datasync.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}
resource "aws_iam_policy" "ds_secret_manager_policy" {
  name        = "${var.app_name_prefix}-datasync-secretsmanager-policy"
  description = "Allows DataSync to read the Azure SAS token from Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.azure_sas.arn
      }
    ]
  })

}
resource "aws_iam_role_policy_attachment" "ds_secret_manager_policy_attachment" {
  role       = aws_iam_role.ds_secret_manager_role.name
  policy_arn = aws_iam_policy.ds_secret_manager_policy.arn
}
resource "time_rotating" "start" {
  rotation_days = 30
}

resource "time_offset" "end" {
  triggers = {
    start = time_rotating.start.id
  }
  offset_days = 90
}

data "azurerm_storage_account_sas" "this" {
  connection_string = azurerm_storage_account.main.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  start  = time_rotating.start.rfc3339
  expiry = time_offset.end.rfc3339

  resource_types {
    service   = true
    container = false
    object    = false
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = true
    delete  = false
    list    = true
    add     = true
    create  = true
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "aws_datasync_task" "enhanced_task" {
  source_location_arn      = awscc_datasync_location_azure_blob.azure_blob_location.location_arn
  destination_location_arn = awscc_datasync_location_s3.s3_location.location_arn
  name                     = "${var.app_name_prefix}-datasync-task"
  task_mode                = "ENHANCED"

  options {
    verify_mode       = "ONLY_FILES_TRANSFERRED"
    gid               = "NONE"
    posix_permissions = "NONE"
    uid               = "NONE"
    object_tags       = "NONE"
  }
  schedule {
    schedule_expression = "cron(0 12 1 1 ? 2123)" ## Test I don't want it to run automatically for now
  }
}