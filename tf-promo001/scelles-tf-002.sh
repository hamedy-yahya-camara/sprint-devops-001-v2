#!/usr/bin/env bash
# ==============================================================
# OPERATION SCELLES
# Mission 2, Semaine Terraform, sprint DevOps MeggieOnTheStack, Promo 001
# ==============================================================
#
# A lancer SANS sudo, DANS ton dossier Terraform (celui de tes fichiers .tf) :
#
#   cd ~/tf-promo001
#   bash ~/Downloads/scelles-tf-002.sh
#
# Ce script dit en toutes lettres ce qu'il touche.
# Il LIT : tes fichiers .tf et .tfvars (pour en calculer une empreinte et y
# chercher des valeurs), ton state (terraform state list / show / pull), tes
# sorties (terraform output -json), tes plans (terraform plan, qui ne modifie
# rien, parfois avec une option -var pour te tester) et Docker (docker inspect).
# Pour l'audit, il COPIE tes fichiers .tf dans un dossier temporaire, y lance
# un plan, puis efface ce dossier. Ton dossier a toi n'est pas touche.
# Il ECRIT un seul fichier, .scelles-tf-002, dans ton dossier, pour se souvenir
# du cahier des charges, des scelles et de ton avancement. Rien d'autre.
# Il ne cree rien, ne modifie rien dans Docker, ne touche ni a tes .tf ni a
# tes .tfvars ni a ton state.
# Relance-le autant de fois que tu veux, il reprend ou tu en etais.
#   bash scelles-tf-002.sh reset    efface le cahier des charges, en grave un neuf.
#
# Le principe. Le client grave un cahier des charges. Tu livres en Terraform,
# avec des valeurs qui vivent HORS du code. Une fois la livraison acceptee, le
# controleur pose les scelles sur tes fichiers .tf. A partir de la, seules les
# valeurs ont le droit de bouger. Quatre actes. La livraison et les scelles,
# l'avenant par telephone, l'audit a blanc, le secret et la signature.
# Le code de mission est encode pour ne pas te spoiler si tu lis ce fichier.
#

set -u
LC_ALL=C
export LC_ALL

CODE_B64="TEUtQ09ERS1TT1VTLVNDRUxMRVMtTEVTLVZBTEVVUlMtTElCUkVTLTIwMjY="
SPEC=".scelles-tf-002"
ENVNOM="CLE_CLIENT"

# 0. Pas de sudo ici
if [ "$(id -u)" -eq 0 ]; then
  echo "STOP. Pas de sudo pour cette epreuve. Relance simplement : bash scelles-tf-002.sh"
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
  echo "  bash ~/Downloads/scelles-tf-002.sh"
  exit 1
fi
if [ ! -d .terraform ]; then
  echo "Pas de dossier .terraform ici. Ton dossier n'est pas initialise, ou tu n'es pas dans le bon. terraform init d'abord."
  exit 1
fi

# --------------------------------------------------------------
# Outils du controleur
# --------------------------------------------------------------

MOTS="amande anis basilic cannelle cumin fenouil gingembre laurier menthe muscade origan paprika piment romarin sauge sesame thym vanille verveine"

mot_au_hasard() {
  n=$(echo "$MOTS" | wc -w | tr -d ' ')
  i=$(( ( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % n ) + 1 ))
  echo "$MOTS" | tr ' ' '\n' | sed -n "${i}p"
}

hexa() { od -An -N2 -tx1 /dev/urandom | tr -d ' \n'; }

port_libre() {
  # entre 8101 et 8198, un port qu'aucun conteneur ne publie, different de ceux deja graves
  while :; do
    p=$(( 8101 + ( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 98 ) ))
    if docker ps --format '{{.Ports}}' | grep -q ":${p}->"; then continue; fi
    if [ -f "$SPEC" ] && grep -qE "^port2?=${p}$" "$SPEC"; then continue; fi
    echo "$p"; return
  done
}

serial_state() {
  [ -f terraform.tfstate ] || { echo 0; return; }
  grep -m1 -oE '"serial": *[0-9]+' terraform.tfstate | grep -oE '[0-9]+'
}

# adresse dans le state d'une ressource TYPE dont l'attribut name vaut VALEUR
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

# 0 = plan vide, 2 = changements, 1 = erreur
etat_plan() {
  terraform plan -detailed-exitcode -input=false -no-color >/dev/null 2>&1
  echo $?
}

empreinte() { # empreinte des fichiers passes en argument, dans l'ordre alphabetique
  if command -v sha256sum >/dev/null 2>&1; then
    ls "$@" 2>/dev/null | sort | xargs cat 2>/dev/null | sha256sum | cut -c1-64
  else
    ls "$@" 2>/dev/null | sort | xargs cat 2>/dev/null | shasum -a 256 | cut -c1-64
  fi
}
empreinte_code()    { empreinte ./*.tf; }
empreinte_valeurs() {
  n=$(ls ./*.tfvars ./*.tfvars.json 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then empreinte ./*.tfvars ./*.tfvars.json; else echo "aucun"; fi
}

md5_de() {
  if command -v md5sum >/dev/null 2>&1; then printf '%s' "$1" | md5sum | cut -c1-32
  else printf '%s' "$1" | md5 | cut -c1-32; fi
}

sauve() { # cle valeur
  grep -v "^$1=" "$SPEC" 2>/dev/null > "$SPEC.tmp"; echo "$1=$2" >> "$SPEC.tmp"; mv "$SPEC.tmp" "$SPEC"
}
lit() { grep -m1 "^$1=" "$SPEC" 2>/dev/null | cut -d= -f2-; }

echec() {
  echo ""
  echo "NON CONFORME. $1"
  echo "Piste : $2"
  echo ""
  echo "Corrige, puis relance : bash scelles-tf-002.sh"
  exit 3
}

duree() {
  debut=$(lit debut); fin=$(lit fin); [ -n "$fin" ] || fin=$(date +%s); s=$(( fin - debut ))
  printf '%dh%02d' $(( s / 3600 )) $(( (s % 3600) / 60 ))
}

demande() { # question -> reponse sur stdout
  printf '%s ' "$1" >&2
  if [ -t 0 ]; then read -r rep
  elif ( : < /dev/tty ) 2>/dev/null; then read -r rep < /dev/tty
  else read -r rep; fi
  printf '%s' "$rep" | tr -d ' \r'
}

# --------------------------------------------------------------
# Reset
# --------------------------------------------------------------
if [ "${1:-}" = "reset" ]; then
  rm -f "$SPEC"
  echo "Cahier des charges efface. Relance sans argument pour en recevoir un neuf."
  echo "Pense a detruire ce que tu avais livre, ou a le renommer, le nouveau client ne le connait pas."
  exit 0
fi

# --------------------------------------------------------------
# Le cahier des charges (grave une seule fois)
# --------------------------------------------------------------
if [ ! -f "$SPEC" ]; then
  mot=$(mot_au_hasard)
  sauve mot "$mot"
  sauve reseau "promo001-${mot}"
  sauve conteneur "boutique-${mot}"
  sauve port "$(port_libre)"
  sauve phrase "Scelles ${mot} poses le $(date +%d/%m) a $(date +%H:%M)"
  sauve cle "CLE-${mot}-$(hexa)"
  sauve etape 1
  sauve debut "$(date +%s)"
fi

RESEAU=$(lit reseau); CONTENEUR=$(lit conteneur); PORT=$(lit port); PHRASE=$(lit phrase); CLE=$(lit cle); ETAPE=$(lit etape); MOT=$(lit mot)

echo "=============================================================="
echo " OPERATION SCELLES, Promo 001, Terraform mission 2"
echo "=============================================================="

# --------------------------------------------------------------
# Verification commune : le cahier des charges est-il conforme ?
#   $1 = port attendu, $2 = phrase attendue, $3 = "plan" pour exiger un plan vide
# --------------------------------------------------------------
controle() {
  port_attendu="$1"; phrase_attendue="$2"; exige_plan="${3:-plan}"
  echo ""
  echo "Le controleur de conformite passe. Il lit ta memoire, puis Docker."

  a_res=$(adresse_par_nom docker_network "$RESEAU") || echec "Aucune ressource docker_network nommee ${RESEAU} dans ta memoire Terraform." "Le cahier des charges demande un reseau nomme ${RESEAU}. Son nom vient d'une variable, pas d'un texte dans le .tf."
  echo "  reseau ${RESEAU} : present dans le state ($a_res)"

  a_con=$(adresse_par_nom docker_container "$CONTENEUR") || echec "Aucune ressource docker_container nommee ${CONTENEUR} dans ta memoire Terraform." "Un docker run ne laisse rien dans le state. Le conteneur doit naitre d'un bloc resource docker_container, et son nom d'une variable."
  id_state=$(attribut "$a_con" id)
  ext=$(terraform state show "$a_con" 2>/dev/null | grep -m1 -E '^ *external *=' | grep -oE '[0-9]+')
  [ "$ext" = "$port_attendu" ] || echec "Le state publie le port ${ext:-aucun}, le cahier des charges exige ${port_attendu}." "external doit valoir ${port_attendu}, par une variable. Puis plan, et lis ce qu'il annonce avant apply."
  echo "  conteneur ${CONTENEUR} : present dans le state, port ${ext}"

  id_docker=$(docker inspect -f '{{.Id}}' "$CONTENEUR" 2>/dev/null) || echec "Docker ne connait aucun conteneur ${CONTENEUR}." "Ta memoire dit qu'il existe, Docker dit non. terraform plan te dira ce qu'il manque."
  [ "$id_docker" = "$id_state" ] || echec "Le conteneur qui tourne n'est pas celui de ta memoire Terraform (identifiants differents)." "Quelqu'un l'a cree a la main. Terraform ne possede pas ce qu'il n'a pas cree. docker rm -f, puis apply."
  etat=$(docker inspect -f '{{.State.Running}}' "$CONTENEUR")
  [ "$etat" = "true" ] || echec "Le conteneur ${CONTENEUR} existe mais ne tourne pas." "docker logs ${CONTENEUR}, puis regarde ton port et ton image."
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$CONTENEUR" | grep -qw "$RESEAU" || echec "Le conteneur n'est pas branche sur le reseau ${RESEAU}." "Le bloc networks_advanced du conteneur, avec une reference vers ta ressource reseau."
  echo "  Docker : le conteneur tourne, meme identifiant que le state, branche sur ${RESEAU}"

  docker inspect -f '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$CONTENEUR" | grep -qxF "${ENVNOM}=${CLE}" || echec "Le conteneur ne porte pas la variable d'environnement ${ENVNOM} avec la cle du client." "La page docker_container du provider a un argument pour les variables d'environnement. La cle vient d'une variable Terraform, jamais d'un texte dans le .tf."
  echo "  environnement : ${ENVNOM} est dans le conteneur, avec la bonne cle"

  page=$(lire_page "$port_attendu" "$CONTENEUR")
  echo "$page" | grep -qF "$phrase_attendue" || echec "La page servie sur le port ${port_attendu} ne contient pas la phrase exigee." "La phrase, mot pour mot, espaces et virgules compris : ${phrase_attendue}"
  echo "  page : la phrase du client est servie sur le port ${port_attendu}"

  if [ "$exige_plan" = "plan" ]; then
    [ "$(etat_plan)" = "0" ] || echec "terraform plan annonce encore des changements, ou echoue." "Un apply a ete oublie, ou une valeur differe entre ton fichier de valeurs et ta memoire. terraform plan, lis-le."
    echo "  plan : No changes, tes fichiers, ta memoire et Docker sont d'accord"
  fi
}

# les cinq valeurs du client ne doivent apparaitre dans AUCUN .tf
litteraux_absents() {
  for v in "$RESEAU" "$CONTENEUR" "$PORT" "$PHRASE" "$CLE"; do
    f=$(grep -lF -- "$v" ./*.tf 2>/dev/null | head -1)
    [ -z "$f" ] || echec "La valeur « ${v} » est ecrite en dur dans ${f}." "Le client veut du code reutilisable. Cette valeur vit dans un fichier de valeurs, et le .tf ne connait que la variable."
  done
  echo "  code : aucune des cinq valeurs du client n'est ecrite dans un .tf"
}

# les sorties : adresse, identifiant, cle protegee
sorties_conformes() {
  port_attendu="$1"
  js=$(terraform output -json 2>/dev/null | tr -d '\n ')
  [ -n "$js" ] && [ "$js" != "{}" ] || echec "terraform output ne rend aucune sortie." "Le client veut lire trois choses sans ouvrir ton state. Un bloc output par chose. La page Output Values du langage."
  echo "$js" | grep -qF "\"value\":\"http://localhost:${port_attendu}\"" || echec "Aucune sortie ne vaut exactement http://localhost:${port_attendu}." "L'adresse se construit depuis la variable du port, pas a la main. Un local, puis un output."
  id_docker=$(docker inspect -f '{{.Id}}' "$CONTENEUR" 2>/dev/null)
  echo "$js" | grep -qF "\"value\":\"${id_docker}\"" || echec "Aucune sortie ne vaut l'identifiant complet du conteneur ${CONTENEUR}." "L'identifiant est un attribut de ta ressource conteneur. Un output qui le reference."
  bloc_cle=$(echo "$js" | grep -oE '\{[^{}]*\}' | grep -F "\"value\":\"${CLE}\"" | head -1)
  [ -n "$bloc_cle" ] || echec "Aucune sortie ne rend la cle du client." "Le client veut pouvoir relire sa cle. Un output qui reference la variable de la cle."
  echo "$bloc_cle" | grep -qF '"sensitive":true' || echec "La sortie qui rend la cle n'est pas protegee." "Terraform lui-meme te l'aurait refuse si ta variable etait bien declaree. La page Input Variables du langage, cherche comment marquer une valeur."
  echo "  sorties : adresse, identifiant et cle protegee, les trois sont la"
}

# --------------------------------------------------------------
# Acte 1, la livraison et les scelles
# --------------------------------------------------------------
if [ "$ETAPE" = "1" ]; then
  echo ""
  echo "ACTE 1. LA LIVRAISON. Le client publie son cahier des charges, grave pour toi :"
  echo ""
  echo "   un reseau Docker nomme          ${RESEAU}"
  echo "   un conteneur nginx nomme        ${CONTENEUR}"
  echo "   qui publie son port 80 sur      ${PORT}"
  echo "   branche sur ce reseau, dont la page d'accueil contient, mot pour mot :"
  echo "   ${PHRASE}"
  echo "   et qui recoit, dans une variable d'environnement nommee ${ENVNOM}, la cle :"
  echo "   ${CLE}"
  echo ""
  echo "Les regles du client, et elles sont fermes :"
  echo "   1. AUCUNE de ces cinq valeurs n'a le droit d'apparaitre dans un fichier .tf."
  echo "      Elles vivent dans un fichier de valeurs. Le code ne connait que des variables."
  echo "   2. Un port hors de 8100 a 8199 doit etre REFUSE par ton code, avant tout plan."
  echo "   3. Trois sorties : l'adresse http://localhost:${PORT} construite depuis le port,"
  echo "      l'identifiant complet du conteneur, et la cle, protegee."
  echo ""
  echo "Tu livres en Terraform. Plan, apply, puis relance ce script pour la visite du controleur."
  echo "Une fois la livraison acceptee, le controleur pose les SCELLES sur tes fichiers .tf."
  echo "Range tes fichiers AVANT, avec la commande d'hier. Apres les scelles, tout compte, meme un espace."
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
  echo "Le controleur ouvre d'abord tes fichiers .tf."
  litteraux_absents
  controle "$PORT" "$PHRASE" sansplan
  sorties_conformes "$PORT"
  [ "$(etat_plan)" = "0" ] || echec "terraform plan annonce encore des changements, ou echoue." "Lance terraform plan et lis-le. Un apply oublie, une valeur qui differe entre ton fichier de valeurs et ta memoire, ou une erreur que Terraform t'explique en entier."
  echo "  plan : No changes, tes fichiers, ta memoire et Docker sont d'accord"
  terraform fmt -check -recursive >/dev/null 2>&1 || echec "Le controleur ne pose pas de scelles sur des fichiers mal ranges." "Tu connais la commande depuis hier, elle range aussi les .tfvars. Lance-la MAINTENANT, avant les scelles. Apres, le moindre caractere qui bouge dans un .tf les brise."
  echo "  mise en forme : fichiers ranges, les scelles peuvent etre poses"
  sauve id_acte1 "$(docker inspect -f '{{.Id}}' "$CONTENEUR")"
  sauve serial_acte1 "$(serial_state)"
  sauve scelles "$(empreinte_code)"
  sauve scelles_valeurs "$(empreinte_valeurs)"
  sauve port2 "$(port_libre)"
  sauve phrase2 "Scelles ${MOT}, avenant du $(date +%d/%m) a $(date +%H:%M)"
  sauve etape 2
  echo ""
  echo "CONFORME. Livraison acceptee, $(date +%H:%M)."
  echo ""
  echo "SCELLES POSES sur tes fichiers .tf. Empreinte : $(lit scelles | cut -c1-16)"
  echo "A partir de maintenant, si UN caractere change dans UN fichier .tf, les scelles sont brises."
  echo ""
  echo "ACTE 2. L'AVENANT PAR TELEPHONE. Le client appelle, il est presse :"
  echo ""
  echo "   le port devient                 $(lit port2)"
  echo "   la phrase de la page devient    $(lit phrase2)"
  echo ""
  echo "Il le veut maintenant, en UNE SEULE commande, sans qu'AUCUN fichier ne bouge."
  echo "Ni .tf, evidemment, ni fichier de valeurs. Tu connais la facon de faire, temps 4."
  echo "Fais-le, puis relance ce script. Le controleur verifie, et il a une question pour toi."
  exit 0
fi

# --------------------------------------------------------------
# Acte 2, premier passage : l'avenant par -var, et ce qu'il laisse derriere lui
# --------------------------------------------------------------
if [ "$ETAPE" = "2" ]; then
  PORT2=$(lit port2); PHRASE2=$(lit phrase2)
  echo ""
  echo "ACTE 2. L'AVENANT PAR TELEPHONE : port ${PORT2}, nouvelle phrase. Le controleur repasse."
  [ "$(empreinte_code)" = "$(lit scelles)" ] || echec "SCELLES BRISES. Un fichier .tf a change depuis la livraison." "Le client a dit une commande, pas une ligne de code. Remets tes .tf exactement comme a la livraison (git te sauve si tu as commite), puis refais l'avenant sans toucher au code."
  echo "  scelles : intacts, aucun .tf n'a bouge"
  [ "$(empreinte_valeurs)" = "$(lit scelles_valeurs)" ] || echec "Ton fichier de valeurs a change." "Le client a dit AUCUN fichier. Pas meme celui-la. Remets-le comme avant, et cherche l'option de la ligne de commande qui donne une valeur sans fichier."
  echo "  valeurs : ton fichier de valeurs n'a pas bouge non plus"
  controle "$PORT2" "$PHRASE2" sansplan
  id_now=$(docker inspect -f '{{.Id}}' "$CONTENEUR")
  [ "$id_now" != "$(lit id_acte1)" ] || echec "Le conteneur est le meme qu'a l'acte 1." "Un port ne se modifie pas sur place, le plan devait dire must be replaced."
  sauve id_acte2 "$id_now"
  sauve serial_acte2 "$(serial_state)"
  echo ""
  echo "CONFORME. L'avenant est en place, Docker et ta memoire disent ${PORT2}, $(date +%H:%M)."
  echo ""
  echo "Maintenant la question du controleur. Il lance terraform plan, sans option, comme le"
  echo "fera ton collegue demain matin. Et voici ce que le plan annonce :"
  echo ""
  terraform plan -input=false -no-color 2>/dev/null | grep -E "must be replaced|external *=|content *=|Plan:|No changes" | sed 's/^/      /'
  echo ""
  code=$(etat_plan)
  if [ "$code" = "2" ]; then
    echo "Ta memoire dit ${PORT2}. Ton fichier de valeurs dit encore ${PORT}. Le prochain apply"
    echo "de n'importe qui remet l'ancien port et l'ancienne phrase, et le client perd son avenant."
    echo "Une valeur donnee sur la ligne de commande ne laisse AUCUNE trace dans le dossier."
    echo ""
    echo "Repare. Mets ton fichier de valeurs d'accord avec ta memoire, SANS casser la boutique :"
    echo "le conteneur qui tourne doit rester exactement le meme. Puis relance ce script."
    sauve etape 3
    exit 0
  fi
  echo "Le plan est vide. Le controleur n'y croit pas, personne ne saute cette marche. Relance-le."
  exit 3
fi

# --------------------------------------------------------------
# Acte 2, second passage : le fichier de valeurs rattrape la memoire
# --------------------------------------------------------------
if [ "$ETAPE" = "3" ]; then
  PORT2=$(lit port2); PHRASE2=$(lit phrase2)
  echo ""
  echo "ACTE 2. LA REPARATION. Le controleur repasse."
  [ "$(empreinte_code)" = "$(lit scelles)" ] || echec "SCELLES BRISES. Un fichier .tf a change." "Reparer, c'est toucher aux VALEURS, jamais au code. Remets tes .tf comme a la livraison."
  echo "  scelles : intacts"
  [ "$(empreinte_valeurs)" != "$(lit scelles_valeurs)" ] || echec "Ton fichier de valeurs n'a pas change depuis la livraison." "C'est lui qui doit dire ${PORT2} et la nouvelle phrase, pour que le prochain apply ne casse rien."
  echo "  valeurs : ton fichier de valeurs a ete mis a jour"
  controle "$PORT2" "$PHRASE2" plan
  id_now=$(docker inspect -f '{{.Id}}' "$CONTENEUR")
  if [ "$id_now" != "$(lit id_acte2)" ]; then
    sauve id_acte2 "$id_now"; sauve casse "oui"
    echec "Le conteneur a ete remplace pendant la reparation, la boutique a ferme." "Si les valeurs du fichier sont exactement celles de la memoire, le plan est vide et rien ne bouge. Une lettre de difference, et la boutique ferme. Le controleur note la casse au proces-verbal. Relance, il reprend."
  fi
  echo "  identifiant : le MEME conteneur, la reparation n'a rien casse"
  sauve etape 4
  echo ""
  echo "CONFORME. Fichier, memoire et Docker sont d'accord, $(date +%H:%M)."
fi

# --------------------------------------------------------------
# Acte 3, l'audit a blanc
# --------------------------------------------------------------
if [ "$(lit etape)" = "4" ]; then
  echo ""
  echo "ACTE 3. L'AUDIT A BLANC. Le controleur copie tes fichiers .tf, et SEULEMENT eux, dans"
  echo "un dossier temporaire. Pas de fichier de valeurs, pas de state, pas de variable"
  echo "d'environnement. Il y lance un plan. Ce que ton code fait sans aucune valeur, c'est"
  echo "ce que verra la prochaine personne qui l'ouvrira."
  echo ""
  [ "$(empreinte_code)" = "$(lit scelles)" ] || echec "SCELLES BRISES. Un fichier .tf a change." "Remets tes .tf comme a la livraison."
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t scelles)
  cp ./*.tf "$tmp"/ && cp .terraform.lock.hcl "$tmp"/ 2>/dev/null; cp -R .terraform "$tmp"/
  sortie=$(cd "$tmp" && for v in $(env | grep -oE '^TF_VAR_[^=]+'); do unset "$v"; done; terraform plan -input=false -no-color 2>&1)
  rm -rf "$tmp"
  nb=$(echo "$sortie" | grep -cE 'input variable "[^"]+" is not set')
  if echo "$sortie" | grep -qE "^Plan:|No changes"; then
    echec "Avec tes seuls fichiers .tf, sans aucune valeur, Terraform accepte de construire." "Une valeur par defaut cache le contrat. Le port, la phrase et la cle doivent etre IMPOSES par celui qui lance, pas devines par le code. Retire les defauts qui n'ont rien a faire la."
  fi
  echo "$sortie" | grep -qF "No value for required variable" || echec "L'audit a blanc n'a pas donne le refus attendu." "Voici ce que Terraform a repondu :
$(echo "$sortie" | tail -12)"
  echo "  audit : sans valeurs, Terraform refuse, ${nb} variable(s) exigee(s) :"
  echo "$sortie" | grep -oE 'input variable "[^"]+" is not set' | sed -E 's/input variable "([^"]+)" is not set/      \1/'
  [ "$nb" -ge 3 ] || echec "Seulement ${nb} variable(s) sans valeur par defaut." "Le port, la phrase et la cle au minimum. Une valeur par defaut sur l'une d'elles, et n'importe qui deploie n'importe quoi sans le savoir."
  sauve nb_requises "$nb"
  echo ""
  echo "Deuxieme partie de l'audit. Le controleur teste ta regle sur le port, celle que le"
  echo "client exigeait dans le code. Il va lancer un plan avec un port interdit, deux fois."
  pv=$(lit var_port)
  while [ -z "$pv" ]; do
    pv=$(demande "Comment s'appelle ta variable qui porte le port ? (le nom apres variable, sans guillemets)")
  done
  for mauvais in 80 8200; do
    sortie=$(terraform plan -input=false -no-color -var "${pv}=${mauvais}" 2>&1)
    if echo "$sortie" | grep -qF "Value for undeclared variable"; then
      echo "  Aucune variable nommee ${pv} dans ton code. Verifie le nom, puis relance ce script."
      exit 3
    fi
    if echo "$sortie" | grep -qF "Invalid value for variable"; then
      msg=$(echo "$sortie" | grep -A2 -F "var.${pv} is ${mauvais}" | sed -n 3p)
      echo "  port ${mauvais} : REFUSE par ton code, avant tout plan. Ton message : ${msg}"
      continue
    fi
    if echo "$sortie" | grep -qE "^Plan:|No changes|must be replaced"; then
      echec "Ton code ACCEPTE le port ${mauvais}. Le client avait dit 8100 a 8199, refuse par le code." "La page Input Variables du langage, section sur les regles de validation. Une condition et un message, dans le bloc de la variable. Et les deux bornes comptent. Remets les scelles en relancant apres correction."
    fi
    echec "Le plan avec ${pv}=${mauvais} a rendu une erreur inattendue." "$(echo "$sortie" | grep -m1 -A3 Error)"
  done
  sauve var_port "$pv"
  sauve etape 5
  echo ""
  echo "CONFORME. Audit signe, $(date +%H:%M). Tes scelles sont toujours la."
fi

# --------------------------------------------------------------
# Acte 4, le secret et la signature
# --------------------------------------------------------------
if [ "$(lit etape)" = "5" ]; then
  PORT2=$(lit port2); pv=$(lit var_port)
  echo ""
  echo "ACTE 4. LE SECRET. La cle du client, ${ENVNOM}. Le controleur cherche partout ou elle"
  echo "pourrait fuir. Il lance un plan qui remplace le conteneur, pour lire tout ce que le"
  echo "plan est capable d'afficher."
  echo ""
  [ "$(empreinte_code)" = "$(lit scelles)" ] || echec "SCELLES BRISES. Un fichier .tf a change." "Remets tes .tf comme a la livraison."
  sortie=$(terraform plan -input=false -no-color -var "${pv}=${PORT}" 2>&1)
  echo "$sortie" | grep -qF "must be replaced" || echec "Le plan de test n'a pas propose de remplacement." "$(echo "$sortie" | grep -m1 -A3 -E 'Error|Plan:')"
  if echo "$sortie" | grep -qF -- "$CLE"; then
    echec "La cle du client s'affiche EN CLAIR dans la sortie du plan." "N'importe qui lit un plan, dans un pipeline, dans un ticket, dans une capture d'ecran. La page Input Variables du langage a un argument pour qu'une valeur ne s'affiche jamais. Puis relance, les scelles seront reposes sur cette correction."
  fi
  echo "  plan : la cle n'apparait nulle part, Terraform ecrit (sensitive value) a sa place"
  docker inspect -f '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$CONTENEUR" | grep -qxF "${ENVNOM}=${CLE}" || echec "Le conteneur n'a plus la cle." "Le client la veut dans le conteneur."
  echo "  conteneur : la cle y est, en clair, c'est le but, l'application en a besoin"
  nb_state=$(terraform state pull 2>/dev/null | grep -cF -- "$CLE")
  echo "  state : le controleur ouvre ta memoire. La cle y est ecrite EN CLAIR, ${nb_state} fois."
  echo ""
  echo "  Retiens ca. sensitive cache une valeur dans les sorties, jamais dans le state."
  echo "  La doc le dit en une phrase, et elle nomme l'argument qui l'en retire. Question 8."
  sauve nb_state "$nb_state"
  echo ""
  echo "LA SIGNATURE. Le client signe la reception avec une empreinte que seul Terraform"
  echo "calcule a partir de ta memoire. Il veut la valeur de cette expression, telle que"
  echo "Terraform l'evalue, avec tes variables et ton state a lui :"
  a_con=$(adresse_par_nom docker_container "$CONTENEUR")
  echo ""
  echo "      substr(md5(${a_con}.id), 0, 12)"
  echo ""
  echo "Une commande terraform repond a ce genre de question, sans rien creer, sans rien"
  echo "modifier. Le document de la mission ne te l'a jamais ecrite. C'est le tresor du jour."
  attendu=$(md5_de "$(docker inspect -f '{{.Id}}' "$CONTENEUR")" | cut -c1-12)
  sig=$(demande "Ta signature (12 caracteres) :" | tr 'A-Z' 'a-z' | tr -d '"')
  [ "$sig" = "$attendu" ] || echec "Signature refusee." "Ce n'est pas la valeur que Terraform calcule. Cherche dans la liste des commandes celle qui evalue une expression, et donne-lui l'expression telle quelle."
  echo "  signature : acceptee"
  sauve etape 6
  echo ""
  echo "CONFORME. Le secret est garde, la signature est bonne, $(date +%H:%M)."
fi

# --------------------------------------------------------------
# Reception
# --------------------------------------------------------------
echo ""
echo "LA RECEPTION. Le controleur relit tes fichiers une derniere fois."
if ! terraform fmt -check -recursive >/dev/null 2>&1; then
  echo "  mise en forme : REFUSEE. Un fichier n'est pas au format standard. Tu connais la commande depuis hier. Elle range aussi les .tfvars."
  exit 3
fi
echo "  mise en forme : conforme, .tf et .tfvars compris"
if ! terraform validate -no-color >/dev/null 2>&1; then
  echo "  grammaire : REFUSEE. Tu connais la commande depuis hier."
  exit 3
fi
echo "  grammaire : conforme"
[ "$(empreinte_code)" = "$(lit scelles)" ] || echec "SCELLES BRISES a la reception." "Un fichier .tf a change apres la livraison. Remets-le, ou relance depuis reset."
echo "  scelles : intacts du debut a la fin"

if [ "$(lit etape)" != "7" ]; then
  sauve etape 7
  sauve fin "$(date +%s)"
fi

echo ""
echo "=============================================================="
echo " PROCES-VERBAL DE RECEPTION"
echo "=============================================================="
echo " Cahier des charges : ${RESEAU}, ${CONTENEUR}, port ${PORT} puis $(lit port2), cle ${ENVNOM}"
echo " Livraison          : cinq valeurs hors du code, trois sorties, scelles $(lit scelles | cut -c1-16)"
echo " Avenant            : livre par la ligne de commande, derive constate, fichier de valeurs repare$( [ "$(lit casse)" = "oui" ] && echo ", avec une casse" )"
echo " Audit a blanc      : $(lit nb_requises) variables exigees sans defaut, ports 80 et 8200 refuses par le code"
echo " Secret             : muet dans le plan, present dans le conteneur, en clair $(lit nb_state) fois dans le state"
echo " Signature          : calculee par Terraform, acceptee"
echo " Reception          : fichiers formates, configuration valide, scelles intacts"
echo " Duree totale       : $(duree)"
echo ""
echo " Le code n'a pas bouge. Les valeurs ont voyage. C'est ca, un code reutilisable."
echo ""
echo " CODE DE MISSION : $(printf '%s' "$CODE_B64" | base64 -d 2>/dev/null || printf '%s' "$CODE_B64" | base64 -D)"
echo "=============================================================="
echo ""
echo "Recopie le proces-verbal EN ENTIER dans ton compte rendu, section 10, avec tout ce que la mission demande pour l'epreuve."
echo "Ta boutique de l'epreuve peut rester debout, la mission 3 en aura besoin."
exit 0
