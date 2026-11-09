# Optional file paths let tests use fixtures independently of local settings.
variable "settings_file" {
  type    = string
  default = null
}

variable "he_ipv6_file" {
  type    = string
  default = null
}
