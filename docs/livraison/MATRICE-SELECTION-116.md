# Matrice de sélection — première livraison `develop` → `main` (#116)

> État **en préparation**. Ce document ne vaut ni décision de fusion dans `main`, ni autorisation de
> déploiement (#116, § 5 et § 6). Les décisions marquées **Propriétaire** restent à prendre.

## 0. Instantané

| Élément | Valeur (14/11/2026, recalculer au démarrage de chaque étape) |
|---|---|
| `origin/main` | `90901642773a8e7bc30ec1684f215d0a2363dd8c` |
| `origin/develop` | `805e3af6d6bf30c3e2061124ee36e088683f37d5` |
| Base commune | `2a614051aae097d58bde9fa6e4991bfe43d547c4` (PR #58) |
| Divergence `main...develop` | **1** commit propre à `main`, **114** propres à `develop` (43 entrées en premier parent) |
| Branche de travail | `claude/funny-faraday-u0we0q` (issue de `develop`, contient aussi #114 et #115) |

Commandes de recalcul :

```bash
git fetch origin main develop
git rev-list --left-right --count origin/main...origin/develop
git log --first-parent --format='%h %s' origin/main..origin/develop
git diff --name-status origin/main origin/develop
```

### Quatre niveaux à ne pas confondre

| Niveau | Ce qui le détermine | Exemple |
|---|---|---|
| **Git (`main`)** | contenu de la branche fusionnée | `deploy/vm/`, `.claude/settings.json` peuvent y rester |
| **Contexte de construction** | `.dockerignore` + `COPY` des Dockerfile | `scripts/`, `deploy/`, `docs/` ne sont jamais copiés |
| **Image livrée** | étape finale des Dockerfile | aujourd'hui : tests, PDF officiels, `build/` y sont encore (§ 4) |
| **Exécution** | configuration (`PKP_*`), domaines actifs, routes, données | Français : code présent, domaines inactifs, aucun import |

Rien n'est supprimé de `main` par son seul nom : les exclusions se font aux niveaux 2 à 4 (#116, § 2).

## 1. Le commit propre à `main` : `.github/dependabot.yml` — **à préserver**

- `9090164` crée `.github/dependabot.yml` sur `main` seulement ; `develop` ne l'a jamais eu.
- Un `git diff main develop` le montre **supprimé** (`D`) : c'est un artefact de comparaison à deux points.
  Une **fusion** de `develop` (ou d'une `release/*`) dans `main` le conserve, car `develop` ne le modifie pas.
  En revanche, une recopie de l'arbre de `develop`, un `reset` ou un `checkout develop -- .` le supprimeraient :
  **ces méthodes sont exclues**.
- Contrôle à ajouter dans la PR de livraison : `git ls-tree <candidat> .github/dependabot.yml` non vide.
- Contenu actuel : le modèle de GitHub, avec `package-ecosystem: ""` ; Dependabot le signale comme
  invalide et ne propose aucune mise à jour. Le compléter (pip `api/` et `engine/`, npm `web/`,
  `github-actions`, `docker` `deploy/`) relève de **#78** ; à faire par PR vers `develop` puis livraison,
  pas par modification directe de `main`.

## 2. Matrice par lot (PR fusionnées dans `develop`)

Légende : **Inclure** = dans `main` et actif ; **Inclure (inactif)** = code et schéma livrés, fonction fermée
à l'exécution ; **Git seulement** = dans `main`, jamais dans une image ni exécuté en production ;
**Différer** = fonction non ouverte tant que la condition n'est pas remplie.

### 2.1 Applicatif et sécurité

| Lot | Contenu | Décision | Justification / dépendances | Migration | Tests | Risque |
|---|---|---|---|---|---|---|
| #105 (#17) | corrigé PKP Math visible après réponse ; matrice des droits | **Inclure** | ARCH-4 ; prérequis de l'ouverture | — | `test_isolement_acces.py`, `test_pkp_math.py` | faible |
| #109 (#107) | corrigé du quiz anglais seulement après une réponse à chaque question | **Inclure** | ARCH-4 ; bloquant sécurité | — | `test_anglais_validation.py` | faible |
| #112 (#110) | mode de correction des quiz par groupe et par séance | **Inclure** | dépend de 0032 par la chaîne Alembic (§ 3) | **0033** | `test_mode_correction.py`, `anglais.test.jsx` | moyen : ajoute des colonnes NOT NULL avec valeur par défaut |
| #106 (#16) | scénarios des tableaux de bord | **Inclure** | tests seulement | — | `test_tableaux_de_bord.py` | nul |
| #114 (branche) | réinitialisation d'un parent réservée au professeur de tous ses enfants | **Inclure** (bloquant) | audit C-1 | — | `test_securite_comptes_tiers.py` | faible |
| #115 (branche) | carte d'un enfant de famille jamais régénérée par un professeur ; `relier` refusé | **Inclure** (bloquant) | audit C-2 | — | `test_securite_comptes_tiers.py` | faible |

### 2.2 Français (#98, #99, #100, #102, #103, #111, #113)

| Lot | Contenu | Décision | Justification / dépendances | Migration | Tests | Risque |
|---|---|---|---|---|---|---|
| #99 (#98) | `app/francais.py`, `routes/francais.py`, modèles `DossierFrancais*`, `contenu/francais/` | **Inclure (inactif)** | 0032 est l'ancêtre obligatoire de 0033 ; modèles requis par `test_migrations_a_jour_avec_les_modeles` | **0032** | `test_francais.py` | moyen si un domaine Français est activé par erreur |
| #103 (#102) | lien « Français (préparation) » sur l'accueil public, la connexion et l'espace professeur | **Inclure, navigation à conditionner** | le lien est affiché **sans condition** (`Accueil.jsx`, `EspaceEnseignant.jsx`) : il annonce une fonction différée ; le serveur refuse l'accès, mais l'affichage contredit « préparer la vente sans l'annoncer » | — | `navigation-francais.test.jsx`, `francais.test.jsx` | faible (sécurité), moyen (image publique) |
| #94, #100, #111, #113 | dossiers et cadrage dans `docs/francais/` | **Git seulement** | documentation ; non copiée dans les images | — | — | nul |

Verrous **côté serveur** constatés (pas seulement la navigation) :
- les domaines `francais-college` et `francais-lycee` sont créés **inactifs** (migration 0023, `permissions.DOMAINES`) ;
- `routes/francais.py` refuse tout dossier d'un domaine inactif ou hors habilitation (même réponse 404) ;
- **aucune route élève** n'existe pour le Français ;
- l'import des dossiers n'est **pas** lancé au démarrage (`python -m app.francais` manuel ; le `CMD` actuel
  n'importe que `app.contenu`).

Écart à corriger avant livraison : n'afficher la navigation Français que si un domaine Français est actif
(information déjà calculée côté serveur), ou décision explicite du **Propriétaire** de garder l'annonce.

Condition d'ouverture (**Propriétaire**) : validation pédagogique (#55, #29), décision d'activation d'un domaine
par l'administrateur, journalisée. Recette à prévoir : en configuration production, `GET /francais/dossiers` → 403
pour un professeur non habilité, 404 pour un dossier de domaine inactif.

### 2.3 Contenus pédagogiques mathématiques (#35 : #92, #95, #101, #104, #108)

| Lot | Contenu | Décision | Condition |
|---|---|---|---|
| corrigés détaillés 1re, 2nde, Tle spé, collège | 76 fichiers `contenu/**/*.yaml` modifiés, 1 ajouté | **Inclure** les fichiers ; **Différer** la diffusion des questions non relues | `PKP_SERVIR_QUESTIONS_NON_VALIDEES` est un choix **explicite** en production (refus de démarrer sinon) ; valeur à décider par le **Propriétaire** selon #14 et #29 |

`python -m app.contenu verifier` : 154 chapitres, 1 776 questions, valide sur `805e3af`. L'import est idempotent
et ne supprime jamais une question (ARCH-3).

### 2.4 Pipeline et exploitation DEV (#59, #64, #65, #66, #67, #69, #70, #71, #72, #74, #93, #96)

| Élément | Décision | Pourquoi c'est sans effet en production |
|---|---|---|
| `.github/workflows/dev-deploy.yml` | **Git seulement** | déclenché sur `push` de `develop` uniquement, et chaque job exige `github.ref == 'refs/heads/develop'` ; environnement GitHub `development` |
| `.github/workflows/gcp-dev-terraform.yml` (modifié : entrées `apply` retirées) | **Inclure** la modification | `workflow_dispatch`, job conditionné à `refs/heads/develop` ; la version de `main` garde des entrées `action`/`confirm_project` (plan seulement) que la livraison retire |
| `infrastructure/terraform/dev/` (`pipeline.tf`, `main.tf`) | **Git seulement** | projet `mer-boussole-dev` ; jamais copié dans une image |
| `deploy/docker-compose.dev.yml`, `deploy/vm/**` | **Git seulement** | utilisés par `boussole-dev-sync` sur la VM DEV ; non copiés dans les images |
| `scripts/*` DEV (14 fichiers ajoutés, liste interdite d'AGENTS.md § 1) | **Git seulement** | non copiés dans les images ; aucun ne s'exécute au démarrage |
| `scripts/tests/**`, `deploy/vm/tests/**` | **Git seulement** | bancs simulés exécutés par la CI |

### 2.5 Gouvernance, outillage et documentation (#75, #82, #83, #84, #86, #88, #89, #91, #97)

| Élément | Décision | Remarque |
|---|---|---|
| `AGENTS.md`, `docs/CONSIGNES-DEVELOPPEUR.md`, `docs/DECISIONS.md`, `.github/pull_request_template.md` | **Git seulement** | nécessaires à la maintenance |
| `.claude/settings.json` | **Git seulement** | permissions d'agent, **sans secret** (vérifié) ; exclu des images par construction |
| `.nvmrc`, `.python-version` | **Git seulement** | versions d'outils |
| `.github/workflows/ci.yml` (job Terraform/bancs ajouté) | **Inclure** | contrôle qualité ; aucune permission d'écriture |
| `.github/workflows/pkp-anglais-beta.yml` (#62 : permissions en lecture) | **Inclure** | corrige un défaut de `main` ; workflow obsolète à retirer plus tard par issue dédiée |
| `docs/analyses/`, `docs/audits/`, `docs/exploitation/`, `docs/PROTOCOLE-RELECTURE-PEDAGOGIQUE.md` | **Git seulement** | — |

## 3. Migrations 0032 et 0033

| | 0032 `dossiers_de_francais` | 0033 `mode_de_correction_des_quiz` |
|---|---|---|
| `down_revision` | `0031` | **`0032`** |
| Fonction liée | Français (différé) | Anglais, mode de correction (inclus) |
| Effet | 2 tables nouvelles ; aucune donnée existante modifiée | 2 tables nouvelles ; `groupe_anglais.mode_correction` NOT NULL avec défaut `apres_chaque_question` ; `progression_anglais.premier_score` NULL |
| Dépendances de schéma | clés étrangères vers `domaine_pedagogique` (0023) et `enseignant` | vers `groupe_anglais`, `eleve_anglais` (0019) |
| Retour arrière | `downgrade` supprime les deux tables (contenu Français importé perdu) | `downgrade` supprime tables et colonnes : **réponses par question et premiers scores perdus** |

Conclusions :
1. **0032 est obligatoire** dès que 0033 l'est : la chaîne est linéaire. Différer le Français ne permet pas de
   retirer 0032 (#116, § 4). Réécrire la chaîne (0033 sur 0031) est **écarté** : la base DEV est déjà en 0033 et
   `boussole-dev-sync` compare les révisions.
2. 0032 est sans risque pour les données existantes : uniquement des créations de tables.
3. 0033 est compatible avec un **ancien code** (colonnes avec défaut ou NULL) : un retour aux images précédentes
   reste possible sans `downgrade`. En revanche, un `downgrade` après usage détruit des réponses d'élèves :
   **interdit sans sauvegarde et décision explicite** (#8).
4. À tester sur PostgreSQL 16 isolé (#116, § 4) : `upgrade` 0031→0033 sur données synthétiques avec groupes
   et progressions anglais, puis lancement de l'ancien code sur le schéma 0033 (compatibilité de retour arrière).
   Non exécuté dans cette PR.

## 4. Image API actuelle (mesure locale, `805e3af`)

Construite localement (Docker 29, sans publication) : **375 Mo**, utilisateur `pkp` (uid 10001), aucun port publié
par Compose. Contenu inutile à l'exécution :

| Chemin dans l'image | Taille | Utilité en production |
|---|---|---|
| `/app/referentiels/sources/*.pdf` | 11 Mo | aucune : l'API lit les YAML sans vérifier les empreintes ; les PDF ne servent qu'aux commandes de matrice |
| `/app/api/tests`, `/app/engine/tests` | 460 Ko | aucune |
| `/app/api/build`, `*.egg-info` | 700 Ko | résidus de `pip install` |
| `watchfiles` (via `uvicorn[standard]`) | — | rechargement à chaud : outil DEV |
| `contenu/francais/` | 32 Ko | inerte tant que l'import manuel n'est pas lancé (§ 2.2) |

Le `CMD` enchaîne `alembic upgrade head`, `python -m app.contenu importer` puis Uvicorn : chaque redémarrage
de l'API migre la base, et plusieurs répliques migreraient en concurrence. Le Compose DEV contourne déjà ce
point (commande Uvicorn seule, étapes pilotées par `boussole-dev-sync`).

## 5. Priorités traitées sur cette branche (ordre demandé par le propriétaire)

| # | Étape | Commit | Preuve |
|---|---|---|---|
| 1 | **Verrouillage du mode production** : `app.db.seed` refusé en production ; `python -m app.production verifier` (code 1 si un compte de démonstration est présent) ; origines CORS `https://` seulement | `security(production)` | `test_verrouillage_production.py` (dont `/docs`, `/redoc`, `/openapi.json` en 404 en production) |
| 2 | **Réduction de l'image API** : deux étapes ; retirés tests, PDF officiels, `build/`, `egg-info`, copie installée de `pkp-api`, `watchfiles`, `websockets` ; `.dockerignore` élargi | `infra(images)` | mesure locale 375 → 362 Mo ; inventaire de l'image ; démarrage vérifié |
| 3 | **Migrations et imports hors du démarrage** : `CMD` = Uvicorn seul ; service ponctuel `preparation` (migrations, import, contrôle de la base) dont l'API attend la réussite | `infra(deploy)` | essai Compose isolé sur PostgreSQL 16 : succès, redémarrage sans migration, refus sur compte de démonstration |

Limites : la base d'essai était vierge (aucune donnée 0031 réelle ni synthétique migrée) ; aucune image publiée ni
signée ; DEV non modifié (`boussole-dev-sync` pilote déjà migration et import, sans le contrôle de démonstration).

## 6. Découpage proposé des travaux restants (tickets existants d'abord)

Aucun ticket n'est créé par cette PR : chaque ligne indique le ticket existant qui porte le travail, ou un
**sous-ticket de #116** à créer après accord (#116 reste le ticket principal).

### 6.1 Bloquants avant la PR de livraison vers `main`

| Ordre | Travail | Porteur | Remarque |
|---|---|---|---|
| 1 | Revue et fusion dans `develop` de cette PR (C-1, C-2, verrouillage, images, préparation) | #114, #115, #116 | une personne relit et fusionne |
| 2 | SSRF de la vérification des liens (redirections, adresses internes) | **#3** | audit M-1 |
| 3 | Contrôle structurel des PDF téléversés | **#4** | audit M-2 |
| 4 | Navigation Français affichée seulement si un domaine Français est actif | **#102** (complément) | § 2.2 ; ou décision du propriétaire de garder l'annonce |
| 5 | Migrations 0031 → 0033 sur PostgreSQL 16 avec données synthétiques ; ancien code sur schéma 0033 ; sauvegarde et restauration testées | **#8** + sous-ticket #116 « recette migrations » | § 3 point 4 |
| 6 | Choix de `PKP_SERVIR_QUESTIONS_NON_VALIDEES` et liste des contenus commercialisés | **#14**, **#29** | décision du propriétaire |
| 7 | Dépendances Python verrouillées (fichier de contraintes utilisé par l'image et la CI) ; images de base épinglées par empreinte | sous-ticket #116 « construction reproductible » | prérequis des digests du § 6 de #116 |
| 8 | Scans : secrets, dépendances Python/npm, images | **#78** (outillage) + sous-ticket #116 « scans du candidat » | npm : vitest 2 / vite 5 vulnérables (outillage DEV, hors bundle) |

### 6.2 Durcissement à planifier (non bloquant pour une recette, à trancher pour l'ouverture)

| Travail | Porteur |
|---|---|
| Révocation des sessions côté serveur ; jetons hors de portée de JavaScript | **#5**, **#6** |
| Limitation des tentatives : une clé de compte commune aux trois routes de connexion élève ; rejeu TOTP | **#7** |
| Rattachement d'un compte parent existant par un professeur (révèle le compte, lui montre l'élève) | **#114** (décision du propriétaire) |
| Recherche d'enfants : nom et identifiant visibles de tout professeur du niveau | **#87** (RGPD-1) |
| Limite de taille des requêtes dans Caddy ; Caddy 2.8 à mettre à jour | sous-ticket #116 « déploiement » |
| `dependabot.yml` à compléter (pip, npm, actions, docker) | **#78** |
| Workflows obsolètes `import-pkp-main.yml`, `pkp-anglais-beta.yml` ; actions épinglées par SHA partout | issue dédiée (AGENTS.md § 1 : workflows) ; **#62** |

### 6.3 Circuit de livraison (#116 § 6)

| Travail | Porteur |
|---|---|
| Protections de `main` selon l'offre GitHub réelle ; environnement `production` protégé ou alternative documentée | **#83** + sous-ticket #116 « protections et approbation » |
| Workflow manuel `release/*` → PR brouillon vers `main`, contrôle final obligatoire, manifeste et digests | sous-ticket #116 « pipeline de livraison » (s'appuie sur #65) |
| Projet, identités WIF et secrets PROD distincts de `mer-boussole-dev` | sous-ticket #116 ; **#61**, **#60**, **#74** pour le DEV |
| Supervision et alertes | **#20** |

### 6.4 DEV, à coordonner sans bloquer la livraison

- **#93** (traité sur cette branche, décision du propriétaire du 15/11/2026 : conserver des comptes de test en DEV
  sans affaiblir l'authentification) : nouvel environnement `integration` pour la VM DEV, mêmes contrôles que la
  production ; comptes de test reconnus à leur domaine réservé (`.test`…), autorisés en intégration, refusés en
  production (création, connexion, contrôle de préparation). **Aucune dispense de TOTP** : la variante
  `PKP_ADMINS_SANS_TOTP` du ticket et le script de bascule ne sont plus nécessaires. Activation sur la VM : réinstallation
  du Compose DEV par le propriétaire (`deployer-dev-iap.sh`), non faite ici.
- **#79** (découpage d'`admin.py` et des gros composants) : après la livraison, pour éviter les conflits.

---
<sub>🤖 Rédigé par **Claude** (Claude Code) pour l'issue #116, 14/11/2026.</sub>
