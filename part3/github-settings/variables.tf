variable "github_token" {
  description = "GitHub personal access token with repo and admin:org scopes"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub organisation or user name that owns the repository"
  type        = string
}

variable "repository" {
  description = "Repository name (without the owner prefix)"
  type        = string
}

variable "required_approvals" {
  description = "Number of approving reviews required before a PR can be merged into main"
  type        = number
  default     = 1
}
