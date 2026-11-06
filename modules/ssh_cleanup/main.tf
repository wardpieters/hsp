terraform {
  required_version = ">= 1.9, < 2.0"
}
# Separate module allows offline tests to override the entire SSH action.
variable "settings" {
  type = object({
    ssh     = object({ host = string, user = string, port = optional(number, 22), host_key = optional(string) })
    command = string
  })
}
resource "terraform_data" "gate" {
  input = var.settings
  connection {
    type     = "ssh"
    host     = self.input.ssh.host
    user     = self.input.ssh.user
    port     = self.input.ssh.port
    host_key = self.input.ssh.host_key
    agent    = true
  }
  provisioner "remote-exec" {
    when   = destroy
    inline = ["${self.input.ssh.user == "root" ? "" : "sudo -n "}/usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/sh -c '${self.input.command}'"]
  }
}
