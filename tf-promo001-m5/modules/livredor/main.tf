resource "docker_volume" "pgdata" {
  name = var.nom_volume

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "postgres" {
  name    = var.nom_postgres
  image   = var.image_postgres
  restart = var.redemarrage
  wait    = true

  env = [
    "POSTGRES_DB=${var.db_nom}",
    "POSTGRES_USER=${var.db_utilisateur}",
    "POSTGRES_PASSWORD=${var.db_mot_de_passe}",
  ]

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.db_utilisateur} -d ${var.db_nom}"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = var.reseau_donnees
  }
}

resource "docker_container" "app" {
  name    = var.nom_app
  image   = var.image_app
  restart = var.redemarrage

  env = [
    "PORT=3000",
    "DATABASE_URL=postgres://${var.db_utilisateur}:${var.db_mot_de_passe}@${docker_container.postgres.name}:5432/${var.db_nom}",
  ]

  networks_advanced {
    name = var.reseau_frontal
  }

  networks_advanced {
    name = var.reseau_donnees
  }
}
