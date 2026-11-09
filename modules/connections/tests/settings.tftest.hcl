variables {
  settings = { platform_cidr = "10.77.0.0/24" }
}
run "optional_connections_default_without_provider_configuration" {
  command = plan
  assert {
    condition     = output.settings.proxmox_ssh == null && output.settings.proxmox_insecure_tls == false && output.settings.pihole_insecure_tls == false
    error_message = "Omitted connection settings must retain their defaults."
  }
}
run "ssh_defaults_and_nulls" {
  command = plan
  variables {
    settings = { platform_cidr = "10.77.0.0/24", proxmox_ssh = { host = "192.0.2.10", user = "root", port = null }, proxmox_insecure_tls = null }
  }
  assert {
    condition     = output.settings.proxmox_ssh.port == 22 && output.settings.proxmox_ssh.host_key == null && output.settings.proxmox_insecure_tls == false
    error_message = "SSH and TLS defaults must survive omitted and explicit-null fields."
  }
}
run "custom_ssh_and_https_endpoints" {
  command = plan
  variables {
    settings = { platform_cidr = "10.77.0.0/24", proxmox_endpoint = "https://192.0.2.10:8006/", pihole_url = "https://192.0.2.53", proxmox_ssh = { host = "192.0.2.10", user = "admin", port = 2222, host_key = "fixture-key" } }
  }
  assert {
    condition     = output.settings.proxmox_ssh.port == 2222 && output.settings.proxmox_ssh.host_key == "fixture-key" && output.settings.proxmox_endpoint == "https://192.0.2.10:8006/"
    error_message = "Connection settings must reach the provider boundary unchanged."
  }
}
run "reject_http_proxmox" {
  command = plan
  variables { settings = { platform_cidr = "10.77.0.0/24", proxmox_endpoint = "http://192.0.2.10:8006" } }
  expect_failures = [output.settings]
}
run "reject_http_pihole" {
  command = plan
  variables { settings = { platform_cidr = "10.77.0.0/24", pihole_url = "http://192.0.2.53" } }
  expect_failures = [output.settings]
}
run "reject_embedded_credentials" {
  command = plan
  variables { settings = { platform_cidr = "10.77.0.0/24", proxmox_endpoint = "https://user:secret@192.0.2.10" } }
  expect_failures = [output.settings]
}
run "reject_api_path" {
  command = plan
  variables { settings = { platform_cidr = "10.77.0.0/24", pihole_url = "https://192.0.2.53/api" } }
  expect_failures = [output.settings]
}
run "reject_query_string" {
  command = plan
  variables { settings = { platform_cidr = "10.77.0.0/24", proxmox_endpoint = "https://192.0.2.10?token=fixture" } }
  expect_failures = [output.settings]
}
run "reject_fragment" {
  command = plan
  variables { settings = { platform_cidr = "10.77.0.0/24", pihole_url = "https://192.0.2.53/#fixture" } }
  expect_failures = [output.settings]
}

run "required_endpoints_cannot_fall_back_to_provider_environment" {
  command = plan
  variables { require_api_endpoints = true }
  expect_failures = [output.settings]
}
run "required_endpoints_reject_explicit_null" {
  command = plan
  variables {
    require_api_endpoints = true
    settings              = { platform_cidr = "10.77.0.0/24", proxmox_endpoint = "https://192.0.2.10:8006", pihole_url = null }
  }
  expect_failures = [output.settings]
}
run "required_endpoints_accept_https_pair" {
  command = plan
  variables {
    require_api_endpoints = true
    settings              = { platform_cidr = "10.77.0.0/24", proxmox_endpoint = "https://192.0.2.10:8006", pihole_url = "https://192.0.2.53" }
  }
}
