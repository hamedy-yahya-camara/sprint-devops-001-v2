variable "boutiques" {
  type = map(object({
    nom  = string
    port = number
    page = string
  }))
  description = "Catalogue des boutiques. La cle est l'identite Terraform, nom est la valeur Docker."

  validation {
    condition     = alltrue([for b in var.boutiques : b.port == floor(b.port) && b.port >= 1024 && b.port <= 65535])
    error_message = "Chaque port du catalogue doit être un entier compris entre 1024 et 65535."
  }

  validation {
    condition     = length(distinct([for b in var.boutiques : b.port])) == length(var.boutiques)
    error_message = "Les ports du catalogue doivent être uniques : un port est utilisé par plusieurs boutiques."
  }

  validation {
    condition     = length(distinct([for b in var.boutiques : b.nom])) == length(var.boutiques)
    error_message = "Les noms Docker du catalogue doivent être uniques : un nom est utilisé par plusieurs boutiques."
  }
}
