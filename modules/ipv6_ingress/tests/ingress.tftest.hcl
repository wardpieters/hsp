mock_provider "system" {}
variables {
  public_address  = "2001:470:1f15:4d6::2"
  ula_prefix      = "fd42:77:1::/48"
  protected_cidrs = ["2001:db8:abcd::/48"]
  forwards        = { http = { guest = "proxy", port = 80, address = "fd42:77:1:2::2", vnet_id = "hsp1002" }, https = { guest = "proxy", port = 443, address = "fd42:77:1:2::2", vnet_id = "hsp1002" } }
  egress          = { cloud = { address = "fd42:77:1:1::2", vnet_id = "hsp1001", ports = [{ protocol = "tcp", port = 443 }, { protocol = "udp", port = 123 }, { protocol = "icmp" }] } }
}
run "enabled" {
  command = apply
  assert {
    condition     = strcontains(system_file.ingress_rules.content, "dnat to fd42:77:1:2::2") && strcontains(system_file.ingress_rules.content, "snat to 2001:470:1f15:4d6::2") && strcontains(system_file.ingress_rules.content, "2001:db8:abcd::/48")
    error_message = "Host edge must render incoming DNAT, outgoing fixed-VIP SNAT and protected ranges."
  }
}
run "revoked" {
  command = apply
  variables {
    forwards = { http = { guest = "proxy", port = 80, address = "fd42:77:1:2::2", vnet_id = "hsp1002" } }
    egress   = { cloud = { address = "fd42:77:1:1::2", vnet_id = "hsp1001", ports = [{ protocol = "udp", port = 123 }] } }
  }
  assert {
    condition     = !strcontains(system_file.ingress_permissions.content, "|tcp|443|") && !strcontains(system_file.ingress_permissions.content, "|icmp|none|") && strcontains(system_file.ingress_permissions.content, "|udp|123|")
    error_message = "Revoked protocol/ports must leave the desired manifest while retained UDP remains."
  }
}
run "egress_only" {
  command = plan
  variables { forwards = {} }
  assert {
    condition     = !strcontains(system_file.ingress_rules.content, "dnat to") && strcontains(system_file.ingress_rules.content, "snat to")
    error_message = "Egress-only configurations must work without any public forward."
  }
}
run "reject_bad_target" {
  command = plan
  variables { forwards = { bad = { guest = "proxy", port = 443, address = "2001:db8::2", vnet_id = "hsp1002" } } }
  expect_failures = [var.forwards]
}
