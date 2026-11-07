# Boussole Maîtrise+

**La boussole de votre réussite scolaire**

Plateforme d'apprentissage adaptatif destinée au collège et au lycée : mathématiques, anglais et français (activation progressive des domaines).

## Origine du projet

Ce dépôt est la base de la future version commerciale de **Boussole Maîtrise+**. Il reprend le code pédagogique du projet [PKP Math Lycée](https://github.com/Photon53/pkp-math-lycee), sans modifier le dépôt d'origine.

**Attention :** la copie du code ne constitue pas une validation de la mise en production commerciale. Sécurité, conformité RGPD, tests, configuration du déploiement, propriété intellectuelle des ressources et conditions d'utilisation restent à contrôler avant ouverture aux clients.

## Architecture

- `web/` : interface React + Vite (élèves, familles, enseignants, administration).
- `api/` : backend FastAPI, stockage, droits et orchestration pédagogique.
- `engine/` : moteur pédagogique Python indépendant du web.
- `contenu/` et `referentiels/` : supports, exercices et référentiels pédagogiques.
- `deploy/` : conteneurs et déploiement.
- `docs/` : documentation et cahiers des charges.

## Démarrage du développement

- Windows : `powershell -ExecutionPolicy Bypass -File scripts\\installer-dev.ps1`
- Linux/macOS : `bash scripts/installer-dev.sh`
- VS Code : ouvrir `boussole-maitrise-plus.code-workspace` après création ou adaptation de cet espace de travail.
- Tests : `bash scripts/tests.sh` (Linux/macOS) ou `powershell -ExecutionPolicy Bypass -File scripts\\tests.ps1` (Windows).

Les variables internes `PKP_*`, les noms de paquets `pkp-api` et `pkp-engine`, et certains identifiants techniques historiques doivent rester inchangés tant qu'une migration technique testée n'a pas été réalisée. Ils ne font **pas** partie de la marque affichée.

## Historique

Source : `Photon53/pkp-math-lycee`, branche `main` au commit `9530db4724cb37f630221bd59886e60565b6eae9` (6 novembre 2026).

## Marque

**Boussole Maîtrise+** — *La boussole de votre réussite scolaire*.
