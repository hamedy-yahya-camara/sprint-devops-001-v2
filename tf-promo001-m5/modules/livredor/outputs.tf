output "nom_app" {
  value = docker_container.app.name
}

output "id_app" {
  value = docker_container.app.id
}

output "nom_postgres" {
  value = docker_container.postgres.name
}

output "id_postgres" {
  value = docker_container.postgres.id
}

output "nom_volume" {
  value = docker_volume.pgdata.name
}
