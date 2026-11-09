mock_provider "system" { alias = "proxmox" }
variables {
  settings_file = "../settings.json.example"
  he_ipv6_file  = "../he-ipv6.json.example"
}
run "starter_host_has_no_ipv6_tunnel" {
  command = plan
  assert {
    condition     = output.he_ipv6_status == null
    error_message = "The host starter must leave optional HE routing disabled."
  }
}
