resource "docker_network" "epreuve" {
  name = var.reseau
}

resource "docker_container" "epreuve" {
  name  = var.conteneur
  env   = ["CLE_CLIENT=${var.cle}"]
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = var.port
  }

  networks_advanced {
    name = docker_network.epreuve.name
  }

  upload {
    content = local.page
    file    = "/usr/share/nginx/html/index.html"
  }

  lifecycle {
    ignore_changes = [env, ports, upload, networks_advanced]
  }
}
