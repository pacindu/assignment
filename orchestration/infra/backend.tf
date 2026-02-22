terraform {
  backend "s3" {
    bucket         = "ntt-terraform-state-ap-southeast-1"
    key            = "orchestration/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    kms_key_id     = "alias/NTT-terraform-state"
    dynamodb_table = "ntt-terraform-state-lock"
    #profile = "state"
  }
}


provider "aws" {
  region = var.region
  #profile = "state"

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