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

variable "port" {
  type        = number
  description = "Le port externe de la boutique"
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
