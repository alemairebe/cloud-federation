terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.60"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.46"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.6"
    }
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

provider "awscc" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}

provider "azuread" {}
