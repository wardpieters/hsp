terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    pihole = { source = "lukaspustina/pihole", version = "0.3.1" }
  }
}
