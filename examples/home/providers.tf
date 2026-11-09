provider "proxmox" {
  endpoint  = local.settings.proxmox_endpoint
  insecure  = local.settings.proxmox_insecure_tls
  api_token = var.proxmox_api_token
}

provider "restful" {
  base_url = "${trimsuffix(local.settings.proxmox_endpoint, "/")}/api2/json"
  client   = { tls_insecure_skip_verify = local.settings.proxmox_insecure_tls }
  security = {
    apikey = [{ in = "header", name = "Authorization", value = "PVEAPIToken=${var.proxmox_api_token}" }]
  }
}

provider "pihole" {
  url          = local.settings.pihole_url
  password     = var.pihole_password
  insecure_tls = local.settings.pihole_insecure_tls
}

provider "system" {
  alias = "ingress"
  ssh {
    host     = local.settings.proxmox_ssh.host
    user     = local.settings.proxmox_ssh.user
    port     = local.settings.proxmox_ssh.port
    host_key = local.settings.proxmox_ssh.host_key
    agent    = true
  }
  sudo = local.settings.proxmox_ssh.user != "root"
}
