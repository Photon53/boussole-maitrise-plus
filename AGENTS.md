# AGENTS.md — règles permanentes des agents IA

S'applique à tout agent (Claude, Codex, DeepSeek…) qui modifie ce dépôt. Une règle a **une seule source** : ce
fichier pour les interdits et les limites d'autonomie, le document de domaine cité pour le reste (il fait foi en
cas d'écart, et ce fichier se corrige). Les procédures détaillées se chargent **à la demande** (§ 5).

## 1. Autonomie et décisions humaines obligatoires

L'agent avance par défaut et décide seul de tout choix technique réversible : architecture dans le périmètre,
ergonomie, design, bugs, refactorisation, conflits Git, tests, découpage des PR, performances, modèles et
sous-agents, organisation des skills et de la documentation, contradiction entre documents sans effet ci-dessous.
Il consigne un choix structurant dans `docs/DECISIONS.md` (« arbitrage d'agent, révisable », date, issue) et
l'annonce en une ligne dans la PR. Présenter des options et attendre sur ces points est une erreur de méthode.

Il ne s'arrête **que** pour :

| Cas | Exemples |
|---|---|
| Coût supplémentaire | service cloud payant, VM, runner, abonnement, licence, minutes CI au-delà du gratuit, API payante |
| Juridique, RGPD | nouvelle donnée personnelle, levée d'une restriction (`PKP_REDACTION_ACTIVE`, `PKP_PDF_FRANCAIS_OUVERT`…), licence, CGU, droit d'auteur incertain |
| Sécurité, accès | secrets, IAM, habilitations, règles de validation, affaiblissement d'un invariant (§ 3) |
| Gouvernance GitHub | protections de branche, contrôles requis, environnements, fusion d'une PR, fermeture d'une issue |
| Production | déploiement, release, GO de production (`docs/VERSIONNING.md`), action sur DEV ou une instance partagée |
| Irréversible | suppression ou migration destructive de données réelles |
| Produit, commerce | offres, prix, périmètre commercial, ouverture publique d'un domaine |
| Pédagogie | validation d'un contenu à la place d'un professeur (V2-D15) |

Dans ce cas : commentaire dans l'issue (problème, impact, recommandation), sans contourner, et poursuite de tout
le travail qui n'en dépend pas.

## 2. Interdits absolus

- `git push` sur `main` ou `develop` ; force-push sur une branche qui porte une PR ; contournement d'une protection.
- `terraform apply`, `plan` sur l'état réel, `init` avec backend (le DEV passe par GitHub Actions et WIF).
- Lire ou écrire un secret : tout `.env`, `PKP_SECRET_KEY` hors démo, clé de compte de service, `*.tfstate` et exports.
- Modifier `.github/workflows/**` sans issue dédiée.
- Supprimer une question (elle s'archive : `archivee`).
- `eval`, `exec`, `os.system`, `subprocess` dans `engine/` ou `api/`.
- Renommer `pkp` / `PKP_*` (`MIGRATION.md`) ; versionner `sources/` (droit d'auteur).
- Lancer un script d'exploitation (Cloud Shell, GCP, VM, IAM, sauvegardes) :
  `deploy/*.sh`, `deploy/vm/boussole-dev-sync`, `scripts/audit-dev-compte-compute.sh`, `scripts/bootstrap-gcp-dev.sh`,
  `scripts/boussole-dev.sh`, `scripts/controle-acces-sauvegardes.sh`, `scripts/deployer-dev-iap.sh`,
  `scripts/dev-publier-version.sh`, `scripts/reprise-terraform-dev.sh`, `scripts/terraform-dev-cloudshell.sh`,
  `scripts/wif-dev-comptes-separes.sh`, `scripts/tester-ihm-gcp.ps1`, `scripts/troubleshooter_iam.py`,
  `scripts/comparer-politique-bucket.py`, et `scripts/recette/*.mjs` pointé vers une instance non locale.
  Tout nouveau script de ce type s'ajoute à cette liste dans sa PR.

**Autorisé** : `scripts/tests.sh`, `scripts/preparer-environnement.sh`, `scripts/synchroniser-branche.sh`,
`scripts/resume-commande.sh`, les bancs simulés (faux `gcloud`, GCS, `docker`) et la pile locale de recette listés
dans la skill `controles-ci`, `bash -n` sur tout script, `terraform fmt|validate` et `init -backend=false`,
`scripts/charge_classe.py` et `scripts/mesure_import.py` contre une base locale de démonstration, `gh` en lecture,
création d'issues et de PR. `scripts/installer-dev.sh` **supprime `api/pkp.db`** : seulement si cette base est
absente ou jetable. Un autre script : lire ses effets avant de le lancer ; le nom ne suffit pas.

## 3. Invariants métier, sécurité et RGPD

| Invariant | Règle (source) |
|---|---|
| Moteur pur | `engine/` n'importe ni FastAPI ni SQLAlchemy ; conversion dans `api/app/db/conversions.py` (ARCH-1) |
| Migration | modèle modifié ⇒ migration Alembic relue à la main, `sa.false()` et non `sa.text('0')` (ARCH-2) |
| Question jamais supprimée | `archivee`, garde ORM `SuppressionInterdite`, clé étrangère `RESTRICT` (ARCH-3) |
| Corrigé protégé | aucune solution envoyée à l'élève avant sa réponse : `QuestionPublique` sans `solution` ; côté adultes, accès par `exiger(permission, domaine)` (ARCH-4) |
| Correction sûre | parseur `ast` à liste blanche, saisie ≤ 200 caractères |
| Mineurs (RGPD-1) | élève : prénom, code classe, code personnel haché, aucun e-mail ; **aucun nom de famille d'enfant** ; identifiant `Lina1` créé par `enfants.identifiant_libre`, jamais réattribué (`docs/RGPD.md`) |
| Isolation, habilitations | toute lecture d'adulte passe par les habilitations et le périmètre (classe, établissement, enfant) ; aucune donnée d'un autre périmètre |
| Validation pédagogique | un agent signale, il ne valide jamais un contenu à la place d'un professeur |
| Sources | tout `contenu/**/*.yaml` remplit `source`, `source_url`, `licence_source`, `adaptation` (`docs/CONTENU.md`) |
| PKP Éducation | nom et spécificités associatives conservés ; aucun prix, paiement, abonnement ni secret commercial (`docs/PKP-LIVRAISON-ASSOCIATIVE.md`) |
| Langue, style | français (code métier, docs, commits, interface, ARCH-6) ; UTF-8, LF, `.editorconfig` |

## 4. Git, traçabilité et réussite

- Branche depuis `develop` à jour : `<type>/issue-<n>-<sujet>` (ou la branche imposée par l'outil). PR vers
  `develop`, jamais `main`. Une PR = un périmètre ; elle ne fusionne ni ne ferme rien elle-même.
- Commit en français : `type(portée): description (#N)`, puis `Agent: <agent réel>` et `Refs: #N`. Les lignes
  imposées par l'outil (`Co-Authored-By`…) s'ajoutent sans remplacer `Agent:`. L'attribution existante ne se réécrit pas.
- Fichier source ou de configuration **créé** : en-tête `Issue #N — Sujet (<Agent>)` en commentaire, après un
  éventuel shebang, encodage, doctype ou docstring imposée. Pas d'en-tête pour JSON, fichiers générés, YAML de
  contenu, fichiers modifiés ; migration Alembic : référence dans la docstring.
- PR : `.github/pull_request_template.md`, section « Agent IA » remplie ; `Refs #N` par défaut (`Closes` ne ferme
  rien vers `develop`). Puis un commentaire de traitement dans l'issue (modèle : skill `integration-git`).
- Avancement : dans l'issue et la PR, **pas** dans un tableau partagé d'un fichier versionné.

**Terminé** quand : contrôles du job concerné passés en local ou sur le SHA exact en CI (jamais coché sans
résultat) ; CI verte ; inventaires régénérés si `contenu/` change ; migration relue si un modèle change ; aucun
secret, aucune donnée personnelle réelle, aucun fichier `sources/` (sauf `referentiels/sources/`) dans le diff ;
traçabilité ci-dessus respectée. Un test impossible en local ⇒ PR en brouillon, « non exécuté », raison, job CI.

## 5. Charger à la demande

Ne pas tout lire avant d'agir : seulement les fichiers, sections et décisions utiles au ticket.

| Sujet | Skill (`.claude/skills/<nom>/SKILL.md`) ou document |
|---|---|
| Branches, PR, synchronisation, conflits, plusieurs agents en parallèle | `integration-git` |
| Commandes CI, bancs simulés, tests ciblés, journaux | `controles-ci` |
| Économie de tokens, choix du modèle, sous-agents | `economie-contexte` |
| Recette navigateur, accessibilité | `recette-accessibilite` |
| Contenus pédagogiques, ajout d'une matière | `contenus-matieres` |
| Sécurité, RGPD, habilitations | `securite-rgpd` |
| Release, livraison Boussole, synchronisation PKP | `livraison-pkp` |
| Architecture, décisions | `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (identifiants préfixés : `ARCH-`, `SEC-D`, `V2-D`, `DEV-D`, `RGPD-`) |
| Vocabulaire métier, périmètre | `docs/CONSIGNES-DEVELOPPEUR.md`, `docs/CAHIER-DES-CHARGES-V2.md` |

Une skill détaille une procédure ; elle n'assouplit jamais les § 1 à 4, qui s'appliquent même si elle n'est pas chargée.

<sub>Numérotation depuis #252 (les anciens renvois restent lisibles) : ancien § 1 → § 2, § 2 et § 4 → § 4,
§ 3 et § 7 → § 4 et skill `controles-ci`, § 5 → § 3, § 6 → § 5, § 8 et § 9 → § 1. Historique : `git log AGENTS.md`.</sub>
