provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = var.proxmox_insecure_tls
  api_token = var.proxmox_api_token
}
provider "restful" {
  base_url = "${trimsuffix(var.proxmox_endpoint, "/")}/api2/json"
  client   = { tls_insecure_skip_verify = var.proxmox_insecure_tls }
  security = {
    apikey = [{ in = "header", name = "Authorization", value = "PVEAPIToken=${var.proxmox_api_token}" }]
  }
}
provider "pihole" {
  url          = var.pihole_url
  password     = var.pihole_password
  insecure_tls = var.pihole_insecure_tls
}

# Pass the SAME -var-file=../he-ipv6.tfvars to home and host-config.
# Missing teardown credentials fail against a reserved invalid hostname;
# unused default-off configurations never connect or fall back to localhost.
provider "system" {
  alias = "ingress"
  ssh {
    host     = var.proxmox_ssh == null ? "disabled.invalid" : var.proxmox_ssh.host
    user     = var.proxmox_ssh == null ? "root" : var.proxmox_ssh.user
    port     = var.proxmox_ssh == null ? 22 : var.proxmox_ssh.port
    host_key = var.proxmox_ssh == null ? null : var.proxmox_ssh.host_key
    agent    = true
  }
  sudo = var.proxmox_ssh == null ? false : var.proxmox_ssh.user != "root"
}
