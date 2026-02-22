terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.33.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "state"

  # Assume the IAM role mapped to the current workspace.
  # This allows different workspaces (Production, Staging) to provision
  # resources using separate roles with appropriate permissions.
  assume_role {
    role_arn     = var.workspace_iam_roles[terraform.workspace]
    session_name = "terraform-${terraform.workspace}"
  }

  default_tags {
    tags = merge(var.tags, {
      Workspace = terraform.workspace
    })
  }
}
