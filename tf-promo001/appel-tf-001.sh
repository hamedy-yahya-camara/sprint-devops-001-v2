#!/usr/bin/env bash
# ==============================================================
# OPERATION APPEL D'OFFRES
# Mission 1, Semaine Terraform, sprint DevOps MeggieOnTheStack, Promo 001
# ==============================================================
#
# A lancer SANS sudo, DANS ton dossier Terraform (celui de tes fichiers .tf) :
#
#   cd ~/tf-promo001
#   bash ~/Downloads/appel-tf-001.sh
#
# Ce script dit en toutes lettres ce qu'il touche.
# Il LIT : ton state (terraform state list / state show), ton plan
# (terraform plan, qui ne modifie rien), tes fichiers (terraform fmt -check,
# terraform validate) et Docker (docker inspect, docker ps).
# Il ECRIT un seul fichier, .appel-tf-001, dans ton dossier, pour se souvenir
# du cahier des charges et de ton avancement. Rien d'autre.
# Il ne cree rien, ne modifie rien dans Docker, ne touche pas a tes .tf.
# Relance-le autant de fois que tu veux, il reprend ou tu en etais.
#   bash appel-tf-001.sh reset    efface le cahier des charges, en grave un neuf.
#
# Le principe. Un client publie un cahier des charges grave pour toi.
# Tu livres en Terraform, uniquement. Le controleur de conformite verifie
# a trois etages : le cahier des charges, ta memoire Terraform, Docker en vrai.
# Quatre actes. La livraison, l'avenant, l'exploitation, la reception.
# Le code de mission est encode pour ne pas te spoiler si tu lis ce fichier.
#

set -u
LC_ALL=C
export LC_ALL

CODE_B64="VFUtREVDUklTLVRVLU4tT1JET05ORVMtUExVUy0yMDI2"
SPEC=".appel-tf-001"
PAGE_DIR="/usr/share/nginx/html"

# 0. Pas de sudo ici
if [ "$(id -u)" -eq 0 ]; then
  echo "STOP. Pas de sudo pour cette epreuve. Relance simplement : bash appel-tf-001.sh"
  exit 1
fi

# 1. Les outils repondent ?
for outil in terraform docker; do
  if ! command -v "$outil" >/dev/null 2>&1; then
    echo "$outil est introuvable dans ce terminal."
    echo "Sur Windows, lance ce script dans WSL ou Git Bash, avec terraform et docker qui repondent DEDANS."
    exit 1
  fi
done
if ! docker ps >/dev/null 2>&1; then
  echo "Docker ne repond pas. docker ps doit marcher avant l'epreuve. Le ticket d'entree est epingle dans #le-lab."
  exit 1
fi

# 2. On est dans un dossier Terraform ?
if ! ls ./*.tf >/dev/null 2>&1; then
  echo "Aucun fichier .tf ici. Ce script se lance DANS ton dossier Terraform :"
  echo "  cd ~/tf-promo001"
  echo "  bash ~/Downloads/appel-tf-001.sh"
  exit 1
fi
if [ ! -d .terraform ]; then
  echo "Pas de dossier .terraform ici. Ton dossier n'est pas initialise, ou tu n'es pas dans le bon. terraform init d'abord."
  exit 1
fi

# --------------------------------------------------------------
# Outils du controleur
# --------------------------------------------------------------

MOTS="acier ambre basalte cedre cobalt corail ebene granit indigo jade lilas nacre ocre onyx opale quartz safran sepia topaze zinc"

mot_au_hasard() {
  n=$(echo "$MOTS" | wc -w | tr -d ' ')
  i=$(( ( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % n ) + 1 ))
  echo "$MOTS" | tr ' ' '\n' | sed -n "${i}p"
}

port_libre() {
  while :; do
    p=$(( 8100 + ( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 100 ) ))
    if docker ps --format '{{.Ports}}' | grep -q ":${p}->"; then continue; fi
    if [ -f "$SPEC" ] && grep -qE "^port2?=${p}$" "$SPEC"; then continue; fi
    echo "$p"; return
  done
}

serial_state() {
  [ -f terraform.tfstate ] || { echo 0; return; }
  grep -m1 -oE '"serial": *[0-9]+' terraform.tfstate | grep -oE '[0-9]+'
}

adresse_par_nom() {
  type="$1"; valeur="$2"
  for a in $(terraform state list 2>/dev/null | grep "^${type}\."); do
    n=$(terraform state show "$a" 2>/dev/null | grep -m1 -E '^ *name *=' | sed -E 's/.*= *"([^"]*)".*/\1/')
    if [ "$n" = "$valeur" ]; then echo "$a"; return 0; fi
  done
  return 1
}

attribut() { terraform state show "$1" 2>/dev/null | grep -m1 -E "^ *$2 *=" | sed -E 's/.*= *"?([^"]*)"?.*/\1/'; }

lire_page() {
  port="$1"; nom="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -s --max-time 5 "http://localhost:${port}/" 2>/dev/null && return
  fi
  docker exec "$nom" wget -qO- "http://localhost/" 2>/dev/null
}

plan_vide() {
  terraform plan -detailed-exitcode -input=false -no-color >/dev/null 2>&1
  [ $? -eq 0 ]
}

sauve() { grep -v "^$1=" "$SPEC" 2>/dev/null > "$SPEC.tmp"; echo "$1=$2" >> "$SPEC.tmp"; mv "$SPEC.tmp" "$SPEC"; }
lit() { grep -m1 "^$1=" "$SPEC" 2>/dev/null | cut -d= -f2-; }

echec() {
  echo ""
  echo "NON CONFORME. $1"
  echo "Piste : $2"
  echo ""
  echo "Corrige, puis relance : bash appel-tf-001.sh"
  exit 3
}

duree() {
  debut=$(lit debut); fin=$(lit fin); [ -n "$fin" ] || fin=$(date +%s); s=$(( fin - debut ))
  printf '%dh%02d' $(( s / 3600 )) $(( (s % 3600) / 60 ))
}

if [ "${1:-}" = "reset" ]; then
  rm -f "$SPEC"
  echo "Cahier des charges efface. Relance sans argument pour en recevoir un neuf."
  echo "Pense a detruire ce que tu avais livre, ou a le renommer, le nouveau client ne le connait pas."
  exit 0
fi

if [ ! -f "$SPEC" ]; then
  mot=$(mot_au_hasard)
  sauve mot "$mot"
  sauve reseau "promo001-${mot}"
  sauve conteneur "boutique-${mot}"
  sauve port "$(port_libre)"
  sauve phrase "Chantier ${mot} ouvert le $(date +%d/%m) a $(date +%H:%M)"
  sauve etape 1
  sauve debut "$(date +%s)"
fi

RESEAU=$(lit reseau); CONTENEUR=$(lit conteneur); PORT=$(lit port); PHRASE=$(lit phrase); ETAPE=$(lit etape); MOT=$(lit mot)

echo "=============================================================="
echo " OPERATION APPEL D'OFFRES, Promo 001, Terraform mission 1"
echo "=============================================================="

controle() {
  port_attendu="$1"; phrase_attendue="$2"
  echo ""
  echo "Le controleur de conformite passe. Il lit ta memoire, puis Docker."

  a_res=$(adresse_par_nom docker_network "$RESEAU") || echec "Aucune ressource docker_network nommee ${RESEAU} dans ta memoire Terraform." "Le cahier des charges demande un bloc resource docker_network avec name = \"${RESEAU}\". Ecris-le, plan, apply."
  echo "  reseau ${RESEAU} : present dans le state ($a_res)"

  a_con=$(adresse_par_nom docker_container "$CONTENEUR") || echec "Aucune ressource docker_container nommee ${CONTENEUR} dans ta memoire Terraform." "Un docker run ne laisse rien dans le state. Le conteneur doit naitre d'un bloc resource docker_container avec name = \"${CONTENEUR}\"."
  id_state=$(attribut "$a_con" id)
  ext=$(terraform state show "$a_con" 2>/dev/null | grep -m1 -E '^ *external *=' | grep -oE '[0-9]+')
  [ "$ext" = "$port_attendu" ] || echec "Le state publie le port ${ext:-aucun}, le cahier des charges exige ${port_attendu}." "Le bloc ports du conteneur, external = ${port_attendu}, internal = 80. Puis plan, et lis ce qu'il annonce avant apply."
  echo "  conteneur ${CONTENEUR} : present dans le state, port ${ext}"

  id_docker=$(docker inspect -f '{{.Id}}' "$CONTENEUR" 2>/dev/null) || echec "Docker ne connait aucun conteneur ${CONTENEUR}." "Ta memoire dit qu'il existe, Docker dit non. terraform plan te dira ce qu'il manque."
  [ "$id_docker" = "$id_state" ] || echec "Le conteneur qui tourne n'est pas celui de ta memoire Terraform (identifiants differents)." "Quelqu'un l'a cree a la main. Terraform ne possede pas ce qu'il n'a pas cree. docker rm -f, puis apply."
  etat=$(docker inspect -f '{{.State.Running}}' "$CONTENEUR")
  [ "$etat" = "true" ] || echec "Le conteneur ${CONTENEUR} existe mais ne tourne pas." "docker logs ${CONTENEUR}, puis regarde ton port et ton image."
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$CONTENEUR" | grep -qw "$RESEAU" || echec "Le conteneur n'est pas branche sur le reseau ${RESEAU}." "Le bloc networks_advanced du conteneur, avec une reference vers ta ressource reseau, pas un texte recopie."
  echo "  Docker : le conteneur tourne, meme identifiant que le state, branche sur ${RESEAU}"

  page=$(lire_page "$port_attendu" "$CONTENEUR")
  echo "$page" | grep -qF "$phrase_attendue" || echec "La page servie sur le port ${port_attendu} ne contient pas la phrase exigee." "La phrase, mot pour mot, espaces et virgules compris : ${phrase_attendue}"
  echo "  page : la phrase du client est servie sur le port ${port_attendu}"

  plan_vide || echec "terraform plan annonce encore des changements, ou echoue." "Un apply a ete oublie, ou un fichier a ete modifie apres. terraform plan, lis-le, apply."
  echo "  plan : No changes, ton fichier, ta memoire et Docker sont d'accord"
}

montage_page() {
  docker inspect -f '{{range .Mounts}}{{.Type}}:{{.Destination}} {{end}}' "$CONTENEUR" 2>/dev/null | tr ' ' '\n' | grep -qE "^bind:${PAGE_DIR}(/index\.html)?$"
}

if [ "$ETAPE" = "1" ]; then
  echo ""
  echo "ACTE 1. LA LIVRAISON. Le client publie son cahier des charges, grave pour toi :"
  echo ""
  echo "   un reseau Docker nomme        ${RESEAU}"
  echo "   un conteneur nginx nomme      ${CONTENEUR}"
  echo "   qui publie son port 80 sur    ${PORT}"
  echo "   branche sur ce reseau, et dont la page d'accueil contient, mot pour mot :"
  echo "   ${PHRASE}"
  echo ""
  echo "Tu livres en Terraform, uniquement. Ajoute ces ressources a ton dossier,"
  echo "plan, apply, puis relance ce script pour la visite du controleur."
  echo "Ta boutique de la journee peut rester debout, le client n'y touche pas."
  echo ""
  if ! adresse_par_nom docker_container "$CONTENEUR" >/dev/null 2>&1; then
    if docker inspect "$CONTENEUR" >/dev/null 2>&1; then
      echo "Docker connait un conteneur nomme ${CONTENEUR}. Ta memoire Terraform, non."
      echo "Un docker run ne compte pas. Le client veut du code. docker rm -f, puis un bloc resource."
      exit 3
    fi
    echo "Rien de livre pour l'instant. A toi."
    exit 0
  fi
  controle "$PORT" "$PHRASE"
  sauve id_acte1 "$(docker inspect -f '{{.Id}}' "$CONTENEUR")"
  sauve serial_acte1 "$(serial_state)"
  NOUVEAU=$(port_libre)
  sauve port2 "$NOUVEAU"
  sauve etape 2
  echo ""
  echo "CONFORME. Livraison acceptee, $(date +%H:%M)."
  echo ""
  echo "ACTE 2. L'AVENANT. Le client change d'avis sur un detail :"
  echo ""
  echo "   le conteneur ${CONTENEUR} doit maintenant publier son port 80 sur ${NOUVEAU}"
  echo ""
  echo "Tout le reste ne bouge pas. Tu sais depuis le temps 5 ce que ce detail"
  echo "provoque. Lis ton plan avant d'appliquer, garde-en une capture, puis relance ce script."
  exit 0
fi

if [ "$ETAPE" = "2" ]; then
  PORT2=$(lit port2)
  echo ""
  echo "ACTE 2. L'AVENANT : ${CONTENEUR} sur le port ${PORT2}. Le controleur repasse."
  controle "$PORT2" "$PHRASE"
  id_now=$(docker inspect -f '{{.Id}}' "$CONTENEUR")
  [ "$id_now" != "$(lit id_acte1)" ] || echec "Le conteneur est le meme qu'a l'acte 1, identifiant identique." "Un port ne se modifie pas sur place. Le plan devait dire must be replaced. Relis-le."
  echo "  identifiant : un conteneur NEUF, le remplacant, pas l'ancien"
  s_now=$(serial_state)
  [ "$s_now" -gt "$(lit serial_acte1)" ] 2>/dev/null || echec "Le serial du state n'a pas avance depuis l'acte 1." "Chaque apply qui change quelque chose fait avancer le serial. Le tien est reste a $(lit serial_acte1)."
  echo "  state : serial $(lit serial_acte1) puis ${s_now}, la memoire a avance"
  sauve serial_acte2 "$s_now"
  sauve phrase3 "Chantier ${MOT}, deuxieme jour, ouvert a $(date +%H:%M)"
  sauve etape 3
  echo ""
  echo "CONFORME. Avenant execute, $(date +%H:%M)."
  echo ""
  echo "ACTE 3. L'EXPLOITATION. Le client a une exigence nouvelle, et c'est la plus dure."
  echo ""
  echo "   Il veut changer la phrase de sa page tous les jours, lui-meme, sans toi,"
  echo "   sans apply, et sans que la boutique ferme une seule seconde."
  echo ""
  echo "   Avec ton bloc upload, c'est impossible, tu l'as vu au temps 5, changer la page"
  echo "   remplace le conteneur. Le client exige donc que la page vive HORS du conteneur,"
  echo "   dans un dossier de TA machine, et que le conteneur la lise en direct."
  echo "   Le provider sait faire ca. La page docker_container de la doc le dit."
  echo "   Deux blocs differents y menent, l'un ou l'autre convient."
  echo ""
  echo "   Premiere phrase a servir, mot pour mot :"
  echo "   $(lit phrase3)"
  echo ""
  echo "Refais ta livraison avec la page hors du conteneur, puis relance ce script."
  echo "Le controleur te donnera ensuite une DEUXIEME phrase, et la, interdiction d'apply."
  exit 0
fi

if [ "$ETAPE" = "3" ]; then
  PORT2=$(lit port2)
  echo ""
  echo "ACTE 3. L'EXPLOITATION, premier passage. Le controleur repasse."
  controle "$PORT2" "$(lit phrase3)"
  montage_page || echec "La page est servie, mais elle vit ENCORE dans le conteneur." "Le controleur ne voit aucun montage de ta machine vers ${PAGE_DIR}. Cherche sur la page docker_container comment brancher un dossier de ta machine dans le conteneur, et retire le bloc upload."
  echo "  montage : la page vit sur ta machine, le conteneur la lit en direct"
  sauve id_acte3 "$(docker inspect -f '{{.Id}}' "$CONTENEUR")"
  sauve serial_acte3 "$(serial_state)"
  sauve phrase4 "Chantier ${MOT}, troisieme jour, ouvert a $(date +%H:%M)"
  sauve etape 4
  echo ""
  echo "CONFORME. Exploitation en place, $(date +%H:%M)."
  echo ""
  echo "Le client prend la main. Deuxieme phrase, mot pour mot :"
  echo "   $(lit phrase4)"
  echo ""
  echo "Regle : PAS de terraform apply, PAS de docker exec, PAS de docker cp. Le client ne"
  echo "connait rien de tout ca. Il edite un fichier sur sa machine, et la page change."
  echo "Fais comme lui, puis relance ce script. Le controleur verifiera que le conteneur"
  echo "est le MEME, que la memoire n'a pas bouge, et que la phrase est servie."
  exit 0
fi

if [ "$ETAPE" = "4" ]; then
  PORT2=$(lit port2)
  echo ""
  echo "ACTE 3. L'EXPLOITATION, second passage. Le client a change sa phrase, le controleur verifie."
  controle "$PORT2" "$(lit phrase4)"
  id_now=$(docker inspect -f '{{.Id}}' "$CONTENEUR")
  [ "$id_now" = "$(lit id_acte3)" ] || echec "Le conteneur a ete remplace, l'identifiant a change." "Le client n'a pas le droit de fermer la boutique. La page doit changer sans toucher au conteneur."
  echo "  identifiant : le MEME conteneur, la boutique n'a pas ferme"
  s_now=$(serial_state)
  [ "$s_now" = "$(lit serial_acte3)" ] || echec "Le serial du state a bouge, il y a eu un apply." "Le client ne connait pas Terraform. Il edite un fichier, rien d'autre."
  echo "  state : serial inchange, aucun apply, Terraform n'a rien eu a faire"
  montage_page || echec "Le montage a disparu." "La page doit rester hors du conteneur."
  sauve etape 5
  echo ""
  echo "CONFORME. Le client est autonome, $(date +%H:%M)."
fi

echo ""
echo "ACTE 4. LA RECEPTION. Le controleur ouvre tes fichiers .tf."
echo "Il exige deux choses que la mission ne t'a jamais ecrites."
echo ""
if ! terraform fmt -check -recursive >/dev/null 2>&1; then
  echo "  mise en forme : REFUSEE. Un ou plusieurs fichiers ne sont pas au format standard."
  echo "  Piste : il existe une commande terraform qui range tes fichiers au millimetre. Deux mots. L'aide integree la liste."
  exit 3
fi
echo "  mise en forme : conforme, tes fichiers sont au format standard"
if ! terraform validate -no-color >/dev/null 2>&1; then
  echo "  grammaire : REFUSEE. La configuration ne passe pas la verification."
  echo "  Piste : il existe une commande terraform qui verifie ta grammaire sans rien creer. Deux mots. Lance-la, elle te dira la ligne."
  exit 3
fi
echo "  grammaire : conforme, la configuration est valide"

if [ "$(lit etape)" != "6" ]; then
  sauve etape 6
  sauve fin "$(date +%s)"
fi

echo ""
echo "=============================================================="
echo " PROCES-VERBAL DE RECEPTION"
echo "=============================================================="
echo " Cahier des charges : ${RESEAU}, ${CONTENEUR}, port ${PORT} puis $(lit port2)"
echo " Livraison          : conforme aux trois etages, cahier, state, Docker"
echo " Avenant            : conteneur remplace, serial $(lit serial_acte1) puis $(lit serial_acte2)"
echo " Exploitation       : page hors du conteneur, phrase changee sans apply, serial fige a $(lit serial_acte3)"
echo " Reception          : fichiers formates, configuration valide"
echo " Duree totale       : $(duree)"
echo ""
echo " Tu n'as pas ordonne. Tu as decrit, et le monde a suivi."
echo ""
echo " CODE DE MISSION : $(printf '%s' "$CODE_B64" | base64 -d 2>/dev/null || printf '%s' "$CODE_B64" | base64 -D)"
echo "=============================================================="
echo ""
echo "Recopie le proces-verbal EN ENTIER dans ton compte rendu, section 10, avec tout ce que la mission demande pour l'epreuve."
echo "Ta boutique de l'epreuve peut rester debout, ou partir avec terraform destroy. A toi de voir."
exit 0
