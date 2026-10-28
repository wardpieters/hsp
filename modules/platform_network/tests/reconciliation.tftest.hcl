mock_provider "proxmox" {}
variables {
  platform_cidr   = "10.77.0.0/24"
  protected_cidrs = ["192.168.1.0/24"]
  node_name       = "pve"
  networks        = { app = { slot = 0, vnet_id = "hsp100" } }
}
run "original" {
  command = apply
}
# Force resource replacement without changing the desired inventory, modeling
# repair of an SDN object removed externally. The apply trigger must follow it.
run "zone_repair" {
  command = apply
  plan_options { replace = [proxmox_sdn_zone_simple.this] }
  assert {
    condition     = output.apply_generation != run.original.apply_generation
    error_message = "Repairing a zone must apply staged SDN even when the inventory has not changed."
  }
}
run "vnet_repair" {
  command = apply
  plan_options { replace = [module.guest["app"].proxmox_sdn_vnet.this] }
  assert {
    condition     = output.apply_generation != run.zone_repair.apply_generation
    error_message = "Repairing a VNet must trigger the centralized SDN apply."
  }
}
run "subnet_repair" {
  command = apply
  plan_options { replace = [module.guest["app"].proxmox_sdn_subnet.this] }
  assert {
    condition     = output.apply_generation != run.vnet_repair.apply_generation
    error_message = "Repairing a subnet must trigger the centralized SDN apply."
  }
}
run "converged" {
  command = apply
  assert {
    condition     = output.apply_generation == run.subnet_repair.apply_generation
    error_message = "A converged network must not perpetually reapply."
  }
}
