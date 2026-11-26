# Politique de versionnement et de mise en production

**Statut : proposition en revue — ticket #229 / PR #230.** Applicable à toutes les composantes du projet et à tous les contributeurs (humains, agents IA, API, front, moteur, contenus, base de données, CI/CD et exploitation) après validation. Ce document ne constitue pas une autorisation de déployer.

## 1. Deux produits, deux historiques de versions

- **PKP Éducation (associatif)** : tags `pkp-vMAJOR.MINOR.PATCH`, par exemple `pkp-v1.0.0`.
- **Boussole Maîtrise+** : tags `boussole-vMAJOR.MINOR.PATCH`, par exemple `boussole-v1.0.0`.
- Les versions progressent indépendamment : une mise à jour de Boussole ne change pas automatiquement la version PKP.
- Ne pas supposer qu'une version historique est déjà publiée : inventorier les tags existants avant de fixer la première version officielle.
- Les tags doivent identifier un commit immuable et la provenance du dépôt. Si les deux produits vivent dans des dépôts distincts, consigner explicitement le dépôt d'origine ; éviter toute ambiguïté entre tags.

## 2. Sémantique

- **MAJOR** : rupture de compatibilité, changement de contrat API/données nécessitant migration incompatible.
- **MINOR** : nouvelle fonctionnalité compatible.
- **PATCH** : correctif compatible, y compris correctif de sécurité.
- **Préversion** : `pkp-v1.2.0-rc.1` ou `boussole-v1.2.0-rc.1` ; ne pas traiter une RC comme une version de production validée.
- Toute modification de schéma doit préciser sa compatibilité et son plan de retour arrière ; une migration irréversible nécessite un plan de restauration et une décision explicite.

## 3. Circuit obligatoire GO / NO-GO

1. Préparer une PR dédiée avec périmètre, risques, tests et migrations.
2. Exécuter les contrôles automatiques et une recette sur environnement approprié.
3. Préparer le dossier de livraison : produit, version candidate, commit SHA complet, image/digest, migrations, sauvegarde, plan de rollback et responsables.
4. Obtenir un **GO humain explicite** ; un agent IA ne s'auto-autorise pas à publier.
5. Créer le tag signé/protégé selon les capacités et politiques GitHub retenues, puis la release associée, uniquement après validation.
6. Déployer **l'artefact exact** validé, pas une branche mouvante ; vérifier la santé, les droits et les parcours métier.
7. Enregistrer version réellement déployée, environnement, date UTC, SHA, digest, auteur de l'approbation et résultat.
8. En cas de NO-GO, ne rien déployer. En cas d'incident, appliquer le rollback documenté, en tenant compte des migrations et données.

## 4. Isolation associative stricte

Le circuit PKP ne doit publier **aucune information commerciale** : prix, paiement, abonnement, facturation, secrets de prestataire ou fonctionnalité commerciale. Les références techniques nécessaires au filtrage doivent rester minimales et ne pas divulguer de données sensibles. Vérifier le code, les assets, les variables exposées, les routes API, les migrations, les données de démonstration et les artefacts construits. Un contrôle de texte seul n'est pas une garantie suffisante : revue humaine et tests fonctionnels obligatoires.

## 5. Registre de déploiement

Un enregistrement par livraison, conservé dans un registre de production protégé :

| Champ | Exemple indicatif |
|---|---|
| Produit / environnement | PKP / PROD Oracle |
| Version | `pkp-v1.0.0` |
| Dépôt et SHA complet | URL GitHub + SHA |
| Artefact | digest immuable de l'image |
| Migrations | liste et compatibilité |
| Recette / CI | URL des résultats |
| GO humain | approbateur, date UTC, lien |
| Déploiement | date UTC, résultat et contrôles post-déploiement |
| Retour arrière | version précédente, procédure et validation |

**Les exemples ne sont pas des versions réellement publiées.**

## 6. Contrôles à automatiser

- Refuser un tag dont le préfixe ne correspond pas au produit cible ou dont le format est invalide.
- Refuser une version déjà utilisée, un SHA non approuvé, des tests en échec, un GO manquant ou un rollback non documenté.
- Vérifier que le digest déployé est celui testé et approuvé.
- Vérifier la séparation des secrets, permissions, runners et environnements.
- Bloquer toute fuite commerciale dans l'artefact PKP, en complément d'une revue.
- Enregistrer le résultat de la publication et alerter en cas d'écart entre tag, image et version exposée par l'application.

**Attention :** ces contrôles sont des exigences cibles. Ils ne sont pas déclarés opérationnels tant que les workflows et leurs tests ne sont pas effectivement livrés et vérifiés.
