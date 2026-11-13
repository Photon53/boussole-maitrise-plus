<!-- Modèle de pull request — voir AGENTS.md § 2 et § 7. Base : develop, jamais main. -->

## Issue liée

<!-- `Closes #N` si la fusion doit fermer l'issue ; `Refs #N` pour une issue de décision ou traitée en plusieurs PR. -->

Closes #

## Objet

<!-- Ce que fait la PR, et ce qu'elle ne fait pas. Une PR = une issue, petite et relisible. -->

## Tests lancés

<!-- Depuis la racine du dépôt (AGENTS.md § 3). Ne jamais cocher un test non lancé : écrire « non exécuté »,
     la raison et le job de CI qui le vérifie, et laisser la PR en brouillon jusqu'à la CI verte. -->

- [ ] `(cd api && python -m app.contenu verifier)`
- [ ] `(cd engine && pytest -q)`
- [ ] `(cd api && pytest -q -W ignore::DeprecationWarning)`
- [ ] `(cd web && npm audit --omit=dev --audit-level=high && npm test && npm run build)`
- [ ] Job « Terraform DEV » et bancs simulés (AGENTS.md § 3), si la PR touche `infrastructure/`, `scripts/` ou `deploy/`

Résultat utile (nombre de tests passés) :

Non exécuté (commande, raison, job de CI qui le vérifie) :

## Migration de base de données

- [ ] Aucune migration
- [ ] Migration fournie et relue à la main — nom : `…`
- [ ] `sa.false()` utilisé pour un booléen (jamais `sa.text('0')`, que PostgreSQL refuse)

## Données personnelles (RGPD)

- [ ] Aucune donnée personnelle nouvelle
- [ ] Données nouvelles décrites et justifiées dans `docs/RGPD.md`
- [ ] Aucun e-mail d'élève ni nouvelle collecte de nom introduits (nom facultatif d'`Enfant` / `Parent` : politique en attente, AGENTS.md § 5)

## Droits d'auteur

- [ ] Aucun fichier issu de `sources/` (photos, extraits de manuels) dans le diff
- [ ] Chaque contenu ajouté renseigne son registre : `source`, `source_url`, `licence_source`, `adaptation`

## Sécurité

- [ ] Aucun secret dans le diff (`.env`, clé, jeton, identifiant GCP)
- [ ] Aucun `eval` / `exec` / `subprocess` ajouté dans `api/` ou `engine/`

## Agent IA

- [ ] PR produite ou assistée par un agent — nom réel de l'agent (jamais celui d'un autre) : 
- [ ] Commentaire de suivi posté sur l'issue (AGENTS.md § 2.4)

## Relecture

- [ ] Base `develop` (jamais `main`)
- [ ] CI verte (jobs « Moteur, API et contenu », « Front », « Terraform DEV »)
- [ ] Une personne relit et fusionne — l'agent ne fusionne jamais
