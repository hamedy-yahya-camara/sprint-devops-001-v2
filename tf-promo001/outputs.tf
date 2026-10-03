output "adresse" {
  value = local.adresse
}

output "identifiant" {
  value = docker_container.epreuve.id
}
output "cle" {
  value     = var.cle
  sensitive = true
}
