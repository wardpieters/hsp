data "restful_resource" "container_features" {
  count        = var.guest_type == "lxc" ? 1 : 0
  id           = "/nodes/${var.node_name}/lxc/${proxmox_virtual_environment_container.this[0].vm_id}/config"
  selector     = "data"
  output_attrs = ["features"]
  depends_on   = [proxmox_virtual_environment_container.this]
}

locals {
  # Omitted false flags and explicit zeros differ to Proxmox's permission check.
  # Retain existing zeros instead of adding or removing unrelated feature flags.
  existing_features = try(coalesce(data.restful_resource.container_features[0].output.features, ""), "")
  preserved_features = sort([
    for flag in split(",", local.existing_features) : flag
    if flag != "" && !startswith(flag, "nesting=")
  ])
}

resource "restful_resource" "nesting" {
  count         = var.guest_type == "lxc" ? 1 : 0
  path          = data.restful_resource.container_features[0].id
  create_method = "PUT"
  update_method = "PUT"
  # Project onto features; a missing property becomes drift instead of a read error.
  read_selector = "data|{features}"
  output_attrs  = ["features"]
  body          = { features = join(",", concat(local.preserved_features, ["nesting=${var.nesting ? 1 : 0}"])) }
  # A feature resource must never issue DELETE against a container endpoint.
  delete_method = "PUT"
  delete_body   = { features = join(",", concat(local.preserved_features, ["nesting=0"])) }

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_container.this[0].id]
    precondition {
      condition     = alltrue([for flag in local.preserved_features : contains(["fuse=0", "keyctl=0", "mknod=0"], flag)])
      error_message = "LXC nesting management requires all unrelated features disabled. Existing explicit fuse=0/keyctl=0/mknod=0 flags are preserved; enabled or unsupported flags cannot be changed with this API token."
    }
  }
}
