mock_provider "system" { alias = "ingress" }
mock_provider "proxmox" {}
mock_provider "pihole" {}
mock_provider "restful" {}
variables {
  settings_file     = "../settings.json.example"
  he_ipv6_file      = "../he-ipv6.json.example"
  proxmox_api_token = "offline@pve!example=offline-test-only"
  pihole_password   = "offline-test-only"
  ssh_public_keys   = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f synthetic-test-only"]
}
run "starter_connects_inventory_network_dns_and_policy" {
  command = plan
  assert {
    condition     = output.guests["proxy"].address == "10.88.0.2" && output.guests["app"].address == "10.88.0.6" && output.dns_targets["app"] == "10.88.0.2"
    error_message = "The starter must wire its published modules, slots, and proxy DNS together."
  }
  assert {
    condition     = alltrue([for g in values(output.guests) : g.started == false]) && output.ipv6_ingress == null
    error_message = "The starter must leave guests stopped and IPv6 disabled."
  }
  assert {
    condition     = contains([for r in output.policies["proxy"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.88.0.6/32:8080")
    error_message = "The declared proxy-to-app connection must generate the destination-specific access rule."
  }
}
