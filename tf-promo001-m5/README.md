# Mission 5 — La passation (Terraform + Docker)

Une pile complète reconstruisible depuis zéro avec un seul `terraform apply` : proxy nginx, livre d'or, PostgreSQL, volume nommé, et une page `/statut` qui réutilise le module boutique du M4.

## Schéma

    navigateur -> 127.0.0.1:8180 -> proxy (nginx)
                                     |-- /        -> livredor:3000 -> postgres:5432 -> volume pgdata
                                     |-- /statut/ -> statut:80 (module boutique)

- Réseau `frontal` : proxy, livredor, statut.
- Réseau `donnees` : livredor, postgres. PostgreSQL n'est pas joignable depuis le proxy.
- Seul le proxy publie un port, sur `127.0.0.1` uniquement.

## Contrat des noms (préfixe `m5-hamedy`)

| Objet | Nom |
|---|---|
| Réseaux | `m5-hamedy-frontal`, `m5-hamedy-donnees` |
| Volume | `m5-hamedy-pgdata` |
| Conteneurs | `m5-hamedy-proxy`, `-livredor`, `-postgres`, `-statut` |
| Port public | 8180 sur 127.0.0.1 |
| Images | `nginx:1.27-alpine`, `postgres:16-alpine`, `livredor-m5:v1` |

## Prérequis

- Docker en fonctionnement, Terraform 1.x, accès au socket `unix:///var/run/docker.sock`.
- L'image applicative `livredor-m5:v1` doit exister sur le moteur Docker utilisé. Elle n'est pas téléchargée par Terraform. Provenance :

      docker pull camarahamedy/livredor-ci:v2
      docker tag camarahamedy/livredor-ci:v2 livredor-m5:v1

  Digest de l'image : `sha256:e6dab936e683576457833cdbcd711a09a508675a7b9cbcf4d9d5ec5e9aaed423`.
  Vérification : `docker run --rm --entrypoint sh livredor-m5:v1 -c "ls /app/node_modules | grep -x pg"` doit afficher `pg`.
- Le fichier `.terraform.lock.hcl` fait partie des sources : il fixe le provider `kreuzwerker/docker`.

## Démarrer depuis zéro

    cp terraform.tfvars.example terraform.tfvars   # puis remplacer le mot de passe (alphanumérique)
    terraform init
    terraform plan
    terraform apply
    terraform output

Pour une autre copie : changer `prefixe` et `port_public` dans `terraform.tfvars`, sans toucher aux fichiers `.tf`.

## Variables

`prefixe`, `port_public`, `image_app`, `image_postgres`, `image_nginx`, `db_nom`, `db_utilisateur`, `db_mot_de_passe` (sensible, sans valeur par défaut).

## Choix de conception

- **Ordre de démarrage** : PostgreSQL a un `healthcheck` (`pg_isready`) et `wait = true`. L'application ne démarre qu'après `healthy`. Elle réessaie aussi 30 fois, toutes les 2 secondes, avant de quitter.
- **Redémarrage** : `unless-stopped` pour tous les conteneurs. Après un redémarrage du moteur Docker, la pile revient seule ; un arrêt volontaire est respecté.
- **Proxy** : `resolver 127.0.0.11 valid=10s` et le nom dans une variable `set`. nginx résout le nom à chaque requête, donc il retrouve une application recréée sans être relancé.
- **Module boutique** : copié du M4 puis modifié dans cette mission seulement. Ajout de `publier_port` (bool, défaut `true`) avec un bloc `dynamic "ports"`. L'adresse de sortie s'adapte. Le `ignore_changes` du M4, qui servait à adopter des conteneurs existants, est retiré.
- **`prevent_destroy` sur le volume** : bloque tout plan qui détruirait ou remplacerait le volume. Limites : il disparaît si on retire le bloc, il ne protège pas d'un `docker volume rm` manuel et ce n'est pas une sauvegarde.
- **Secret** : `sensitive = true` masque l'affichage. Le mot de passe reste en clair dans le state et dans les variables d'environnement du conteneur. Le state, `terraform.tfvars` et les plans ne vont jamais dans Git.

## Les trois pièges

1. **Faux service prêt.** Un conteneur « créé » n'est pas « prêt ». Prévention : healthcheck + `wait = true`. Preuve : logs de l'application `Base de donnees prete.` sans nouvel essai.
2. **Fausse persistance.** Les données doivent vivre dans le volume, pas dans le conteneur. Preuve : le remplacement forcé du conteneur applicatif conserve PostgreSQL, le volume et les messages.
3. **Faux secret caché.** `sensitive` n'est pas du chiffrement. Preuve : le plan affiche `(sensitive value)`, mais le secret reste dans le state ; `docker inspect` complet n'est jamais capturé.

## Résultats des actes

| Acte | Résultat |
|---|---|
| 1. Copie propre (`m5-copie`, port 8280) | `Plan: 9 to add`, `Apply complete! 9 added`, 2 routes en 200, base vide au départ |
| 2. `-replace` du conteneur applicatif | application `8c3ee7f9…` -> `fdd7a73d…`, PostgreSQL `b0942f71…` et volume `m5-copie-pgdata` conservés, message conservé, coupure mesurée : 1 mesure en échec sur 110 (environ 1 s maximum) |
| 3. Codes de sortie | 0 : aucun changement ; 2 : changements (port 8280 -> 8281, seul le proxy est remplacé, non appliqué) ; 1 : erreur, d'après la documentation de `-detailed-exitcode` |
| 4. Cycle de vie | `plan -destroy` : 9 objets, mais refusé : `Instance cannot be destroyed` sur le volume (`prevent_destroy`) |

Le remplacement a été fait avec une boucle `curl` toutes les 0,3 s ; la durée de coupure est donc connue à environ 1,3 s près. Cette expérience prouve que les données sont indépendantes du conteneur applicatif ; elle ne remplace pas un test de restauration.

## Prédictions

À compléter avec mes trois prédictions, notées comme rédigées après l'essai pour l'Acte 2.

## Arrêt, sauvegarde et remise en route

**Exécuté** : `terraform plan -destroy` (refusé par `prevent_destroy`), plan ciblé du proxy seul, remplacement du conteneur applicatif, changement de port en plan seulement.

**Proposé, non exécuté** :
1. Sauvegarde logique : `docker exec m5-hamedy-postgres pg_dump -U livredor livredor > sauvegarde.sql`.
2. Arrêt du service : retrait du proxy puis de l'application, en gardant PostgreSQL et le volume.
3. Test de restauration sur une copie : démarrer une pile neuve, restaurer `sauvegarde.sql`, lire les messages.
4. Destruction réelle seulement après ce test, en retirant `prevent_destroy` de façon délibérée et relue.

Un volume persistant n'est pas une sauvegarde, et une sauvegarde non restaurée n'est pas une restauration vérifiée : aucune restauration n'a été testée dans cette mission.
