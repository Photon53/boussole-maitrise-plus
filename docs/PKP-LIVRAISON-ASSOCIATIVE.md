# Circuit de livraison PKP Éducation — proposition (ticket #229)

## Objectif
Isoler la livraison associative PKP Éducation de la livraison Boussole Maîtrise+.
Cette proposition n'active aucun déploiement et ne modifie pas les branches protégées.

## Branches et responsabilités
- `develop` : intégration et tests des changements pédagogiques.
- `main` : branche de livraison Boussole, selon les règles existantes.
- `pkp-education-prod` : **branche cible proposée**, à créer seulement après inventaire et validation du périmètre associatif. Ne pas la créer automatiquement à partir de `develop` sans contrôle du contenu.
- Le dépôt PKP Éducation conserve son propre historique et son circuit de livraison.

## Contrôles obligatoires avant chaque transfert
1. Établir un inventaire explicite des commits, fichiers, migrations et dépendances à transférer.
2. Vérifier les licences, le nom « PKP Éducation », l'absence de secrets et de fonctionnalités non autorisées dans le périmètre associatif.
3. Revoir le diff dans une PR, avec au moins une validation humaine.
4. Exécuter tests API, interface, droits multi-rôles et migrations sur un environnement isolé.
5. Sauvegarder, documenter le SHA déployé et préparer le retour arrière.
6. Autoriser manuellement la publication après recette ; ne jamais déclencher un déploiement de production depuis une PR.

## Critères de sortie
- Branche associative dédiée, protections et CI contrôlées par un administrateur GitHub.
- Flux de sélection reproductible et documenté.
- Recette Français multi-rôles du ticket #228 et tests de non-régression réussis.
- Publication Boussole et PKP indépendante, avec journal des versions et rollback.

## Points à vérifier avant implémentation
- Inventaire réel des workflows GitHub et de leurs permissions.
- État des protections de branches et secrets de déploiement.
- Méthode actuelle de synchronisation vers le dépôt PKP et ses échecs.
- Base technique commune et migrations compatibles avec la production associative.
