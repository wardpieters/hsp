output "reload_generation" {
  description = "Generation loaded by the helper service, useful for diagnosing drift reconciliation."
  value       = terraform_data.revision.id
}
