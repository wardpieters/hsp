variable "proxmox_api_token" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "pihole_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_keys" {
  description = "Public keys for initial guest access; HSP validates the key format."
  type        = list(string)
}
