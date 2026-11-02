variable "nom" {
  type        = string
  description = "Le nom reel du conteneur Docker"
}

variable "image" {
  type        = string
  description = "La reference exacte d'image transmise par la racine"
}

variable "reseau" {
  type        = string
  description = "Le nom du reseau deja gere a la racine"
}

variable "publier_port" {
  type        = bool
  default     = true
  description = "Publier le port sur l'hote (false = accessible seulement via le reseau Docker)"
}

variable "port" {
  type        = number
  default     = null
  description = "Le port externe, utilise seulement si publier_port est true"
}

variable "page" {
  type        = string
  description = "Le contenu exact de la page HTML"
}

variable "cle" {
  type        = string
  sensitive   = true
  description = "La cle factice CLE_CLIENT utilisee depuis la mission 2"
}

variable "redemarrage" {
  type        = string
  description = "La politique de redemarrage Docker"
}
