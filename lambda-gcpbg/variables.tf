variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "eu-west-1"
}

variable "gcp_project_id" {
  description = "Your GCP Project ID."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region for the Cloud Function."
  type        = string
  default     = "us-central1"
}

variable "app_name_prefix" {
  description = "A unique prefix for resource names."
  type        = string
  default     = "multicloud"
}

variable "cognito_lambda_identity_id" {
  description = "The Cognito Developer Identity ID provided to the Lambda function."
  type        = string
  default     =  "eu-west-1:293c25a4-f059-c3b2-140d-81253fa0c26e"
}