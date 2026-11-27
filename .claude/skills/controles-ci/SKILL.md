---
name: controles-ci
description: Commandes exactes de la CI à lancer en local, bancs simulés autorisés, tests ciblés pendant le développement et lecture économe des journaux. À charger avant de lancer des tests ou d'analyser un échec de CI.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Contrôles et CI

`.github/workflows/ci.yml` fait foi ; si cette liste s'en écarte, corriger cette skill dans la même PR.
Toutes les commandes se lancent depuis la racine, dans `.venv` (`bash scripts/preparer-environnement.sh` l'installe).

## Pendant le développement : ciblé

- Python : `(cd api && pytest -q tests/test_<sujet>.py -x)` ; moteur : `(cd engine && pytest -q -k <motif>)`.
- Front : `(cd web && npx vitest run src/<dossier>/<Composant>.test.jsx)`.
- Pas de suite complète à chaque modification ; pas de relance d'un test inchangé.

## Avant de pousser pour relecture : complet

| Job CI | Commandes |
|---|---|
| Moteur, API et contenu | `(cd api && python -m app.contenu verifier)` · `(cd engine && pytest -q)` · `(cd api && pytest -q -n auto -W ignore::DeprecationWarning)` |
| Front | `(cd web && npm audit --omit=dev --audit-level=high)` · `(cd web && npm test)` · `(cd web && npm run build)` |
| Terraform DEV et bancs (si `infrastructure/`, `scripts/`, `deploy/` changent) | `(cd infrastructure/terraform/dev && terraform fmt -check -recursive && terraform init -input=false -backend=false && terraform validate)` · `for f in scripts/*.sh deploy/*.sh infrastructure/terraform/dev/*.sh; do bash -n "$f"; done` · `bash scripts/test-dev-publier-version.sh` · `bash deploy/vm/tests/test-boussole-dev-sync.sh` · `bash deploy/vm/tests/test-refus-deploiement-manuel.sh` · `bash scripts/tests/test-controle-acces-sauvegardes.sh` |
| Recette Français (PR touchant `api/`, `engine/`, `web/`, `contenu/francais/`) | `(cd api && pytest -q tests/test_francais.py)` (déjà inclus dans la suite API) |

Hors CI, à lancer si le sujet est touché : `bash deploy/sauvegarde/tests/test-sauvegarde-prod.sh` (sauvegardes,
vrai `age`), `bash scripts/tests/test-synchroniser-branche.sh` (script de synchronisation),
`bash scripts/recette/pile-locale.sh` (recette navigateur, skill `recette-accessibilite`).

Inventaires : `test_inventaire_du_depot_a_jour` et `test_inventaire_des_corriges_a_jour` échouent s'ils sont
périmés ; corriger par `(cd api && python -m app.contenu inventaire)` et `(cd api && python -m app.contenu corrections)`.

## Journaux : peu de contexte, aucun échec masqué

`bash scripts/resume-commande.sh <nom> <commande…>` garde le journal complet dans `${TMPDIR:-/tmp}/journaux/<nom>.log`,
n'affiche que la dernière ligne en cas de succès et les lignes d'erreur plus la fin du journal en cas d'échec, et
**renvoie le code de retour de la commande**. Ne jamais tronquer par `| tail` sans conserver le code de retour
(`set -o pipefail` ou ce script). Lire un journal par `grep -n` ciblé, pas en entier, et une seule fois.

Échec en CI : lire d'abord le job en échec seulement (`get_job_logs` avec `failed_only`, peu de lignes de fin),
reproduire en local avec le test ciblé, corriger, puis pousser une seule fois.

## Test impossible en local

Ne jamais le cocher : PR en brouillon, « non exécuté », raison, job CI qui le vérifiera ; relecture demandée
seulement une fois la CI verte.
