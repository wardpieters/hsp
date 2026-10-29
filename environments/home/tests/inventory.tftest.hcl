mock_provider "proxmox" {}
mock_provider "pihole" {}
variables {
  proxmox_endpoint      = "https://192.168.1.10:8006/"
  pihole_url            = "https://192.168.1.53"
  pihole_password       = "offline-test-only"
  node_name             = "pve"
  platform_cidr         = "10.77.0.0/24"
  host_address          = "192.168.1.10"
  protected_cidrs       = ["192.168.1.0/24"]
  bootstrap_admin_cidrs = ["192.168.1.42/32"]
  dns_servers           = ["192.168.1.53"]
  ntp_servers           = ["192.168.1.1"]
  template_id           = 9000
  datastore_id          = "local-lvm"
  ssh_public_keys       = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  guests = {
    proxy = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "private_proxy" }
    cloud = { vm_id = 101, slot = 1, vnet_id = "hsp101", dns = { cloud = { mode = "proxy", proxy_name = "proxy" } } }
  }
  connections = [{ from = "proxy", to = "cloud", protocol = "tcp", port = 8080 }]
}
run "paired_rules_and_dns" {
  command = plan
  assert {
    condition     = output.guests["cloud"].address == "10.77.0.6" && output.guests["proxy"].address == "10.77.0.2"
    error_message = "Stable slots must produce the same addresses across modules."
  }
  assert {
    condition     = contains([for r in output.policies["proxy"] : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.6/32:8080") && contains([for r in output.policies["cloud"] : "${r.type}:${coalesce(r.source, "-")}:${coalesce(r.dport, "-")}"], "in:10.77.0.2/32:8080")
    error_message = "A declared connection needs both source egress and destination ingress."
  }
  assert {
    condition     = output.dns_targets["cloud"] == "10.77.0.2"
    error_message = "The application alias must resolve to its declared proxy."
  }
  assert {
    condition     = alltrue(flatten([for rules in values(output.policies) : [for r in rules : !(r.action == "ACCEPT" && contains(var.bootstrap_admin_cidrs, coalesce(r.source, "-")))]]))
    error_message = "Omitting bootstrap must not grant administrator LAN access to guests."
  }
}
run "lan_public_ports_are_per_guest" {
  command = plan
  variables {
    public_ports_lan_cidrs = ["192.168.1.0/24"]
    connections            = []
    guests = {
      vpn     = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "admin_vpn", public_ports = [{ protocol = "udp", port = 51821 }] }
      web     = { vm_id = 1001, slot = 1, vnet_id = "hsp1001", role = "public_proxy", public_ports = [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }] }
      private = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", role = "private_proxy" }
    }
  }
  assert {
    condition     = toset([for r in output.policies["vpn"] : "${r.type}:${r.proto}:${r.dport}" if r.action == "ACCEPT" && r.source == "192.168.1.0/24"]) == toset(["in:udp:51821"]) && toset([for r in output.policies["web"] : "${r.type}:${r.proto}:${r.dport}" if r.action == "ACCEPT" && r.source == "192.168.1.0/24"]) == toset(["in:tcp:80", "in:tcp:443"])
    error_message = "The top-level LAN setting must allow exactly each guest's own public ports across all module layers."
  }
  assert {
    condition     = length([for r in output.policies["private"] : r if r.action == "ACCEPT" && r.source == "192.168.1.0/24"]) == 0
    error_message = "A VM without public ports must not receive LAN access through this setting."
  }
}
run "reject_guest_network_as_public_ports_lan" {
  command = plan
  variables { public_ports_lan_cidrs = ["10.77.0.0/25"] }
  expect_failures = [var.public_ports_lan_cidrs]
}
run "internet_egress_is_per_guest" {
  command = plan
  variables {
    guests = {
      proxy = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "private_proxy", internet_egress_ports = [{ protocol = "tcp", port = 443 }] }
      cloud = { vm_id = 101, slot = 1, vnet_id = "hsp101" }
    }
  }
  assert {
    condition     = toset([for r in output.policies["proxy"] : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == toset(["tcp:443"])
    error_message = "The guest's internet port list must propagate through the service and VM modules."
  }
  assert {
    condition     = length([for r in output.policies["cloud"] : r if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == 0
    error_message = "Enabling internet egress for one guest must not enable it for another."
  }
}
run "shared_http_proxy" {
  command = plan
  variables {
    private_proxy_name = "private"
    http_proxy_name    = "http-proxy"
    connections        = [{ from = "family", to = "http-proxy", protocol = "tcp", port = 3128 }]
    guests = {
      admin      = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "admin_vpn" }
      family     = { vm_id = 1001, slot = 1, vnet_id = "hsp1001", role = "service_vpn" }
      public     = { vm_id = 1002, slot = 2, vnet_id = "hsp1002", role = "public_proxy" }
      private    = { vm_id = 1003, slot = 3, vnet_id = "hsp1003", role = "private_proxy" }
      cloud      = { vm_id = 1004, slot = 4, vnet_id = "hsp1004" }
      tools      = { vm_id = 1005, slot = 5, vnet_id = "hsp1005", role = "management" }
      http-proxy = { vm_id = 1006, slot = 6, vnet_id = "hsp1006", internet_egress_ports = [{ protocol = "tcp", port = 80 }, { protocol = "tcp", port = 443 }] }
    }
  }
  assert {
    condition     = alltrue([for name, rules in output.policies : contains([for r in rules : "${r.type}:${r.action}:${coalesce(r.dest, "-")}:${coalesce(r.proto, "-")}:${coalesce(r.dport, "-")}"], "out:ACCEPT:10.77.0.26/32:tcp:3128") if name != "http-proxy"])
    error_message = "Every other guest, including the family VPN, must reach the selected HTTP proxy on TCP 3128."
  }
  assert {
    condition     = toset([for r in output.policies["http-proxy"] : r.source if r.type == "in" && r.action == "ACCEPT" && r.proto == "tcp" && r.dport == "3128"]) == toset(["10.77.0.2/32", "10.77.0.6/32", "10.77.0.10/32", "10.77.0.14/32", "10.77.0.18/32", "10.77.0.22/32"])
    error_message = "The HTTP proxy must accept TCP 3128 only from the declared client guests."
  }
  assert {
    condition     = toset([for r in output.policies["http-proxy"] : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == toset(["tcp:80", "tcp:443"]) && alltrue([for name, rules in output.policies : length([for r in rules : r if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == 0 if name != "http-proxy"])
    error_message = "Only the HTTP proxy gets direct internet HTTP/HTTPS access."
  }
  assert {
    condition     = alltrue([for name, rules in output.policies : try(index([for r in rules : "${r.type}:${coalesce(r.dest, "-")}:${coalesce(r.proto, "-")}:${coalesce(r.dport, "-")}"], "out:10.77.0.26/32:tcp:3128") < index([for r in rules : r.comment], "hsp:protect-out:10.77.0.0/24"), false) if name != "http-proxy"])
    error_message = "HTTP proxy exceptions must precede the protected guest-network drop."
  }
}
run "reject_unknown_http_proxy" {
  command = plan
  variables { http_proxy_name = "missing" }
  expect_failures = [var.http_proxy_name]
}
run "reject_service_vpn_unselected_http_proxy" {
  command = plan
  variables {
    private_proxy_name = "proxy"
    http_proxy_name    = "cloud"
    guests = {
      vpn   = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "service_vpn" }
      proxy = { vm_id = 101, slot = 1, vnet_id = "hsp101", role = "private_proxy" }
      cloud = { vm_id = 102, slot = 2, vnet_id = "hsp102" }
    }
    connections = [{ from = "vpn", to = "proxy", protocol = "tcp", port = 3128 }]
  }
  expect_failures = [var.connections]
}
run "reject_service_vpn_other_http_proxy_port" {
  command = plan
  variables {
    private_proxy_name = "proxy"
    http_proxy_name    = "cloud"
    guests = {
      vpn   = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "service_vpn" }
      proxy = { vm_id = 101, slot = 1, vnet_id = "hsp101", role = "private_proxy" }
      cloud = { vm_id = 102, slot = 2, vnet_id = "hsp102" }
    }
    connections = [{ from = "vpn", to = "cloud", protocol = "tcp", port = 8080 }]
  }
  expect_failures = [var.connections]
}
run "bootstrap_ssh_is_scoped_to_selected_guest" {
  command = plan
  variables {
    bootstrap_admin_cidrs = ["192.168.1.42/32", "192.168.1.43/32"]
    connections           = []
    guests = {
      vpn = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "admin_vpn", bootstrap = true }
      app = { vm_id = 1001, slot = 1, vnet_id = "hsp1001", bootstrap = false }
    }
  }
  assert {
    condition = toset([for r in output.policies["vpn"] : "${r.type}:${r.action}:${r.source}:${r.proto}:${r.dport}" if contains(var.bootstrap_admin_cidrs, coalesce(r.source, "-"))]) == toset([
      "in:ACCEPT:192.168.1.42/32:tcp:22",
      "in:ACCEPT:192.168.1.43/32:tcp:22"
    ])
    error_message = "Bootstrap must grant only incoming TCP 22 from each listed administrator /32."
  }
  assert {
    condition     = try(alltrue([for source in var.bootstrap_admin_cidrs : index([for r in output.policies["vpn"] : r.source], source) < index([for r in output.policies["vpn"] : r.source], "192.168.1.0/24")]), false)
    error_message = "Bootstrap SSH exceptions must precede the protected LAN drop."
  }
  assert {
    condition     = alltrue([for r in output.policies["app"] : !(r.action == "ACCEPT" && contains(var.bootstrap_admin_cidrs, coalesce(r.source, "-")))])
    error_message = "Enabling bootstrap on one guest must not open another guest."
  }
}
run "bootstrap_ssh_disabled" {
  command = plan
  variables {
    connections = []
    guests = {
      vpn = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "admin_vpn", bootstrap = false }
      app = { vm_id = 1001, slot = 1, vnet_id = "hsp1001" }
    }
  }
  assert {
    condition     = alltrue(flatten([for rules in values(output.policies) : [for r in rules : !(r.action == "ACCEPT" && contains(var.bootstrap_admin_cidrs, coalesce(r.source, "-")))]]))
    error_message = "Turning bootstrap off must remove the administrator SSH exceptions."
  }
}
run "reject_duplicate_slots" {
  command = plan
  variables {
    connections = []
    guests      = { a = { vm_id = 100, slot = 0, vnet_id = "hsp100" }, b = { vm_id = 101, slot = 0, vnet_id = "hsp101" } }
  }
  expect_failures = [var.guests]
}
run "reject_duplicate_ids" {
  command = plan
  variables {
    connections = []
    guests      = { a = { vm_id = 100, slot = 0, vnet_id = "hsp100" }, b = { vm_id = 100, slot = 1, vnet_id = "hsp101" } }
  }
  expect_failures = [var.guests]
}
run "reject_duplicate_names" {
  command = plan
  variables {
    connections = []
    guests      = { a = { vm_id = 100, slot = 0, vnet_id = "hsp100", dns = { clash = { mode = "direct" } } }, b = { vm_id = 101, slot = 1, vnet_id = "hsp101", dns = { clash = { mode = "direct" } } } }
  }
  expect_failures = [var.guests]
}
run "reject_vpn_to_admin" {
  command = plan
  variables {
    private_proxy_name = "proxy"
    guests             = { vpn = { vm_id = 100, slot = 0, vnet_id = "hsp100", role = "service_vpn" }, proxy = { vm_id = 101, slot = 1, vnet_id = "hsp101", role = "private_proxy" } }
    connections        = [{ from = "vpn", to = "proxy", protocol = "tcp", port = 22 }]
  }
  expect_failures = [var.connections]
}
