<!-- Modèle de pull request — voir AGENTS.md § 2 et § 7. Base : develop, jamais main. -->

## Issue liée

Closes #
<!-- ou « Refs # » pour un ticket de décision : l'issue ne se ferme que sur décision du propriétaire. -->

## Objet

<!-- Ce que fait la PR, et ce qu'elle ne fait pas. Une PR = une issue, petite et relisible. -->

## Tests lancés

Commandes à exécuter **depuis la racine du dépôt**, chacune dans son sous-shell.

- [ ] `pip install -e "./engine[dev]" -e "./api[dev]"`
- [ ] `(cd api && python -m app.contenu verifier)`
- [ ] `(cd engine && pytest -q)`
- [ ] `(cd api && pytest -q -W ignore::DeprecationWarning)`
- [ ] `(cd web && npm ci --no-audit --no-fund)`
- [ ] `(cd web && npm audit --omit=dev --audit-level=high)`
- [ ] `(cd web && npm test)`
- [ ] `(cd web && npm run build)`

Résultat utile (nombre de tests passés), ou **« non exécuté »** avec la raison :

<!-- Ne jamais cocher un test non lancé. Une PR en brouillon avec justification est acceptable. -->

## Parité CI

- [ ] Le job « Moteur, API et contenu » est couvert par les tests ci-dessus
- [ ] Le job « Front » est couvert
- [ ] Le job « Terraform DEV » est concerné par cette PR → commandes du § 3.4 exécutées

## Migration de base de données

- [ ] Aucune migration
- [ ] Migration fournie et relue à la main — nom : `…`
- [ ] `sa.false()` utilisé pour un booléen (jamais `sa.text('0')`, que PostgreSQL refuse)

## Données personnelles (RGPD)

- [ ] Aucune donnée personnelle nouvelle
- [ ] Aucun nom de famille ni e-mail d'élève introduit
- [ ] Si un champ nominatif est ajouté : décision tracée dans `docs/DECISIONS.md` et `docs/RGPD.md` mis à jour (voir AGENTS.md § 5.1)

## Droits d'auteur

- [ ] Aucun fichier issu de `sources/` (photos, extraits de manuels) dans le diff
- [ ] Chaque contenu ajouté renseigne son registre : `source`, `source_url`, `licence_source`, `adaptation`

## Sécurité

- [ ] Aucun secret dans le diff (`.env`, clé, jeton, identifiant GCP)
- [ ] Aucun `eval` / `exec` / `subprocess` ajouté dans `api/` ou `engine/`

## Agent IA

- [ ] PR produite ou assistée par un agent — **nom réel** : 
- [ ] Commit avec `Agent: <nom>` et `Refs: #N`
- [ ] Commentaire de suivi posté sur l'issue (AGENTS.md § 2.4)

## Relecture

- [ ] Base `develop` (jamais `main`)
- [ ] CI verte (jobs « Moteur, API et contenu », « Front », « Terraform DEV »)
- [ ] Une personne relit et fusionne — l'agent ne fusionne jamais
