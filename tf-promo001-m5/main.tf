locals {
  page_statut = <<-HTML
    <!doctype html>
    <html lang="fr">
    <head><meta charset="utf-8"><title>Statut Mission 5</title></head>
    <body>
      <h1>Mission 5 Terraform</h1>
      <p>Pseudo : hamedy</p>
      <p>Environnement : ${var.prefixe}</p>
      <p>Statut : en ligne</p>
    </body>
    </html>
  HTML
}

resource "docker_network" "frontal" {
  name = "${var.prefixe}-frontal"
}

resource "docker_network" "donnees" {
  name = "${var.prefixe}-donnees"
}

resource "docker_image" "postgres" {
  name = var.image_postgres
}

resource "docker_image" "nginx" {
  name = var.image_nginx
}

module "livredor" {
  source = "./modules/livredor"

  nom_app         = "${var.prefixe}-livredor"
  nom_postgres    = "${var.prefixe}-postgres"
  nom_volume      = "${var.prefixe}-pgdata"
  image_app       = var.image_app
  image_postgres  = docker_image.postgres.image_id
  reseau_frontal  = docker_network.frontal.name
  reseau_donnees  = docker_network.donnees.name
  db_nom          = var.db_nom
  db_utilisateur  = var.db_utilisateur
  db_mot_de_passe = var.db_mot_de_passe
  redemarrage     = "unless-stopped"
}

module "statut" {
  source = "./modules/boutique"

  nom          = "${var.prefixe}-statut"
  image        = docker_image.nginx.image_id
  reseau       = docker_network.frontal.name
  publier_port = false
  page         = local.page_statut
  cle          = "cle-factice-m5"
  redemarrage  = "unless-stopped"
}
