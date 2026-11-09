mock_provider "system" { alias = "ingress" }
mock_provider "restful" {
  override_during = plan
  mock_data "restful_resource" {
    defaults = { output = { features = "" } }
  }
}
mock_provider "proxmox" {}
mock_provider "pihole" {}
variables {
  domain                = "home.example.com"
  node_name             = "pve"
  platform_cidr         = "10.77.0.0/24"
  host_address          = "192.168.1.10"
  protected_cidrs       = ["192.168.1.0/24"]
  bootstrap_admin_cidrs = ["192.168.1.42/32"]
  dns_servers           = ["192.168.1.53"]
  ntp_servers           = []
  vm_template_id        = 9000
  lxc_template          = { file_id = "local:vztmpl/debian-test.tar.zst" }
  datastore_id          = "local-lvm"
  ssh_public_keys       = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
  private_proxy_name    = "private"
  guests = {
    monitor     = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "monitoring" }
    monitor-lxc = { vm_id = 1001, slot = 1, vnet_id = "hsp1001", role = "monitoring", type = "lxc" }
    app         = { vm_id = 1002, slot = 2, vnet_id = "hsp1002" }
    private     = { vm_id = 1003, slot = 3, vnet_id = "hsp1003", role = "private_proxy" }
    public      = { vm_id = 1004, slot = 4, vnet_id = "hsp1004", role = "public_proxy" }
    admin       = { vm_id = 1005, slot = 5, vnet_id = "hsp1005", role = "admin_vpn" }
    family      = { vm_id = 1006, slot = 6, vnet_id = "hsp1006", role = "service_vpn", type = "lxc" }
    management  = { vm_id = 1007, slot = 7, vnet_id = "hsp1007", role = "management" }
  }
}

run "monitoring_reaches_every_other_guest" {
  command = plan
  assert {
    condition = alltrue([for name in ["monitor", "monitor-lxc"] :
      toset([for r in output.policies[name] : "${r.dest}:${r.proto}" if r.type == "out" && r.action == "ACCEPT" && r.dport == "1:65535"]) ==
      toset(flatten([for address in ["10.77.0.2/32", "10.77.0.6/32", "10.77.0.10/32", "10.77.0.14/32", "10.77.0.18/32", "10.77.0.22/32", "10.77.0.26/32", "10.77.0.30/32"] :
      ["${address}:tcp", "${address}:udp"] if address != "${output.guests[name].address}/32"]))
    ])
    error_message = "Each VM or LXC monitor must reach all other declared guests on every TCP/UDP port, without self, host, or LAN exceptions."
  }
  assert {
    condition = alltrue([for name, rules in output.policies :
      toset([for r in rules : "${r.source}:${r.proto}" if r.type == "in" && r.action == "ACCEPT" && r.dport == "1:65535"]) ==
      toset(flatten([for address in ["10.77.0.2/32", "10.77.0.6/32"] :
      ["${address}:tcp", "${address}:udp"] if address != "${output.guests[name].address}/32"]))
    ])
    error_message = "Every destination must accept all TCP/UDP ports only from the other monitoring guests."
  }
  assert {
    condition = alltrue(flatten([for rules in values(output.policies) : [for i, r in rules :
      i < index([for rule in rules : rule.comment], r.type == "in" ? "hsp:protect-in:10.77.0.0/24" : "hsp:protect-out:10.77.0.0/24")
      if r.action == "ACCEPT" && r.dport == "1:65535"
    ]]))
    error_message = "Both sides of monitoring connections must precede protected-network drops."
  }
  assert {
    condition = alltrue([for name, rules in output.policies :
      contains(["monitor", "monitor-lxc"], name) ?
      toset([for r in rules : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == toset(["tcp:80", "tcp:443"]) :
      length([for r in rules : r if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == 0
    ])
    error_message = "Only monitoring guests must receive direct TCP 80/443 internet egress by default."
  }
  assert {
    condition = alltrue(flatten([for rules in values(output.policies) : [for i, r in rules :
      alltrue([for j, rule in rules : i > j if rule.type == "out" && rule.action == "DROP"])
      if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"
    ]]))
    error_message = "Direct web egress must follow every outbound protected-network and IPv6 drop."
  }
}

run "monitoring_egress_merges_with_explicit_ports" {
  command = plan
  variables {
    private_proxy_name    = null
    internet_egress_ports = [{ protocol = "udp", port = 123 }, { protocol = "tcp", port = 443 }]
    guests = {
      monitor = { vm_id = 1000, slot = 0, vnet_id = "hsp1000", role = "monitoring", internet_egress_ports = [{ protocol = "tcp", port = 80 }, { protocol = "udp", port = 161 }] }
      app     = { vm_id = 1001, slot = 1, vnet_id = "hsp1001" }
    }
  }
  assert {
    condition     = sort([for r in output.policies["monitor"] : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == sort(["tcp:80", "tcp:443", "udp:123", "udp:161"])
    error_message = "Monitoring web defaults must merge with global and guest egress without duplicate rules."
  }
  assert {
    condition     = toset([for r in output.policies["app"] : "${r.proto}:${r.dport}" if r.type == "out" && r.action == "ACCEPT" && r.dest == "0.0.0.0/0"]) == toset(["udp:123", "tcp:443"])
    error_message = "Other roles must retain only their configured egress ports."
  }
}
