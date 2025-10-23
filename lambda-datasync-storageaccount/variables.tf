variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "eu-west-1"
}

variable "app_name_prefix" {
  description = "A unique prefix for resource names."
  type        = string
  default     = "datasync"
}
