removed {
  from = docker_network.archive_reseau

  lifecycle {
    destroy = false
  }
}

resource "docker_container" "coffre" {
  name         = "archive-codex"
  image        = "nginx:1.27-alpine"
  network_mode = "archives-codex"

  lifecycle {
    ignore_changes  = [env]
    prevent_destroy = true
  }
}

moved {
  from = docker_container.archive
  to   = docker_container.coffre
}
