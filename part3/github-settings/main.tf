terraform {
  required_version = ">= 1.14.0"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

# NOTE: branch_name_pattern in repository rulesets requires GitHub Enterprise Cloud.
# Branch naming (GCC-NNNN-*) is enforced by the jira-gate pipeline job instead.

# =============================================================================
# Ruleset — Main Branch Protection
#
# Enforces on main:
#   - PRs required (at least 1 approval, stale reviews dismissed on new push)
#   - All three compliance pipeline jobs must pass before merge
#   - No force-pushes, no branch deletion
# =============================================================================

resource "github_repository_ruleset" "main_protection" {
  name        = "main-branch-protection"
  repository  = var.repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/heads/main"]
      exclude = []
    }
  }

  rules {
    pull_request {
      required_approving_review_count   = var.required_approvals
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = true
      required_review_thread_resolution = true
      require_code_owner_review         = false
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      required_check {
        context = "Jira Comment"
      }

      required_check {
        context = "Checkov + SHIP-HAT Compliance"
      }

      required_check {
        context = "Generate Release Notes"
      }
    }

    non_fast_forward = true
    deletion         = true
  }
}
