variable "prefixe" {
  type        = string
  description = "Prefixe de tous les objets de la mission"
  default     = "m5-hamedy"
}

variable "port_public" {
  type        = number
  description = "Port public du proxy sur 127.0.0.1"
  default     = 8180
}

variable "image_app" {
  type        = string
  description = "Image applicative du livre d'or, construite en local"
  default     = "livredor-m5:v1"
}

variable "image_postgres" {
  type        = string
  description = "Image PostgreSQL"
  default     = "postgres:16-alpine"
}

variable "image_nginx" {
  type        = string
  description = "Image nginx du proxy et de la page de statut"
  default     = "nginx:1.27-alpine"
}

variable "db_nom" {
  type        = string
  description = "Nom de la base"
  default     = "livredor"
}

variable "db_utilisateur" {
  type        = string
  description = "Utilisateur de la base"
  default     = "livredor"
}

variable "db_mot_de_passe" {
  type        = string
  sensitive   = true
  description = "Mot de passe d'essai de la base, alphanumerique, jamais dans le depot"
}
