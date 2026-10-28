terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "0.118.1" }
    pihole  = { source = "lukaspustina/pihole", version = "0.3.1" }
  }
}
