mock_provider "pihole" {}
variables {
  domain = "home.example.com"
  records = {
    storage = { mode = "direct", address = "10.77.0.2" }
    cloud   = { mode = "proxy", address = "10.77.0.2", proxy_address = "10.77.0.6" }
    hidden  = { mode = "none", address = "10.77.0.2" }
  }
}
run "targets" {
  command = plan
  assert {
    condition     = pihole_dns_record.this["storage"].domain == "storage.home.example.com" && pihole_dns_record.this["storage"].ip == "10.77.0.2" && pihole_dns_record.this["cloud"].ip == "10.77.0.6" && !contains(keys(pihole_dns_record.this), "hidden")
    error_message = "DNS must honor direct/proxy/none independently for every alias."
  }
}
run "reject_missing_proxy" {
  command = plan
  variables { records = { cloud = { mode = "proxy", address = "10.77.0.2" } } }
  expect_failures = [var.records]
}
run "reject_outside_name" {
  command = plan
  variables { records = { "bad.example.com" = { mode = "direct", address = "10.77.0.2" } } }
  expect_failures = [var.records]
}
