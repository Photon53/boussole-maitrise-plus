# Boussole Maîtrise+ — consignes pour Claude Code

> Ces consignes guident Claude ; elles **ne bloquent rien techniquement**. Les vraies barrières sont les
> permissions des workflows, la condition WIF côté GCP et la revue humaine avant toute fusion.

## Projet
Plateforme pédagogique adaptative (collège/lycée) issue de PKP Math Lycée.
- `engine/` : moteur pédagogique (Python)
- `api/` : API FastAPI + Alembic (PostgreSQL en déploiement, SQLite en local)
- `web/` : front React (Vite)
- `contenu/`, `referentiels/` : contenu pédagogique (YAML, PDF)
- `deploy/` : Docker Compose, Caddy ; `infrastructure/terraform/dev/` : GCP DEV

Les identifiants internes `PKP_*`, `pkp-api`, `pkp-engine`, `/pkp` sont conservés volontairement :
ne pas les renommer.

## Vérifier avant de proposer une PR
Mêmes contrôles que `.github/workflows/ci.yml` :
```bash
pip install -e "./engine[dev]" -e "./api[dev]"
(cd api && python -m app.contenu verifier)
(cd engine && pytest -q)
(cd api && pytest -q -W ignore::DeprecationWarning)
(cd web && npm ci --no-audit --no-fund && npm test && npm run build)
```

## Règles de travail
- Partir de `develop`, travailler sur une branche `claude/…`, ouvrir une PR **en brouillon vers `develop`**.
- Ne jamais pousser sur `main` ni sur `develop`, ne jamais fusionner, ne jamais changer la branche par défaut.
- Ne jamais modifier `.github/workflows/` ni `infrastructure/` sans demande explicite dans le ticket.
- Aucun accès GCP : pas de `gcloud`, pas de `terraform apply`, pas d'authentification Google.
- Aucune donnée réelle d'élève, aucun secret dans le code, les logs ou les commentaires.
- Une PR = un ticket ; référencer le ticket (`Refs #N`) ; expliquer ce qui a été testé et ce qui ne l'a pas été.
- Écrire en français (code, commentaires, messages de commit, PR).
