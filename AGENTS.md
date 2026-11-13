# AGENTS.md — instructions aux agents IA

Ce fichier s'applique à **tout agent IA** (DeepSeek, Claude, Codex, autre) qui modifie ce dépôt.
Il complète `README.md` et `docs/ARCHITECTURE.md` ; en cas de contradiction, **la règle la plus
restrictive l'emporte** et l'ambiguïté doit être signalée dans l'issue avant d'agir.

> Dernière mise à jour : 13/11/2026 — issue #83.

---

## 1. Règles absolues

Ces points ne se négocient pas et ne demandent pas d'arbitrage : ils sont déjà tranchés.

| Interdit | Pourquoi |
|---|---|
| `git push` direct sur `main` ou `develop` | toute modification passe par une PR relue |
| `terraform apply` | le déploiement DEV passe par GitHub Actions et WIF, jamais par un poste |
| Lancer `deploy/*.sh`, `scripts/*gcp*`, `scripts/*dev*`, `scripts/boussole-dev.sh` | ces scripts touchent au cloud, aux VM ou aux secrets |
| Manipuler des secrets : `deploy/.env`, `PKP_SECRET_KEY` de production, clé de compte de service | l'agent n'en a pas besoin et ne doit jamais les lire ni les écrire |
| Modifier `.github/workflows/**` sans issue dédiée | la CI est le contrat de qualité du dépôt |
| Supprimer une question | une question s'archive (`archivee`), elle ne disparaît jamais |
| `eval`, `exec`, `os.system`, `subprocess` dans `engine/` ou `api/` | la correction est un parseur `ast` à liste blanche |
| Renommer `pkp` / `PKP_*` | conservés pour compatibilité (voir `MIGRATION.md`) |
| Versionner `sources/` | photos et extraits de manuels : droit d'auteur (voir § 5) |

**Autorisé** : `terraform fmt`, `terraform validate`, les scripts de test (`scripts/tests.sh`,
`scripts/installer-dev.sh`), les commandes `gh` en lecture, la création d'issues et de PR.

---

## 2. Traçabilité — exigence du propriétaire

Chaque production de l'agent (code, configuration, documentation) doit être **référencée à
l'issue traitée et attribuée à DeepSeek**. Quatre endroits, sans exception pour le code applicatif :

### 2.1 Le commit

```
type(portée): description courte (#N)

Corps facultatif : ce qui change, pourquoi, ce qui n'est pas fait.

Agent: DeepSeek
Refs: #N
```

- Types utilisés dans l'historique : `feat`, `fix`, `infra`, `ci`, `docs`, `test`, `ops`, `security`.
- Messages en **français**, accents compris.
- Le numéro d'issue est **obligatoire** dès qu'il existe.

### 2.2 L'en-tête du fichier nouveau

Tout fichier **source ou de configuration créé** porte, en première ligne, une référence courte :

```python
# Issue #65 — Pipeline DEV (DeepSeek)
```

```javascript
// Issue #65 — Pipeline DEV (DeepSeek)
```

```yaml
# Issue #65 — Pipeline DEV (DeepSeek)
```

Exceptions : fichiers de données pédagogiques (`contenu/**/*.yaml`) — leur traçabilité passe par
le commit et la PR, pas par un commentaire dans 154 fichiers — et fichiers générés.

### 2.3 La pull request

Titre identique au commit. Corps rempli avec `.github/pull_request_template.md`, section « Agent »
renseignée. **Base : `develop`**, jamais `main`.

### 2.4 Le commentaire dans l'issue

Après ouverture de la PR, poster un commentaire sur l'issue traitée, dans ce format :

```markdown
## Traitement — PR #<numéro>

**Ce qui a été fait**
- …

**Fichiers modifiés**
- `chemin/fichier.py`

**Tests exécutés**
- `cd engine && pytest -q` → N passed
- `cd web && npm test` → N passed

**Reste à faire / limites**
- …

---
<sub>🤖 Produit par **DeepSeek** (DeepSeek Harness), <date>.</sub>
```

Un ticket ne se ferme qu'après fusion, et jamais par l'agent seul sur un ticket de décision.

---

## 3. Environnement et commandes

| Élément | Version |
|---|---|
| Python | **3.11 minimum** (la CI utilise 3.12) |
| Node.js | **20** |
| Installation locale | `bash scripts/installer-dev.sh` (crée `.venv` et la base SQLite de démo) |
| Tests complets | `bash scripts/tests.sh` |

Avant chaque PR, exécuter **les mêmes commandes que la CI** :

```bash
cd api    && python -m app.contenu verifier
cd engine && pytest -q
cd api    && pytest -q -W ignore::DeprecationWarning
cd web    && npm test && npm run build && npm audit --omit=dev --audit-level=high
```

Une PR dont la CI est rouge ne se demande pas en relecture.

---

## 4. Git

| Règle | Valeur |
|---|---|
| Branche de base | `develop` |
| Nom de branche | `<type>/issue-<n>-<sujet>` — ex. `fix/issue-65-liste-releases` |
| Taille | **une PR = une issue**, petite et relisible |
| Fusion | jamais par l'agent : une personne relit et fusionne |
| Force-push | interdit sur une branche partagée (une PR ouverte) |

---

## 5. Invariants du projet

Ces règles sont vérifiées par les tests ou par la CI ; les casser fait échouer la PR.

| Invariant | Détail |
|---|---|
| `engine/` reste pur | n'importe ni FastAPI ni SQLAlchemy ; la conversion passe par `api/app/db/conversions.py` |
| Modèle modifié ⇒ migration | `alembic revision --autogenerate`, **relue à la main** ; utiliser `sa.false()` et non `sa.text('0')`, sinon PostgreSQL refuse ; `test_migrations_a_jour_avec_les_modeles` échoue sinon |
| Question jamais supprimée | colonne `archivee`, contrainte `RESTRICT` depuis `reponse` |
| Solution jamais exposée | `QuestionPublique` ne contient jamais la solution ; seul `ResultatReponse` la renvoie |
| Correction sans `eval` | parseur `ast`, liste blanche de nœuds, saisie ≤ 200 caractères |
| RGPD | élève identifié par prénom + code classe + code personnel haché ; aucune donnée nominative supplémentaire, aucun e-mail élève (`docs/RGPD.md`) |
| Droit d'auteur | ne jamais versionner `sources/` (photos, extraits de manuels) ; exception : `referentiels/sources/` (textes officiels BO). Tout contenu de `contenu/**/*.yaml` remplit le registre des sources : `source`, `source_url`, `licence_source`, `adaptation` (`docs/CONTENU.md`) |
| Style | UTF-8, fins de ligne LF, indentation 4 espaces (Python), 2 (JS/JSX/JSON/CSS/HTML/YAML), CRLF pour `.ps1`/`.bat` (`.editorconfig`) |
| Langue | code métier, documentation, commits et messages d'interface **en français** |

---

## 6. Lecture obligatoire avant d'agir

1. `README.md`
2. `docs/ARCHITECTURE.md`
3. `docs/CONTENU.md`
4. `docs/RGPD.md`
5. `docs/CAHIER-DES-CHARGES-V2.md` — périmètre et décisions ouvertes

Et selon le sujet : `docs/DEPLOIEMENT.md` (infra), `docs/audit/` (sécurité), `docs/exploitation/`
(exploitation).

---

## 7. Définition de « terminé »

- [ ] Les quatre commandes de test du § 3 passent en local
- [ ] La CI est verte sur la PR
- [ ] Migration fournie et relue si un modèle a changé
- [ ] Aucun secret, aucune donnée personnelle, aucun fichier `sources/` dans le diff
- [ ] Le registre des sources est rempli pour tout contenu ajouté
- [ ] Commit, en-tête de fichier, PR et commentaire d'issue conformes au § 2
- [ ] La PR est liée à l'issue (`Closes #N` quand la fusion doit la fermer)

---

## 8. Ce que l'agent ne décide pas seul

- Les choix produit, tarifaires et juridiques (offres, licence, RGPD, CGI) : ce sont des décisions
  du propriétaire, éventuellement avec un conseil externe.
- La fusion d'une PR.
- La modification des protections de branche, des secrets, des règles IAM ou des environnements.
- La validation pédagogique d'un contenu : un agent peut signaler, jamais valider à la place d'un
  professeur.

---

## 9. Signaler un blocage

Si une règle empêche d'avancer, **ne pas contourner** : ouvrir un commentaire dans l'issue avec
le blocage, les options et la recommandation. Le propriétaire tranche.

---

<sub>🤖 Rédigé par **DeepSeek** (DeepSeek Harness) pour l'issue #83, 13/11/2026.</sub>
