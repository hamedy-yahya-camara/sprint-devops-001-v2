variable "nom_app" {
  type        = string
  description = "Nom Docker du conteneur applicatif"
}

variable "nom_postgres" {
  type        = string
  description = "Nom Docker du conteneur PostgreSQL"
}

variable "nom_volume" {
  type        = string
  description = "Nom du volume Docker de PostgreSQL"
}

variable "image_app" {
  type        = string
  description = "Reference de l'image applicative, presente sur le moteur Docker"
}

variable "image_postgres" {
  type        = string
  description = "Reference de l'image PostgreSQL transmise par la racine"
}

variable "reseau_frontal" {
  type        = string
  description = "Nom du reseau frontal, gere a la racine"
}

variable "reseau_donnees" {
  type        = string
  description = "Nom du reseau de donnees, gere a la racine"
}

variable "db_nom" {
  type        = string
  description = "Nom de la base"
}

variable "db_utilisateur" {
  type        = string
  description = "Utilisateur de la base"
}

variable "db_mot_de_passe" {
  type        = string
  sensitive   = true
  description = "Mot de passe de la base"
}

variable "redemarrage" {
  type        = string
  description = "Politique de redemarrage Docker des deux conteneurs"
  default     = "unless-stopped"
}
