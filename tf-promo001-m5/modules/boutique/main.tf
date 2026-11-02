resource "docker_container" "web" {
  name  = var.nom
  env   = ["CLE_CLIENT=${var.cle}"]
  image = var.image

  dynamic "ports" {
    for_each = var.publier_port ? [var.port] : []
    content {
      internal = 80
      external = ports.value
    }
  }

  networks_advanced {
    name = var.reseau
  }

  upload {
    content = var.page
    file    = "/usr/share/nginx/html/index.html"
  }

  restart = var.redemarrage
}
