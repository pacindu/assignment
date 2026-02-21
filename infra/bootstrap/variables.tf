variable "region" {
  description = "AWS region to deploy bootstrap resources into"
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}

# variable "cicd_role_name" {
#   description = "Name of the IAM role used by the CI/CD pipeline"
#   type        = string
#   default     = "ntt-cicd-role"
# }

#variable "github_org" {
#  description = "GitHub organisation name (used to scope the OIDC trust policy)"
#  type        = string
#}

# variable "github_repo" {
#   description = "GitHub repository name (used to scope the OIDC trust policy)"
#   type        = string
# }

variable "tags" {
  description = "A map of tags to apply to all bootstrap resources"
  type        = map(string)
  default     = {}
}
