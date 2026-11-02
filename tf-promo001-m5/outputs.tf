output "url_livredor" {
  description = "Adresse du livre d'or via le proxy"
  value       = "http://127.0.0.1:${var.port_public}/"
}

output "url_statut" {
  description = "Adresse de la page de statut via le proxy"
  value       = "http://127.0.0.1:${var.port_public}/statut/"
}

output "conteneurs" {
  description = "Noms des conteneurs de la stack"
  value = {
    proxy    = docker_container.proxy.name
    livredor = module.livredor.nom_app
    postgres = module.livredor.nom_postgres
    statut   = module.statut.nom
  }
}

output "volume_donnees" {
  description = "Nom du volume PostgreSQL"
  value       = module.livredor.nom_volume
}
