provider "system" {
  alias = "proxmox"
  ssh {
    host     = local.settings.proxmox_ssh.host
    user     = local.settings.proxmox_ssh.user
    port     = local.settings.proxmox_ssh.port
    host_key = local.settings.proxmox_ssh.host_key
    agent    = true
  }
  sudo = local.settings.proxmox_ssh.user != "root"
}
