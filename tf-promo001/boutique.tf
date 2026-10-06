resource "docker_network" "epreuve" {
  name = var.reseau
}

module "boutiques" {
  source   = "./modules/boutique"
  for_each = var.boutiques

  nom         = each.value.nom
  image       = docker_image.nginx.image_id
  reseau      = docker_network.epreuve.name
  port        = each.value.port
  page        = each.value.page
  cle         = var.cle
  redemarrage = var.redemarrage
}

moved {
  from = docker_container.epreuve
  to   = module.boutique.docker_container.web
}

moved {
  from = module.boutique
  to   = module.boutiques["origine"]
}
moved {
  from = module.boutiques["atelier"]
  to   = module.boutiques["studio"]
}
