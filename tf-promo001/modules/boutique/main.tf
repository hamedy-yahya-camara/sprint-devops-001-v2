resource "docker_container" "web" {
  name  = var.nom
  env   = ["CLE_CLIENT=${var.cle}"]
  image = var.image

  ports {
    internal = 80
    external = var.port
  }

  networks_advanced {
    name = var.reseau
  }

  upload {
    content = var.page
    file    = "/usr/share/nginx/html/index.html"
  }

  restart = var.redemarrage

  lifecycle {
    ignore_changes = [env, ports, upload, networks_advanced]
  }
}
