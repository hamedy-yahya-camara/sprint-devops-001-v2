#!/usr/bin/env bash
# ==============================================================
# OPERATION AMNESIE
# Mission 3, Semaine Terraform, sprint DevOps MeggieOnTheStack, Promo 001
# ==============================================================
#
# A lancer SANS sudo, DANS ton dossier Terraform (celui de tes fichiers .tf) :
#
#   cd ~/tf-promo001
#   bash ~/Downloads/amnesie-tf-003.sh
#
# Ce script dit en toutes lettres ce qu'il touche.
# Il LIT : tes fichiers .tf (pour en calculer une empreinte), ton state
# (terraform state list / show), tes plans (terraform plan, qui ne modifie
# rien) et Docker (docker inspect, docker exec pour lire un fichier temoin).
# Il CREE, a l'acte 1, avec docker run, un reseau et un conteneur nginx a la
# main, et ecrit un fichier temoin dedans. C'est l'archive que tu dois adopter.
# Il TOUCHE a ton infra dans ton dos, une seule fois, a l'acte 2, et il te le
# dit : il arrete l'archive (docker stop) et il supprime le conteneur de ta
# boutique (docker rm -f). Ta boutique est decrite dans tes .tf, un apply la
# refait.
# Il DEPLACE, a l'acte 4, ton fichier terraform.tfstate et ses sauvegardes dans
# un sous-dossier .amnesie-tf-003 de ton dossier. Il ne les efface jamais.
# Il ECRIT un seul fichier de suivi, .amnesie-tf-003.suivi, dans ton dossier, pour se
# souvenir du cahier des charges et de ton avancement.
# Il ne touche jamais a tes fichiers .tf ni a ton fichier de valeurs.
# Relance-le autant de fois que tu veux, il reprend ou tu en etais.
#   bash amnesie-tf-003.sh reset    efface le suivi, en grave un neuf.
#
# Le principe. Le client te confie une archive construite a la main, avant
# Terraform, qui contient un fichier impossible a refaire. Tu l'adoptes dans ta
# memoire Terraform sans la detruire. Puis quelqu'un touche a ton infra dans
# ton dos. Puis le client exige des operations de chirurgie sur ta memoire.
# Puis ta memoire disparait, et tu la reconstruis depuis la realite. A chaque
# acte, le temoin dit si l'archive a survecu.
# Le code de mission est encode pour ne pas te spoiler si tu lis ce fichier.
#

set -u
LC_ALL=C
export LC_ALL

CODE_B64="TEEtTUVNT0lSRS1TRS1SRUNPTlNUUlVJVC1MRS1URU1PSU4tTkUtTUVOVC1QQVMtMjAyNg=="
SPEC=".amnesie-tf-003.suivi"
COFFRE="docker_container.coffre"
IMAGE="nginx:1.27-alpine"
TEMOIN_CHEMIN="/usr/share/nginx/html/temoin.txt"

# 0. Pas de sudo ici
if [ "$(id -u)" -eq 0 ]; then
  echo "STOP. Pas de sudo pour cette epreuve. Relance simplement : bash amnesie-tf-003.sh"
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
  echo "  bash ~/Downloads/amnesie-tf-003.sh"
  exit 1
fi
if [ ! -d .terraform ]; then
  echo "Pas de dossier .terraform ici. Ton dossier n'est pas initialise, ou tu n'es pas dans le bon. terraform init d'abord."
  exit 1
fi

# --------------------------------------------------------------
# Outils du controleur
# --------------------------------------------------------------

MOTS="papyrus velin parchemin grimoire codex manuscrit registre almanach atlas herbier carnet folio lettrine encrier palimpseste incunable"

mot_au_hasard() {
  n=$(echo "$MOTS" | wc -w | tr -d ' ')
  i=$(( ( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % n ) + 1 ))
  echo "$MOTS" | tr ' ' '\n' | sed -n "${i}p"
}

hexa() { od -An -N3 -tx1 /dev/urandom | tr -d ' \n'; }

serial_state() {
  [ -f terraform.tfstate ] || { echo 0; return; }
  grep -m1 -oE '"serial": *[0-9]+' terraform.tfstate | grep -oE '[0-9]+'
}
lignee_state() {
  [ -f terraform.tfstate ] || { echo aucune; return; }
  grep -m1 -oE '"lineage": *"[^"]+"' terraform.tfstate | sed -E 's/.*"([^"]+)"$/\1/'
}

# adresse dans le state d'une ressource TYPE dont l'attribut name vaut VALEUR
adresse_par_nom() {
  type="$1"; valeur="$2"
  for a in $(terraform state list 2>/dev/null | grep "^${type}\."); do
    n=$(terraform state show -no-color "$a" 2>/dev/null | grep -m1 -E '^ *name *=' | sed -E 's/.*= *"([^"]*)".*/\1/')
    if [ "$n" = "$valeur" ]; then echo "$a"; return 0; fi
  done
  return 1
}

attribut() { terraform state show -no-color "$1" 2>/dev/null | grep -m1 -E "^ *$2 *=" | sed -E 's/.*= *"?([^"]*)"?.*/\1/'; }

# 0 = plan vide, 2 = changements, 1 = erreur
etat_plan() {
  terraform plan -detailed-exitcode -input=false -no-color >/dev/null 2>&1
  echo $?
}

empreinte() {
  if command -v sha256sum >/dev/null 2>&1; then
    ls "$@" 2>/dev/null | sort | xargs cat 2>/dev/null | sha256sum | cut -c1-64
  else
    ls "$@" 2>/dev/null | sort | xargs cat 2>/dev/null | shasum -a 256 | cut -c1-64
  fi
}
empreinte_code() { empreinte ./*.tf; }

sauve() { # cle valeur
  grep -v "^$1=" "$SPEC" 2>/dev/null > "$SPEC.tmp"; echo "$1=$2" >> "$SPEC.tmp"; mv "$SPEC.tmp" "$SPEC"
}
lit() { grep -m1 "^$1=" "$SPEC" 2>/dev/null | cut -d= -f2-; }

echec() {
  echo ""
  echo "NON CONFORME. $1"
  echo "Piste : $2"
  echo ""
  echo "Corrige, puis relance : bash amnesie-tf-003.sh"
  exit 3
}

duree() {
  debut=$(lit debut); fin=$(lit fin); [ -n "$fin" ] || fin=$(date +%s); s=$(( fin - debut ))
  printf '%dh%02d' $(( s / 3600 )) $(( (s % 3600) / 60 ))
}

id_docker() { docker inspect -f '{{.Id}}' "$1" 2>/dev/null; }
tourne()    { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
lire_temoin() { docker exec "$1" cat "$TEMOIN_CHEMIN" 2>/dev/null | tr -d '\r\n'; }
ecrire_temoin() { docker exec "$1" sh -c "echo '$2' > $TEMOIN_CHEMIN" 2>/dev/null; }

# --------------------------------------------------------------
# Reset
# --------------------------------------------------------------
if [ "${1:-}" = "reset" ]; then
  if [ -f "$SPEC" ]; then
    echo "Le suivi est efface. L'archive de l'ancien cahier reste dans Docker, a toi de la retirer si tu veux :"
    echo "  docker rm -f $(lit archive)   puis   docker network rm $(lit reseau_archives)"
    echo "Et si elle est dans ta memoire Terraform, retire ses blocs, ou terraform state rm."
    echo "Si ton state a ete deplace a l'acte 4, il est intact dans .amnesie-tf-003/."
  fi
  rm -f "$SPEC"
  echo "Relance sans argument pour recevoir un cahier des charges neuf."
  exit 0
fi

# --------------------------------------------------------------
# Le cahier des charges (grave une seule fois)
# --------------------------------------------------------------
if [ ! -f "$SPEC" ]; then
  mot=$(mot_au_hasard)
  sauve mot "$mot"
  sauve reseau_archives "archives-${mot}"
  sauve archive "archive-${mot}"
  sauve temoin "TEMOIN-${mot}-$(hexa)"
  sauve etape 1
  sauve debut "$(date +%s)"
fi

MOT=$(lit mot); RESEAU_A=$(lit reseau_archives); ARCHIVE=$(lit archive); TEMOIN=$(lit temoin); ETAPE=$(lit etape)

echo "=============================================================="
echo " OPERATION AMNESIE, Promo 001, Terraform mission 3"
echo "=============================================================="

# --------------------------------------------------------------
# Verifications communes
# --------------------------------------------------------------

# l'archive tourne, avec l'identite attendue et son temoin
controle_archive() { # $1 = adresse attendue dans le state ("" = par nom)
  attendu="$1"
  tourne "$ARCHIVE" || echec "Le conteneur ${ARCHIVE} ne tourne pas, ou n'existe plus." "docker ps -a. S'il est arrete, une commande docker le relance sans le detruire. S'il n'existe plus, l'archive est perdue, et le temoin avec."
  idd=$(id_docker "$ARCHIVE")
  if [ -n "$attendu" ]; then
    a_arc="$attendu"
    terraform state list 2>/dev/null | grep -qx "$a_arc" || echec "Aucune ressource ${a_arc} dans ta memoire Terraform." "Le client veut l'archive a CETTE adresse, sans la detruire. Une page du langage s'appelle Refactoring, et terraform state a une sous-commande pour ca. Le document ne te l'ecrit pas, c'est le tresor du jour."
  else
    a_arc=$(adresse_par_nom docker_container "$ARCHIVE") || echec "Aucune ressource docker_container nommee ${ARCHIVE} dans ta memoire Terraform." "Un bloc resource qui decrit l'archive telle qu'elle est, et un import, par bloc ou par commande. La page docker_container du provider a une section Import."
  fi
  ids=$(attribut "$a_arc" id)
  [ "$ids" = "$idd" ] || echec "L'archive de ta memoire (${ids}) n'est pas celle qui tourne (${idd})." "Ta memoire parle d'un autre conteneur. terraform plan te dit ce qu'il croit, docker inspect te dit ce qui est."
  if [ "$idd" != "$(lit archive_id)" ]; then
    # l'archive a ete detruite et refaite : le temoin d'origine est perdu
    sauve casse "$(lit casse)$2,"
    sauve archive_id "$idd"
    nouveau="TEMOIN-${MOT}-$(hexa)"
    ecrire_temoin "$ARCHIVE" "$nouveau"; sauve temoin "$nouveau"; TEMOIN="$nouveau"
    echo ""
    echo "  ARCHIVE DETRUITE. Le conteneur qui tourne n'est plus celui du client, son identifiant a change."
    echo "  Le fichier temoin d'origine est perdu pour toujours. Le controleur le note au proces-verbal."
    echo "  Il ecrit un nouveau temoin dans la nouvelle archive pour que l'epreuve continue."
    echo "  Relis le plan que tu as applique. Il te l'avait dit, en toutes lettres."
    echo ""
  fi
  t=$(lire_temoin "$ARCHIVE")
  [ "$t" = "$TEMOIN" ] || echec "Le temoin de l'archive ne repond plus (${t:-vide})." "Le fichier ${TEMOIN_CHEMIN} dans ${ARCHIVE} doit contenir exactement ${TEMOIN}."
  echo "  archive ${ARCHIVE} : meme identifiant que ta memoire (${a_arc}), temoin intact"
}

# la boutique du membre : un docker_container du state qui n'est pas l'archive, qui tourne
controle_boutique() {
  nom=$(lit boutique)
  a_bou=$(adresse_par_nom docker_container "$nom") || echec "Aucune ressource docker_container nommee ${nom} dans ta memoire Terraform." "Ta boutique de la mission 2 doit etre dans le state. terraform plan te dira ce qu'il manque."
  idd=$(id_docker "$nom") || echec "Docker ne connait aucun conteneur ${nom}." "Ta memoire dit qu'il existe, Docker dit non. Un plan, puis un apply, et lis ce que le plan annonce."
  tourne "$nom" || echec "Le conteneur ${nom} existe mais ne tourne pas." "docker ps -a, docker logs ${nom}."
  [ "$(attribut "$a_bou" id)" = "$idd" ] || echec "Le conteneur ${nom} qui tourne n'est pas celui de ta memoire." "Identifiants differents. Un docker run a la main ne compte pas, et un conteneur refait dans le dos de Terraform non plus. Laisse Terraform le refaire."
  echo "  boutique ${nom} : presente dans le state (${a_bou}), meme identifiant que Docker, elle tourne"
}

plan_vide() {
  [ "$(etat_plan)" = "0" ] || echec "terraform plan annonce encore des changements, ou echoue." "Lance terraform plan et lis-le en entier. Chaque ligne avec # forces replacement dit ce que ton bloc contredit dans la realite."
  echo "  plan : No changes, ta memoire, ton code et Docker sont d'accord"
}

# --------------------------------------------------------------
# Acte 1, l'adoption
# --------------------------------------------------------------
if [ "$ETAPE" = "1" ]; then
  if ! docker inspect "$ARCHIVE" >/dev/null 2>&1; then
    echo ""
    echo "Le controleur construit l'archive du client, A LA MAIN, sans Terraform, sous tes yeux :"
    echo ""
    echo "   docker network create ${RESEAU_A}"
    docker network create "$RESEAU_A" >/dev/null 2>&1 || true
    echo "   docker run -d --name ${ARCHIVE} --network ${RESEAU_A} ${IMAGE}"
    docker run -d --name "$ARCHIVE" --network "$RESEAU_A" "$IMAGE" >/dev/null || echec "Docker n'a pas pu creer l'archive." "docker ps -a, docker network ls. Un reste d'une ancienne epreuve ? Retire-le, puis relance."
    sleep 1
    ecrire_temoin "$ARCHIVE" "$TEMOIN" || echec "Le controleur n'a pas pu ecrire le temoin dans l'archive." "docker logs ${ARCHIVE}"
    sauve archive_id "$(id_docker "$ARCHIVE")"
    echo "   et il ecrit un fichier temoin DANS le conteneur, hors de toute image, hors de tout volume."
    echo ""
    echo "ACTE 1. L'ADOPTION. Le client parle :"
    echo ""
    echo "   Ce reseau et ce conteneur existaient avant toi, avant Terraform. Le conteneur contient un"
    echo "   fichier qu'aucune image ne peut refaire. Je veux les deux dans ta memoire Terraform,"
    echo "   decrits dans tes .tf, et je veux le MEME conteneur. Pas une copie. S'il est detruit et"
    echo "   refait, meme identique, le fichier est perdu, et je le saurai."
    echo ""
    echo "   le reseau a adopter            ${RESEAU_A}"
    echo "   le conteneur a adopter         ${ARCHIVE}   (image ${IMAGE}, aucun port publie)"
    echo "   le temoin, pour ton compte rendu   $(docker exec "$ARCHIVE" cat "$TEMOIN_CHEMIN")"
    echo ""
    echo "Ta boutique de la mission 2 reste en place, le controleur la verifie aussi."
    echo "Adopte, puis relance ce script. Le plan te dit AVANT l'apply si tu vas la detruire. Lis-le."
    exit 0
  fi
  echo ""
  echo "ACTE 1. L'ADOPTION. Le controleur passe. Il lit ta memoire, puis Docker."
  a_net=$(adresse_par_nom docker_network "$RESEAU_A") || echec "Aucune ressource docker_network nommee ${RESEAU_A} dans ta memoire Terraform." "Un bloc resource docker_network avec ce name, puis un import. La page docker_network du provider a une section Import, et terraform import a une page dans les commandes."
  [ "$(attribut "$a_net" id)" = "$(docker network inspect -f '{{.Id}}' "$RESEAU_A")" ] || echec "Le reseau de ta memoire n'est pas celui de Docker (identifiants differents)." "Ta memoire parle d'un autre reseau. Un reseau refait a la main, ou une adoption ratee."
  echo "  reseau ${RESEAU_A} : adopte (${a_net}), meme identifiant que Docker"
  controle_archive "" adoption
  # la boutique du membre : le premier docker_container du state qui n'est pas l'archive
  bou=""
  for a in $(terraform state list 2>/dev/null | grep '^docker_container\.'); do
    n=$(attribut "$a" name)
    if [ "$n" != "$ARCHIVE" ] && [ -n "$n" ]; then bou="$n"; break; fi
  done
  [ -n "$bou" ] || echec "Ta memoire ne contient aucun autre conteneur que l'archive." "Ta boutique de la mission 2 doit etre debout et dans le state. terraform apply la refait si tu l'avais detruite."
  sauve boutique "$bou"
  controle_boutique
  plan_vide
  sauve etape 2
  echo ""
  echo "CONFORME. Adoption acceptee, $(date +%H:%M). L'archive est a toi, avec son temoin."
  echo ""
  echo "ACTE 2. LE SABOTAGE. Quelqu'un touche a ton infra dans ton dos. Le controleur le fait"
  echo "lui-meme, maintenant, et il te le dit en toutes lettres :"
  echo ""
  echo "   docker stop ${ARCHIVE}"
  docker stop "$ARCHIVE" >/dev/null 2>&1
  echo "   docker rm -f ${bou}"
  docker rm -f "$bou" >/dev/null 2>&1
  echo ""
  echo "L'archive est arretee. Ta boutique n'existe plus. Ta memoire, elle, n'a rien vu."
  echo "Remets tout debout. La boutique, en Terraform. L'archive, avec le MEME identifiant et son"
  echo "temoin. Avant chaque apply, lis le plan, et demande-toi ce qu'il va detruire."
  echo "Puis relance ce script."
  exit 0
fi

# --------------------------------------------------------------
# Acte 2, le retour a la normale
# --------------------------------------------------------------
if [ "$ETAPE" = "2" ]; then
  echo ""
  echo "ACTE 2. LE SABOTAGE. Le controleur repasse."
  controle_archive "" sabotage
  controle_boutique
  plan_vide
  sauve id_boutique_acte2 "$(id_docker "$(lit boutique)")"
  sauve scelles3 "$(empreinte_code)"
  sauve etape 3
  echo ""
  echo "CONFORME. Tout est debout, $(date +%H:%M)."
  echo ""
  echo "ACTE 3. LA CHIRURGIE. Le client a des exigences sur ta memoire, et il pose une regle :"
  echo "a partir de maintenant, AUCUNE commande docker. Tout passe par Terraform."
  echo ""
  echo "   Premiere exigence. Ta boutique $(lit boutique) a ete touchee par un inconnu, il n'a plus"
  echo "   confiance. Il veut un conteneur NEUF, identifiant neuf, avec exactement le meme code."
  echo "   Aucun fichier ne bouge. Le controleur a pris l'empreinte de tes .tf a l'instant."
  echo ""
  echo "Fais-le, puis relance ce script."
  exit 0
fi

# --------------------------------------------------------------
# Acte 3a, le remplacement force
# --------------------------------------------------------------
if [ "$ETAPE" = "3" ]; then
  echo ""
  echo "ACTE 3. LA CHIRURGIE, premiere exigence. Le controleur repasse."
  [ "$(empreinte_code)" = "$(lit scelles3)" ] || echec "Un fichier .tf a change depuis l'acte 2." "Le client a dit aucun fichier. Remets tes .tf comme ils etaient. La page de la commande plan a une option qui force le remplacement d'une ressource, elle marche aussi avec apply."
  echo "  code : aucun .tf n'a bouge"
  bou=$(lit boutique)
  controle_boutique
  [ "$(id_docker "$bou")" != "$(lit id_boutique_acte2)" ] || echec "Le conteneur ${bou} est le meme qu'a l'acte 2." "Le client veut un conteneur neuf. Sans toucher au code, sans commande docker. La page de la commande plan, cherche l'option qui remplace une ressource a la demande."
  echo "  boutique ${bou} : identifiant neuf, remplacee par Terraform"
  controle_archive "" chirurgie
  plan_vide
  sauve etape 4
  echo ""
  echo "CONFORME. Remplacement accepte, $(date +%H:%M)."
  echo ""
  echo "ACTE 3. LA CHIRURGIE, suite. Trois exigences de plus, toujours sans commande docker :"
  echo ""
  echo "   Deuxieme. Le reseau ${RESEAU_A} passe a une autre equipe. Terraform doit L'OUBLIER,"
  echo "   sans le detruire. Il doit disparaitre de ta memoire et rester dans Docker."
  echo ""
  echo "   Troisieme. Dans ton code, l'archive doit s'appeler ${COFFRE}. Meme conteneur,"
  echo "   meme identifiant, meme temoin. Un renommage, pas une reconstruction."
  echo ""
  echo "   Quatrieme. Le client veut que terraform destroy soit REFUSE tant que ${COFFRE}"
  echo "   est dans ta memoire. Le controleur le testera lui-meme, avec un plan."
  echo ""
  echo "Fais les trois, puis relance ce script."
  exit 0
fi

# --------------------------------------------------------------
# Acte 3b, c, d : oublier, renommer, proteger
# --------------------------------------------------------------
if [ "$ETAPE" = "4" ]; then
  echo ""
  echo "ACTE 3. LA CHIRURGIE, suite. Le controleur repasse."
  if adresse_par_nom docker_network "$RESEAU_A" >/dev/null 2>&1; then
    echec "Le reseau ${RESEAU_A} est encore dans ta memoire Terraform." "Oublier sans detruire. La page de la commande state rm le dit en une phrase, et le langage a un bloc pour ca, avec un argument qui empeche la destruction. Retire aussi le bloc resource, sinon le plan voudra le recreer."
  fi
  docker network inspect "$RESEAU_A" >/dev/null 2>&1 || echec "Le reseau ${RESEAU_A} n'existe plus dans Docker." "Le client a dit oublier, pas detruire. Le plan te l'avait annonce. Recree-le a la main, docker network create ${RESEAU_A}, le controleur fermera les yeux cette fois."
  echo "  reseau ${RESEAU_A} : oublie par Terraform, toujours dans Docker"
  if terraform state list 2>/dev/null | grep -qx "docker_container.archive"; then
    echec "docker_container.archive existe encore dans ta memoire." "Le client veut ${COFFRE}, et une seule adresse pour l'archive."
  fi
  controle_archive "$COFFRE" renommage
  plan_vide
  echo "  Le controleur lance lui-meme : terraform plan -destroy"
  sortie=$(terraform plan -destroy -input=false -no-color 2>&1)
  if echo "$sortie" | grep -qF "cannot be destroyed"; then
    echo "$sortie" | grep -m1 -F "cannot be destroyed" | sed 's/^/      /'
    echo "  protection : Terraform REFUSE de detruire ${COFFRE}, comme le client l'exige"
  else
    echec "terraform plan -destroy accepte de detruire ${COFFRE}." "Un reglage dans le bloc de la ressource, dans la page lifecycle des meta-arguments du langage. Terraform doit repondre par une erreur, pas par un plan."
  fi
  sauve lignee_avant "$(lignee_state)"
  sauve serial_avant "$(serial_state)"
  mkdir -p .amnesie-tf-003
  mv terraform.tfstate .amnesie-tf-003/terraform.tfstate.$(date +%s) 2>/dev/null
  for f in terraform.tfstate.backup terraform.tfstate.*.backup; do [ -f "$f" ] && mv "$f" .amnesie-tf-003/ 2>/dev/null; done
  sauve etape 5
  echo ""
  echo "CONFORME. Chirurgie acceptee, $(date +%H:%M)."
  echo ""
  echo "ACTE 4. L'AMNESIE. Le controleur vient de DEPLACER ta memoire. terraform.tfstate et ses"
  echo "sauvegardes sont dans le sous-dossier .amnesie-tf-003/, intacts, hors de portee de"
  echo "Terraform. Ne les remets pas en place, ce serait tricher, et le controleur compare la lignee."
  echo ""
  echo "   Terraform ne se souvient de rien. Docker, lui, n'a rien oublie. Tout tourne encore."
  echo ""
  echo "   Reconstruis ta memoire depuis la realite. A la fin, terraform state list doit contenir"
  echo "   ${COFFRE} avec le MEME identifiant et son temoin, ton reseau de la mission 2 avec"
  echo "   le MEME identifiant, ta boutique $(lit boutique), et le plan doit etre vide."
  echo "   Ce que tu ne peux pas adopter, tu le refais, et le plan te dit lequel."
  echo ""
  echo "Puis relance ce script."
  exit 0
fi

# --------------------------------------------------------------
# Acte 4, la reconstruction
# --------------------------------------------------------------
if [ "$ETAPE" = "5" ]; then
  echo ""
  echo "ACTE 4. L'AMNESIE. Le controleur repasse."
  [ -f terraform.tfstate ] || echec "Aucun terraform.tfstate dans ton dossier." "Ta memoire renait au premier apply, ou au premier import. terraform state list te dira ce qu'elle contient."
  [ "$(lignee_state)" != "$(lit lignee_avant)" ] || echec "Cette memoire est l'ancienne, remise en place." "Le controleur compare la lignee du state. Une memoire reconstruite a une lignee neuve. Remets le fichier dans .amnesie-tf-003/ et reconstruis pour de vrai."
  echo "  memoire : lignee neuve ($(lignee_state | cut -c1-8)...), ce n'est pas l'ancien fichier"
  controle_archive "$COFFRE" amnesie
  bou=$(lit boutique)
  controle_boutique
  # le reseau du membre : celui sur lequel la boutique est branchee
  net_bou=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$bou" | tr ' ' '\n' | grep -v '^$' | head -1)
  a_net=$(adresse_par_nom docker_network "$net_bou") || echec "Le reseau ${net_bou} de ta boutique n'est pas dans ta memoire." "Un reseau se refait ? Docker refuse, le nom existe deja. Un reseau s'adopte, comme a l'acte 1."
  [ "$(attribut "$a_net" id)" = "$(docker network inspect -f '{{.Id}}' "$net_bou")" ] || echec "Le reseau ${net_bou} de ta memoire n'est pas celui de Docker." "Identifiants differents. Un import, pas une creation."
  echo "  reseau ${net_bou} : adopte a nouveau, meme identifiant"
  plan_vide
  sauve etape 6
  echo ""
  echo "CONFORME. Memoire reconstruite, $(date +%H:%M)."
fi

# --------------------------------------------------------------
# Reception
# --------------------------------------------------------------
echo ""
echo "LA RECEPTION. Le controleur relit tes fichiers une derniere fois."
if ! terraform fmt -check -recursive >/dev/null 2>&1; then
  echo "  mise en forme : REFUSEE. Un fichier n'est pas au format standard. Tu connais la commande."
  exit 3
fi
echo "  mise en forme : conforme"
if ! terraform validate -no-color >/dev/null 2>&1; then
  echo "  grammaire : REFUSEE. Tu connais la commande."
  exit 3
fi
echo "  grammaire : conforme"
[ "$(etat_plan)" = "0" ] || echec "Le plan n'est pas vide a la reception." "terraform plan, lis-le."
echo "  plan : vide"

if [ "$(lit etape)" != "7" ]; then
  sauve etape 7
  sauve fin "$(date +%s)"
fi

casse=$(lit casse)
echo ""
echo "=============================================================="
echo " PROCES-VERBAL DE RECEPTION"
echo "=============================================================="
echo " Archive             : ${ARCHIVE} sur ${RESEAU_A}, temoin ${TEMOIN}"
echo " Adoption            : reseau et conteneur importes, identifiants conserves"
echo " Sabotage            : archive arretee et boutique supprimee dans ton dos, tout remis debout"
echo " Chirurgie           : boutique remplacee sans toucher au code, reseau oublie sans etre detruit,"
echo "                       archive renommee ${COFFRE} sans reconstruction, destroy refuse"
echo " Amnesie             : state deplace, memoire reconstruite, lignee neuve, plan vide"
if [ -n "$casse" ]; then
echo " Archive detruite    : oui, a l'acte ${casse%,}. Le temoin d'origine est perdu, note au PV."
else
echo " Archive detruite    : jamais. Le temoin du client est celui du premier jour."
fi
echo " Duree totale        : $(duree)"
echo ""
echo " La memoire se reconstruit. Le temoin ne ment pas."
echo ""
echo " CODE DE MISSION : $(printf '%s' "$CODE_B64" | base64 -d 2>/dev/null || printf '%s' "$CODE_B64" | base64 -D)"
echo "=============================================================="
echo ""
echo "Recopie le proces-verbal EN ENTIER dans ton compte rendu, section 10, avec tout ce que la mission demande pour l'epreuve."
echo "Ton ancienne memoire est dans .amnesie-tf-003/, garde-la, tu la compareras a la neuve pour le compte rendu."
exit 0
