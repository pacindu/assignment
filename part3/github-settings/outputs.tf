output "main_protection_ruleset_id" {
  description = "ID of the main branch protection ruleset"
  value       = github_repository_ruleset.main_protection.ruleset_id
}
