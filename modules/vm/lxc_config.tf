locals {
  lxc_cgroup_entries = flatten([
    for key in sort(keys(var.lxc_cgroups)) : [for value in var.lxc_cgroups[key] : { key = "lxc.cgroup2.${key}", value = value }]
  ])
  lxc_entries = concat(
    [for mount in var.lxc_mounts : ["lxc.mount.entry", mount]],
    [for entry in local.lxc_cgroup_entries : [entry.key, entry.value]]
  )
}

resource "terraform_data" "lxc_config" {
  count = var.guest_type == "lxc" && length(local.lxc_entries) > 0 ? 1 : 0
  input = {
    ssh     = var.proxmox_ssh
    payload = base64encode(jsonencode({ vm_id = var.vm_id, node_name = var.node_name, entries = local.lxc_entries }))
    # Save code and connection in state so destroy uses precisely the old ownership.
    script = base64encode(file("${path.module}/scripts/lxc-config.pl"))
  }
  triggers_replace = [var.proxmox_ssh, local.lxc_entries, filesha256("${path.module}/scripts/lxc-config.pl")]

  connection {
    type     = "ssh"
    host     = try(self.input.ssh.host, "")
    user     = try(self.input.ssh.user, "root")
    port     = try(self.input.ssh.port, 22)
    host_key = try(self.input.ssh.host_key, null)
    agent    = true
  }
  provisioner "remote-exec" {
    inline = ["${self.input.ssh.user == "root" ? "" : "sudo -n "}perl -MMIME::Base64 -e 'my $code = shift @ARGV; eval decode_base64($code); die $@ if $@;' '${self.input.script}' '${self.input.payload}' apply"]
  }
  provisioner "remote-exec" {
    when   = destroy
    inline = ["${self.input.ssh.user == "root" ? "" : "sudo -n "}perl -MMIME::Base64 -e 'my $code = shift @ARGV; eval decode_base64($code); die $@ if $@;' '${self.input.script}' '${self.input.payload}' remove"]
  }
  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_container.this[0].id]
  }
  depends_on = [restful_resource.nesting]
}
