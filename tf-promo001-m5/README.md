# Mission 5 Terraform : la passation

## Schema

navigateur -> http://127.0.0.1:8180 -> proxy nginx (port 80, reseau frontal)
  /        -> livre d'or (m5-hamedy-livredor:3000, reseaux frontal + donnees)
  /statut  -> page de statut (m5-hamedy-statut:80, reseau frontal)
livre d'or -> PostgreSQL (m5-hamedy-postgres:5432, reseau donnees)
PostgreSQL -> volume m5-hamedy-pgdata monte sur /var/lib/postgresql/data

Seul le proxy publie un port sur la machine (127.0.0.1:8180).

## Contrat

| Objet | Nom |
|---|---|
| Prefixe | m5-hamedy |
| Reseau frontal | m5-hamedy-frontal |
| Reseau donnees | m5-hamedy-donnees |
| Volume PostgreSQL | m5-hamedy-pgdata |
| Conteneur proxy | m5-hamedy-proxy |
| Conteneur livre d'or | m5-hamedy-livredor |
| Conteneur PostgreSQL | m5-hamedy-postgres |
| Conteneur statut | m5-hamedy-statut |
| Port public | 8180 (127.0.0.1) |
| PostgreSQL | postgres:16-alpine |
| Image applicative | livredor-m5:v1 (construite en local) |
| Image nginx | nginx:1.27-alpine |

## Variables

prefixe, port_public, image_app, image_postgres, image_nginx,
db_nom, db_utilisateur, db_mot_de_passe (sensible, jamais dans le depot).
Voir terraform.tfvars.example.

## Predictions (a remplir avant le premier plan)

1. Ce que Terraform doit creer :
2. Si seul le port public change :
3. Ce qui doit survivre si le conteneur applicatif est remplace :
