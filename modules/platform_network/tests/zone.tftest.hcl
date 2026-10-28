mock_provider "proxmox" {}
variables {
  platform_cidr   = "10.77.0.0/24"
  protected_cidrs = ["192.168.1.0/24"]
  node_name       = "pve"
  zone_id         = "hsp"
}
run "local_zone" {
  command = plan
  assert {
    condition     = proxmox_sdn_zone_simple.this.nodes == toset(["pve"])
    error_message = "The zone must stay on the single declared node."
  }
}
run "reject_overlap" {
  command = plan
  variables { protected_cidrs = ["10.77.0.64/26"] }
  expect_failures = [var.protected_cidrs]
}
run "reject_public_aggregate" {
  command = plan
  variables { platform_cidr = "203.0.113.0/24" }
  expect_failures = [var.platform_cidr]
}
run "reject_containing_protected_range" {
  command = plan
  variables { protected_cidrs = ["10.0.0.0/8"] }
  expect_failures = [var.protected_cidrs]
}
run "allow_adjacent_network" {
  command = plan
  variables { protected_cidrs = ["10.77.1.0/24"] }
}
