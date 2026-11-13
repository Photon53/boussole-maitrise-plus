# AGENTS.md — instructions aux agents IA

Ce fichier est la **référence** pour tout agent IA (DeepSeek, Claude, Codex, autre) qui modifie ce dépôt.

> **Version 2 — 13/11/2026.** Correction après deux revues de la version 1 (PR #84) : attribution générique, listes explicites de scripts, parité réelle avec la CI, exceptions d'en-tête, hiérarchie des consignes, écarts documentés.

## Historique

| Version | Date | Changement |
|---|---|---|
| v1 | 13/11/2026 | Première rédaction (PR #84, fusionnée) |
| v2 | 13/11/2026 | Attribution générique à l'agent réel ; scripts nommés au lieu de motifs ; commandes CI exactes ; exceptions d'en-tête ; `Closes`/`Refs` ; hiérarchie des consignes ; RGPD et « solution » reformulés ; `SuppressionInterdite` cité |

---

## 0. Hiérarchie des consignes

| Document | Autorité |
|---|---|
| `AGENTS.md` (ce fichier) | **règles de travail des agents** : droits, traçabilité, tests, Git |
| `docs/ARCHITECTURE.md` | architecture et invariants techniques |
| `docs/DECISIONS.md` | décisions tranchées, avec leur code (`SEC-D…`, `V2-D…`, `DEV-D…`) |
| `docs/CONSIGNES-DEVELOPPEUR.md` | conventions de développement humaines |
| `README.md`, `docs/CONTENU.md`, `docs/RGPD.md`, `docs/CAHIER-DES-CHARGES-V2.md` | domaines respectifs |

Un futur `CLAUDE.md` (branche `outillage/issue-63-claude-github-action`) ou tout autre fichier de
consignes **renvoie vers ce document** et ne le duplique pas. Une contradiction entre deux documents
se **signale dans l'issue** ; « la règle la plus restrictive » ne tranche pas un désaccord de fond,
c'est le propriétaire qui tranche.

---

## 1. Règles absolues

### 1.1 Toujours interdit

| Interdit | Pourquoi |
|---|---|
| `git push` direct sur `main` ou `develop` | toute modification passe par une PR relue |
| `terraform apply` | le déploiement DEV passe par GitHub Actions et WIF |
| Fusionner une PR | une personne relit et fusionne |
| Modifier les protections de branche, les secrets, les règles IAM | décisions du propriétaire |
| Modifier `.github/workflows/**` sans issue dédiée | la CI est le contrat de qualité |
| Supprimer une question | elle s'archive (`archivee`) |
| `eval`, `exec`, `os.system`, `subprocess` dans `engine/` ou `api/` | la correction est un parseur `ast` à liste blanche |
| Renommer `pkp` / `PKP_*` | conservés pour compatibilité (`MIGRATION.md`) |
| Versionner `sources/` | photos et extraits de manuels (droit d'auteur) |
| Lire ou écrire `deploy/.env`, une clé de compte de service, `PKP_SECRET_KEY` de production | l'agent n'en a pas besoin |

### 1.2 Scripts — listes explicites

**Interdit d'exécuter** (ils touchent au cloud, aux VM, aux sauvegardes ou aux secrets) :

```
deploy/*.sh
deploy/vm/boussole-dev-sync
scripts/bootstrap-gcp-dev.sh
scripts/boussole-dev.sh
scripts/deployer-dev-iap.sh
scripts/dev-publier-version.sh
scripts/reprise-terraform-dev.sh
scripts/terraform-dev-cloudshell.sh
scripts/wif-dev-comptes-separes.sh
scripts/audit-dev-compte-compute.sh
```

**Autorisé** :

| Commande | Réserve |
|---|---|
| `scripts/installer-dev.sh`, `scripts/installer-dev.ps1` | **détruit `api/pkp.db`** (`rm -f`) et recrée la base de démo : ne jamais lancer sur une base à conserver ; vérifier le chemin avant |
| `scripts/tests.sh`, `scripts/tests.ps1` | tests locaux |
| `scripts/test-dev-publier-version.sh` | test contre un faux GCS, sans accès cloud (CI) |
| `scripts/tests/test-controle-acces-sauvegardes.sh` | test simulé (CI) |
| `deploy/vm/tests/*.sh` | tests simulés, sans VM (CI) |
| `bash -n` sur un script | vérification de syntaxe, aucune exécution |
| `terraform fmt -check -recursive`, `terraform init -input=false -backend=false`, `terraform validate` | aucun état, aucun identifiant |

Tout autre script : **lire et vérifier ses effets ; demander une décision uniquement s'ils dépassent
le périmètre autorisé ou restent ambigus**. Un motif `*dev*` ne suffit pas à décider :
`installer-dev.sh` et `deployer-dev-iap.sh` se ressemblent et n'ont pas le même danger.

---

## 2. Traçabilité

Chaque production (code, configuration, documentation) est **référencée à l'issue** et **attribuée à
l'agent qui l'a produite**. Aucun agent n'attribue sa production à un autre : Claude indique Claude,
Codex indique Codex, DeepSeek indique DeepSeek. Le champ `Agent: <nom>` est une attribution
déclarative, pas une signature cryptographique.

### 2.1 Le commit

```
type(portée): description courte (#N)

Corps facultatif : ce qui change, pourquoi, ce qui n'est pas fait.

Agent: <nom de l'agent>
Refs: #N
```

- Types utilisés : `feat`, `fix`, `infra`, `ci`, `docs`, `test`, `ops`, `security`.
- Messages en **français**, accents compris.
- Le numéro d'issue est obligatoire dès qu'il existe.

### 2.2 L'en-tête du fichier nouveau

Tout fichier **source ou de configuration créé** porte une référence en première ligne exploitable :

```python
# Issue #65 — Pipeline DEV (<agent>)
```

```javascript
// Issue #65 — Pipeline DEV (<agent>)
```

```yaml
# Issue #65 — Pipeline DEV (<agent>)
```

**Exceptions** — formats qui n'acceptent pas de commentaire libre, ou dont la première ligne est
signifiante :

| Cas | Règle |
|---|---|
| **JSON** (`package.json`, `*.json`) | aucun commentaire possible : la traçabilité passe par le commit et la PR |
| **Scripts shell** | le shebang reste **ligne 1** ; l'en-tête va en ligne 2 |
| **Migrations Alembic** | conserver les métadonnées générées (`Revision ID`, `Revises`, `Create Date`) ; ajouter la référence dans la docstring, sans la remplacer |
| **Fichiers générés** (`package-lock.json`, `docs/CONTENU-INVENTAIRE.md`, `migrations/versions` générées) | ne pas éditer à la main : régénérer, la traçabilité est dans le commit |
| **Données pédagogiques** (`contenu/**/*.yaml`) | pas d'en-tête : 154 fichiers annotés seraient du bruit ; traçabilité par commit et PR |

### 2.3 La pull request

Titre identique au commit. Corps rempli avec `.github/pull_request_template.md`, section « Agent »
renseignée. **Base : `develop`**, jamais `main`.

### 2.4 Le commentaire dans l'issue

Après ouverture de la PR, poster un commentaire sur l'issue traitée :

```markdown
## Traitement — PR #<numéro>

**Ce qui a été fait**
- …

**Fichiers modifiés**
- `chemin/fichier.py`

**Tests exécutés**
- `(cd engine && pytest -q)` → N passed
- ou : **non exécuté** — raison, et vérifications attendues en CI

**Reste à faire / limites**
- …

---
<sub>🤖 Produit par **<agent>** (<outil>), <date>.</sub>
```

### 2.5 `Closes` ou `Refs`

- `Closes #N` quand la fusion doit clore l'issue : la fermeture résulte de la **fusion humaine**,
  pas d'une action de l'agent. Ce n'est donc pas une violation du « l'agent ne fusionne pas ».
- `Refs #N` pour un **ticket de décision** (licence, offre, politique de données) : l'issue ne se
  ferme que sur décision explicite du propriétaire.

---

## 3. Environnement et parité avec la CI

| Élément | Version |
|---|---|
| Python | **3.11 minimum** (CI : 3.12) |
| Node.js | **20** |
| Installation locale | `bash scripts/installer-dev.sh` (**détruit `api/pkp.db`**, cf. § 1.2) |
| Tests locaux | `bash scripts/tests.sh` |

Les commandes ci-dessous se lancent **depuis la racine du dépôt**, chacune dans un sous-shell — un
`cd api` suivi d'un `cd engine` échouerait, `engine/` n'étant pas dans `api/`.

### 3.1 Installation (job Python et Front)

```bash
pip install -e "./engine[dev]" -e "./api[dev]"
(cd web && npm ci --no-audit --no-fund)
```

### 3.2 Job « Moteur, API et contenu »

```bash
(cd api && python -m app.contenu verifier)
(cd engine && pytest -q)
(cd api && pytest -q -W ignore::DeprecationWarning)
```

### 3.3 Job « Front »

```bash
(cd web && npm audit --omit=dev --audit-level=high)
(cd web && npm test)
(cd web && npm run build)
```

### 3.4 Job « Terraform DEV »

```bash
(cd infrastructure/terraform/dev && terraform fmt -check -recursive)
(cd infrastructure/terraform/dev && terraform init -input=false -backend=false)
(cd infrastructure/terraform/dev && terraform validate)
for f in scripts/*.sh deploy/*.sh infrastructure/terraform/dev/*.sh; do bash -n "$f"; done
bash scripts/test-dev-publier-version.sh
bash -n deploy/vm/boussole-dev-sync
bash deploy/vm/tests/test-boussole-dev-sync.sh
bash deploy/vm/tests/test-refus-deploiement-manuel.sh
bash scripts/tests/test-controle-acces-sauvegardes.sh
```

### 3.5 Quand les tests locaux sont impossibles

Ouvrir la PR **en brouillon** avec la mention « non exécuté », la raison (environnement, dépendance
absente, temps), et les vérifications attendues en CI. **Ne jamais cocher un test non lancé comme
réussi.**

---

## 4. Git

| Règle | Valeur |
|---|---|
| Branche de base | `develop` |
| Nom de branche | `<type>/issue-<n>-<sujet>` — ex. `fix/issue-65-liste-releases` |
| Taille | une PR = une issue, petite et relisible |
| Force-push | interdit sur une branche avec PR ouverte |
| Attribution | `Agent: <nom>` obligatoire (voir § 2.1) |

---

## 5. Invariants du projet

| Invariant | Détail |
|---|---|
| `engine/` reste pur | n'importe ni FastAPI ni SQLAlchemy ; conversion via `api/app/db/conversions.py` |
| Modèle modifié ⇒ migration | `alembic revision --autogenerate`, **relue** ; `sa.false()` et non `sa.text('0')` ; `test_migrations_a_jour_avec_les_modeles` échoue sinon |
| Question jamais supprimée | colonne `archivee` **et** garde ORM `SuppressionInterdite` (`api/app/db/models.py`), plus `ondelete="RESTRICT"` sur `reponse.question_id` — c'est la garde ORM qui fait échouer les tests |
| Pas de solution avant la réponse | `QuestionPublique` ne contient jamais `solution` ; `ReponseHistorique` la renvoie **après** réponse ; `QuestionEnseignant` la contient pour les enseignants, sous réserve des habilitations |
| Correction sans `eval` | parseur `ast`, liste blanche, saisie ≤ 200 caractères |
| Style | UTF-8, LF, indentation 4 (Python) / 2 (JS, JSON, CSS, HTML, YAML), CRLF pour `.ps1`/`.bat` (`.editorconfig`) |
| Langue | code métier, documentation, commits et interface **en français** |

### 5.1 Écart connu à ne pas présenter comme un invariant

`docs/RGPD.md` décrit l'élève comme identifié par son prénom seul. **Le code va plus loin depuis la V3** :

- `EnfantSaisi.nom` et `EnfantModification` acceptent un **nom facultatif** (`api/app/schemas.py`) ;
- `IdentiteResponsable` accepte nom et prénom du responsable légal.

Ce n'est donc pas un invariant déjà tenu, mais **une politique à trancher** : soit le nom reste
facultatif et il faut l'assumer dans `docs/RGPD.md`, soit il est retiré. L'agent ne tranche pas ; il
signale. Règle provisoire : **ne pas ajouter de donnée nominative nouvelle** sans décision.

### 5.2 Droit d'auteur

Ne jamais versionner `sources/` (photos, extraits de manuels). Exception : `referentiels/sources/`
(textes officiels du BO, suivis par Git et vérifiés par empreinte). Tout contenu de `contenu/**/*.yaml`
renseigne `source`, `source_url`, `licence_source`, `adaptation` (`docs/CONTENU.md`).

---

## 6. Lecture obligatoire avant d'agir

1. `README.md`
2. `docs/ARCHITECTURE.md`
3. `docs/CONTENU.md`
4. `docs/RGPD.md`
5. `docs/CAHIER-DES-CHARGES-V2.md`
6. `docs/DECISIONS.md` — décisions tranchées, préfixes `SEC-D`, `V2-D`, `DEV-D`
7. `docs/CONSIGNES-DEVELOPPEUR.md`

Selon le sujet : `docs/DEPLOIEMENT.md`, `docs/exploitation/`, `docs/audit/`.

---

## 7. Définition de « terminé »

- [ ] Les commandes du § 3.2 et § 3.3 passent (ou « non exécuté » justifié en brouillon)
- [ ] La CI est verte sur la PR
- [ ] Migration fournie et relue si un modèle a changé
- [ ] Aucun secret, aucune donnée nominative nouvelle non décidée, aucun fichier `sources/` dans le diff
- [ ] Registre des sources rempli pour tout contenu ajouté
- [ ] Commit, en-tête de fichier, PR et commentaire d'issue conformes au § 2, attribués à **l'agent réel**
- [ ] `Closes #N` ou `Refs #N` choisi selon le § 2.5

---

## 8. Ce que l'agent ne décide pas seul

- Les choix produit, tarifaires, juridiques et de politique de données (offres, licence, RGPD, CGI).
- La fusion d'une PR.
- Les protections de branche, secrets, règles IAM, environnements.
- La validation pédagogique : un agent peut **signaler** un problème, jamais valider à la place d'un
  professeur.

---

## 9. Signaler un blocage

Ne pas contourner : commenter l'issue avec le blocage, les options et une recommandation. Le
propriétaire tranche.

---

<sub>🤖 Rédigé par **DeepSeek** (DeepSeek Harness), version 1 le 13/11/2026 (PR #84). Version 2 corrigée par **DeepSeek** après les deux revues du 13/11/2026.</sub>
