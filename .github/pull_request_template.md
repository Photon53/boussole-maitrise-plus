<!-- Modèle de pull request — voir AGENTS.md § 2 et § 7. Base : develop, jamais main. -->

## Issue liée

<!-- AGENTS.md § 2.5 : `Refs #N` par défaut. `Closes #N` seulement si la PR traite entièrement l'issue ; il ne ferme
     rien à la fusion dans `develop` (la fermeture automatique ne vaut que vers `main`) : une personne ferme l'issue. -->

Refs #

## Objet

<!-- Ce que fait la PR, et ce qu'elle ne fait pas. Une PR = une issue, petite et relisible. -->

## Tests lancés

<!-- Depuis la racine du dépôt (AGENTS.md § 3). Ne jamais cocher un test non lancé : écrire « non exécuté »,
     la raison et le job de CI qui le vérifie, et laisser la PR en brouillon jusqu'à la CI verte. -->

- [ ] `pip install -e "./engine[dev]" -e "./api[dev]"` (environnement virtuel du projet)
- [ ] `(cd web && npm ci --no-audit --no-fund)`
- [ ] `(cd api && python -m app.contenu verifier)` — et `(cd api && python -m app.contenu inventaire)` si `contenu/` change
- [ ] `(cd engine && pytest -q)`
- [ ] `(cd api && pytest -q -W ignore::DeprecationWarning)`
- [ ] `(cd web && npm audit --omit=dev --audit-level=high)`
- [ ] `(cd web && npm test)`
- [ ] `(cd web && npm run build)`
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
- [ ] Aucun nom de famille ni e-mail d'enfant ou d'élève introduit (décision RGPD-1, AGENTS.md § 5)
- [ ] Si un champ nominatif est ajouté : décision tracée dans `docs/DECISIONS.md` et `docs/RGPD.md` mis à jour

## Droits d'auteur

- [ ] Aucun fichier issu de `sources/` (photos, extraits de manuels) dans le diff
- [ ] Chaque contenu ajouté renseigne son registre : `source`, `source_url`, `licence_source`, `adaptation`

## Sécurité

- [ ] Aucun secret dans le diff (`.env`, clé, jeton, identifiant GCP)
- [ ] Aucun `eval` / `exec` / `subprocess` ajouté dans `api/` ou `engine/`

## Agent IA

- [ ] PR produite ou assistée par un agent — nom réel de l'agent (jamais celui d'un autre) : 
- [ ] Commits avec `Agent: <nom>` et `Refs: #N` (AGENTS.md § 2.1)
- [ ] Commentaire de suivi posté sur l'issue (AGENTS.md § 2.4)

## Relecture

- [ ] Base `develop` (jamais `main`)
- [ ] CI verte (jobs « Moteur, API et contenu », « Front », « Terraform DEV »)
- [ ] Une personne relit et fusionne — l'agent ne fusionne jamais
