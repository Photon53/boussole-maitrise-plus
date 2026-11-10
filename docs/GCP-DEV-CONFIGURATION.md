# Configuration GCP DEV existant : mer-boussole-dev

Cette branche configure le projet GCP **déjà créé manuellement**. Ne pas exécuter le script de création de projet de l'ancienne PR.

## Avant toute exécution
1. Vérifier le projet GCP et son compte de facturation.
2. Depuis Cloud Shell, cloner la branche `feature/gcp-dev-configuration` puis exécuter `DEV_PROJECT_ID=mer-boussole-dev bash scripts/bootstrap-gcp-dev.sh`.
3. Le bootstrap demande une confirmation explicite et crée seulement les prérequis dans `mer-boussole-dev`. Il s'arrête si un fournisseur OIDC nommé `github` existe déjà afin de ne pas le modifier à l'aveugle.
4. Créer dans GitHub **Settings > Environments** l'environnement `development`. Limiter les branches autorisées à `develop`, et activer les approbations manuelles si disponibles.
5. Ajouter les variables d'environnement GitHub affichées par le script : `GCP_DEV_PROJECT_ID`, `GCP_DEV_SERVICE_ACCOUNT`, `GCP_WIF_PROVIDER`, `TF_STATE_BUCKET`, `GCP_DEV_ADMIN_MEMBERS_JSON`. Remplacer `YOUR_EMAIL` par le véritable compte Google autorisé.
6. Après fusion de cette PR dans `develop`, déclencher manuellement le workflow `GCP DEV Terraform` depuis la branche `develop` avec `plan`.
7. Relire le plan Terraform, les rôles IAM et les coûts; déclencher `apply` avec la confirmation `mer-boussole-dev` seulement après validation.

## Limites
- Aucun accès GCP direct ni exécution du bootstrap n'ont été réalisés depuis cette PR.
- Terraform n'a pas été validé par exécution. `terraform fmt -check` peut demander un formatage préalable des fichiers hérités.
- La VM privée et Artifact Registry ne constituent pas encore une application DEV déployée.
- Le workflow doit exister sur la branche par défaut pour être déclenchable manuellement selon les règles GitHub Actions; vérifier son accessibilité depuis `develop`.
- Le compte de service Terraform dispose de rôles de provisionnement puissants, mais limités au projet DEV : faire une revue IAM avant exécution.
- Aucun déploiement de production n'est prévu.
