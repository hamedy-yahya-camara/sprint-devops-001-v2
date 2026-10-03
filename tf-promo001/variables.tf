variable "port" {
  type        = number
  description = "Port de ta machine sur lequel la boutique est publiee"

  validation {
    condition     = var.port >= 8100 && var.port <= 8199
    error_message = "Le port doit etre compris entre 8100 et 8199 inclus."
  }
}

variable "reseau" {
  type        = string
  description = "Nom Docker du reseau"
}

variable "conteneur" {
  type        = string
  description = "Nom Docker du conteneur"
}

variable "message" {
  type        = string
  description = "Phrase affichee sur la page"
}

variable "image" {
  type    = string
  default = "nginx:1.27-alpine"
}
locals {
  adresse = "http://localhost:${var.port}"
  page    = "<h1>${var.message}</h1><p>Boutique sur ${local.adresse}</p>"
}
variable "cle" {
  type      = string
  sensitive = true
}
