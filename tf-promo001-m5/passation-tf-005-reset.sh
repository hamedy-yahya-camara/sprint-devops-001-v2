#!/bin/bash
# Mission 5 Terraform — contrôles relançables et Reset sans suppression.
# Compatible Bash 3.2+. Ne lance ni init, ni apply, ni destroy, ni commande Docker.
# Écrit uniquement de nouveaux dossiers dans .passation-tf-005 du projet courant.
set -u
set -o noclobber
umask 077
export LC_ALL=C

base='.passation-tf-005'
action=${1:-menu}
attempt=''

fail() { printf 'REFUS : %s\n' "$*" >&2; exit 1; }
help_text() {
  printf '%s\n' 'Passation M5 : lance ce script depuis la racine de ton projet.' \
    'Sans argument : menu [1] Tester [2] Voir les résultats [0] RESET [q] Quitter.' \
    'Actions directes : tester, etat, reset, aide.' \
    'Reset crée une nouvelle tentative à 0/5 ; toutes les anciennes preuves restent.' \
    'Reset ne restaure ni le code, ni le state, ni les conteneurs.' \
    'Les 5 contrôles ne remplacent pas les preuves humaines des actes de la mission.'
}

[[ $# -le 1 ]] || fail 'Une seule action est acceptée.'
case "$action" in
  aide|-h|--help) help_text; exit 0;;
  menu|tester|etat|reset) ;;
  *) fail 'Action inconnue. Utilise aide.';;
esac

if [[ "$action" == menu ]]; then
  printf '%s\n' 'OPÉRATION PASSATION' '[1] Lancer / relancer les 5 contrôles' \
    '[2] Voir les derniers résultats' '[0] RESET : nouvelle tentative, anciennes preuves conservées' \
    '[q] Quitter'
  printf 'Ton choix : '
  IFS= read -r choice || exit 0
  case "$choice" in
    1) action=tester;; 2) action=etat;; 0) action=reset;; q|Q) exit 0;;
    *) fail 'Choix inconnu. Relance le menu.';;
  esac
fi

[[ ! -L "$base" ]] || fail 'Le dossier de preuves est un lien symbolique.'
[[ ! -e "$base" || -d "$base" ]] || fail 'Le chemin des preuves est occupé par un fichier.'

find_attempt() {
  attempt=''
  for candidate in "$base"/tentative-[0-9][0-9][0-9][0-9][0-9][0-9]; do
    [[ ! -L "$candidate" ]] || fail 'Une tentative est un lien symbolique.'
    [[ -d "$candidate" ]] || continue
    attempt=$candidate
  done
}

find_run() {
  last_run=''
  for candidate in "$attempt"/execution-[0-9][0-9][0-9][0-9][0-9][0-9]; do
    [[ ! -L "$candidate" ]] || fail 'Une exécution est un lien symbolique.'
    [[ -d "$candidate" ]] || continue
    last_run=$candidate
  done
}

state_text() {
  find_attempt
  if [[ -z "$attempt" ]]; then
    printf '%s\n' 'Aucune tentative. Lance tester ou reset.'
    return
  fi
  printf 'Tentative : %s\n' "$attempt"
  find_run
  if [[ -n "$last_run" && -f "$last_run/bilan.txt" && ! -L "$last_run/bilan.txt" ]]; then
    cat "$last_run/bilan.txt"
  else
    printf '%s\n' 'Résultat : 0/5 — contrôles à lancer (ou exécution interrompue).'
  fi
}

if [[ "$action" == etat ]]; then state_text; exit 0; fi

project_found=false
for config in ./*.tf; do
  if [[ -f "$config" ]]; then project_found=true; break; fi
done
[[ "$project_found" == true ]] || fail 'Lance le script depuis la racine du projet, avec ses fichiers .tf.'

[[ -d "$base" ]] || mkdir "$base" || fail 'Impossible de créer le dossier de preuves.'
find_attempt

# Réservation par mkdir : aucun fichier existant n'est remplacé, même à la relance.
new_attempt() {
  local number=1 target suffix
  if [[ -n "$attempt" ]]; then
    suffix=${attempt##*/tentative-}
    number=$((10#$suffix + 1))
  fi
  while [[ "$number" -le 999999 ]]; do
    printf -v target '%s/tentative-%06d' "$base" "$number"
    [[ ! -L "$target" ]] || fail 'Une tentative est un lien symbolique.'
    if [[ ! -e "$target" ]] && mkdir "$target" 2>/dev/null; then
      attempt=$target
      return
    fi
    [[ -e "$target" ]] || fail 'Impossible de réserver une nouvelle tentative.'
    number=$((number + 1))
  done
  fail 'Nombre maximal de tentatives atteint ; conserve ce dossier et utilise une autre copie du projet.'
}

if [[ "$action" == reset ]]; then
  previous=${attempt:-aucune}
  new_attempt
  printf 'Date UTC : %s\nPrécédente : %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$previous" > "$attempt/reset.txt"
  printf 'RESET effectué. Nouvelle tentative : %s\n' "$attempt"
  printf '%s\n' 'Résultat : 0/5 — prêt à relancer les contrôles.' \
    'Anciennes preuves conservées. Code, state et infrastructure inchangés.' \
    'Relance le menu puis choisis 1, ou utilise : bash CHEMIN/passation-tf-005-reset.sh tester'
  exit 0
fi

for dependency in terraform curl; do
  command -v "$dependency" >/dev/null 2>&1 || fail "Commande absente : $dependency. Aucune infrastructure n’a été modifiée."
done
[[ -n "$attempt" ]] || new_attempt
number=1
while :; do
  printf -v run '%s/execution-%06d' "$attempt" "$number"
  [[ ! -L "$run" ]] || fail 'Une exécution est un lien symbolique.'
  if [[ ! -e "$run" ]] && mkdir "$run" 2>/dev/null; then break; fi
  [[ -e "$run" ]] || fail 'Impossible de créer une exécution.'
  number=$((number + 1))
  [[ "$number" -le 999999 ]] || fail 'Nombre maximal d’exécutions atteint.'
done

passed=0
printf 'Contrôles en lecture seule. Preuves : %s\n' "$run"
printf '%s\n' 'Ils ne vérifient pas la persistance SQL, le remplacement applicatif ni la complétude du compte rendu.'

report() {
  local label=$1 code=$2
  if [[ "$code" == 0 ]]; then
    passed=$((passed + 1)); printf 'OK : %s\n' "$label"
  else
    printf 'À CORRIGER : %s (code %s)\n' "$label" "$code"
  fi
}

terraform fmt -check -recursive > "$run/01-format.log" 2>&1
report 'format Terraform' "$?"
terraform validate -no-color > "$run/02-validation.log" 2>&1
report 'validation Terraform' "$?"

# Évite les arguments injectés via la configuration du terminal ; aucun plan n'est appliqué.
(unset TF_CLI_ARGS TF_CLI_ARGS_plan; terraform plan -no-color -input=false -detailed-exitcode) > "$run/03-plan.log" 2>&1
code=$?
if [[ "$code" == 2 ]]; then
  printf '%s\n' 'À CORRIGER : le plan propose des changements ; ce n’est pas un plan vide.'
else
  report 'plan normal sans changement' "$code"
fi

check_http() {
  local output=$1 label=$2 log=$3 url code http_code
  url=$(terraform output -raw "$output" 2> "$run/$log-output.log")
  code=$?
  if [[ "$code" != 0 ]]; then
    printf 'À CORRIGER : output public %s absent ou illisible.\n' "$output"
    return
  fi
  case "$url" in
    http://*|https://*) ;;
    *) printf 'À CORRIGER : %s ne contient pas une URL HTTP(S).\n' "$output"; return;;
  esac
  case "$url" in
    *'@'*|*'?'*|*'#'*|*$'\n'*|*$'\r'*)
      printf 'À CORRIGER : %s doit être une URL publique sans identifiants, paramètres ni fragment.\n' "$output"; return;;
  esac
  # Pas de corps HTML dans les preuves et pas d'URL imprimée ; les logs restent locaux.
  http_code=$(curl -q --fail --silent --show-error --connect-timeout 5 --max-time 20 \
    --output /dev/null --write-out '%{http_code}' -- "$url" 2> "$run/$log-errors.log")
  code=$?
  printf 'HTTP %s\n' "$http_code" > "$run/$log.log"
  if [[ "$code" == 0 && "$http_code" != 200 ]]; then code=1; fi
  report "$label" "$code"
}
check_http url_livredor 'accès HTTP au livre d’or' '04-livredor'
check_http url_statut 'accès HTTP à la page de statut' '05-statut'

printf 'Tentative : %s\nExécution : %s\nRésultat : %s/5\n' "$attempt" "$run" "$passed" > "$run/bilan.txt"
printf '%s\n' 'Ces contrôles techniques ne valident pas à eux seuls les actes de la mission.' >> "$run/bilan.txt"
cat "$run/bilan.txt"
printf '%s\n' 'Corrige puis relance tester ; aucune ancienne preuve ne sera écrasée.' \
  'Pour recommencer le suivi à zéro, choisis 0 dans le menu ou lance reset.' \
  'Les journaux peuvent contenir des informations sensibles : masque-les avant de les partager.'
[[ "$passed" == 5 ]]
