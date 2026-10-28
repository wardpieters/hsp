output "apply_generation" {
  description = "Last SDN apply generation, for verifying reconciliation and drift repair."
  value       = proxmox_sdn_applier.apply.id
}
