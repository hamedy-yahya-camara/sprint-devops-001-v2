output "nom" {
  value = docker_container.web.name
}

output "identifiant" {
  value = docker_container.web.id
}

output "adresse" {
  value = "http://localhost:${var.port}"
}
