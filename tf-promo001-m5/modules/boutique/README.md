# Module boutique

Gere une seule boutique nginx : un conteneur Docker, nomme `web` dans le code.
L'image et le reseau partages restent geres a la racine (avec le coffre de la
mission 3) ; le module recoit leur reference en entree, il ne les cree jamais
lui-meme. Ainsi plusieurs appels de ce module ne recreent ni la meme image, ni
le meme reseau.

## Entrees

| Entree        | Type            | Ce qu'elle recoit                                   |
|----------------|-----------------|------------------------------------------------------|
| nom            | string          | Le nom reel du conteneur Docker                      |
| image          | string          | La reference exacte d'image transmise par la racine   |
| reseau         | string          | Le nom du reseau deja gere a la racine                |
| port           | number          | Le port externe de la boutique                        |
| page           | string          | Le contenu exact de la page HTML                      |
| cle            | string sensible | La cle factice CLE_CLIENT utilisee depuis la mission 2|
| redemarrage    | string          | La politique de redemarrage Docker                     |

## Sorties

- `nom` : le nom Docker du conteneur
- `identifiant` : l'identifiant Docker du conteneur
- `adresse` : l'URL de la boutique, sous la forme http://localhost:PORT

## Exemple d'appel

```hcl
module "boutiques" {
  source   = "./modules/boutique"
  for_each = var.boutiques

  nom         = each.value.nom
  image       = docker_image.nginx.image_id
  reseau      = docker_network.epreuve.name
  port        = each.value.port
  page        = each.value.page
  cle         = var.cle
  redemarrage = var.redemarrage
}
```

Chaque clé du catalogue `boutiques` devient une instance distincte et durable du module, suivie séparément dans le state (`module.boutiques["<clé>"]`).
