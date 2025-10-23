terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.46"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.6"
    }
    # google = {
    #   source  = "hashicorp/google"
    #   version = "~> 7.4"
    # }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# provider "google" {
#   project = var.gcp_project_id
#   region  = var.gcp_region
# }