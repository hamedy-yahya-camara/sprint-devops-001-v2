output "adresse" {
  value = module.boutiques["origine"].adresse
}

output "identifiant" {
  value = module.boutiques["origine"].identifiant
}

output "cle" {
  value     = var.cle
  sensitive = true
}

output "boutiques" {
  value = {
    for cle, boutique in module.boutiques : cle => {
      nom         = boutique.nom
      identifiant = boutique.identifiant
      adresse     = boutique.adresse
    }
  }
}
