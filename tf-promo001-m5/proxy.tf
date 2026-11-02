resource "docker_container" "proxy" {
  name    = "${var.prefixe}-proxy"
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.port_public
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.frontal.name
  }

  upload {
    content = templatefile("${path.module}/nginx.conf.tftpl", {
      nom_app    = module.livredor.nom_app
      nom_statut = module.statut.nom
    })
    file = "/etc/nginx/conf.d/default.conf"
  }
}
