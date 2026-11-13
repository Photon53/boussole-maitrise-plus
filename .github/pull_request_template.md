<!-- Modèle de pull request — voir AGENTS.md § 2 et § 7. Base : develop, jamais main. -->

## Issue liée

Closes #

## Objet

<!-- Ce que fait la PR, et ce qu'elle ne fait pas. Une PR = une issue, petite et relisible. -->

## Tests lancés

- [ ] `cd api && python -m app.contenu verifier`
- [ ] `cd engine && pytest -q`
- [ ] `cd api && pytest -q -W ignore::DeprecationWarning`
- [ ] `cd web && npm test && npm run build && npm audit --omit=dev --audit-level=high`

Résultat utile (nombre de tests passés) :

## Migration de base de données

- [ ] Aucune migration
- [ ] Migration fournie et relue à la main — nom : `…`
- [ ] `sa.false()` utilisé pour un booléen (jamais `sa.text('0')`, que PostgreSQL refuse)

## Données personnelles (RGPD)

- [ ] Aucune donnée personnelle nouvelle
- [ ] Données nouvelles décrites et justifiées dans `docs/RGPD.md`
- [ ] Aucun nom de famille ni e-mail d'élève introduit

## Droits d'auteur

- [ ] Aucun fichier issu de `sources/` (photos, extraits de manuels) dans le diff
- [ ] Chaque contenu ajouté renseigne son registre : `source`, `source_url`, `licence_source`, `adaptation`

## Sécurité

- [ ] Aucun secret dans le diff (`.env`, clé, jeton, identifiant GCP)
- [ ] Aucun `eval` / `exec` / `subprocess` ajouté dans `api/` ou `engine/`

## Agent IA

- [ ] PR produite ou assistée par un agent — lequel : 
- [ ] Commentaire de suivi posté sur l'issue (AGENTS.md § 2.4)

## Relecture

- [ ] Base `develop` (jamais `main`)
- [ ] CI verte (jobs « Moteur, API et contenu », « Front », « Terraform DEV »)
- [ ] Une personne relit et fusionne — l'agent ne fusionne jamais
