mock_provider "proxmox" {}
variables {
  platform_cidr = "10.77.0.0/24"
  slot          = 3
  zone_id       = "hsp"
  vnet_id       = "hsp100"
}
run "stable_slot" {
  command = plan
  assert {
    condition     = output.cidr == "10.77.0.12/30"
    error_message = "Slot 3 must keep its own /30."
  }
  assert {
    condition     = output.gateway == "10.77.0.13" && output.address == "10.77.0.14"
    error_message = "Gateway and guest offsets must remain 1 and 2."
  }
}
run "reject_overflow" {
  command = plan
  variables { slot = 64 }
  expect_failures = [var.slot]
}
run "reject_negative_slot" {
  command = plan
  variables { slot = -1 }
  expect_failures = [var.slot]
}
run "reject_invalid_vnet" {
  command = plan
  variables { vnet_id = "too-long-name" }
  expect_failures = [var.vnet_id]
}
