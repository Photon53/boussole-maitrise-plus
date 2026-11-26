# Module Français — préparation avant le GO de développement (#175)

Issue #175 — Claude — 26/11/2026. Base examinée : `develop` `88e6ea6`.

**Statut : GO PRÉPARATION — NO GO DÉVELOPPEMENT.** Ce document rassemble les livrables demandés par le
propriétaire le 26/11/2026 avant tout développement fonctionnel. Il ne prouve aucune implémentation, aucune
recette ni aucune validation pédagogique. Les décisions citées sont consignées dans
[`../DECISIONS.md`](../DECISIONS.md), section « Module Français — arbitrages du 26/11/2026 ».

## Légende des niveaux de preuve

Chaque constat porte le niveau le plus élevé réellement atteint :

| Code | Signification |
|---|---|
| **C** | Constaté dans le code de `develop` (lecture) |
| **T** | Testé automatiquement : tests présents et CI verte sur le SHA cité |
| **N** | Vérifié dans un navigateur (recette Playwright ou capture), en précisant l'environnement |
| **D** | Validé sur GCP DEV par le propriétaire (SHA relevé, rapport joint) |

Au 26/11/2026, **aucun constat n'atteint D**. Le niveau N n'a été atteint qu'en local, le 23/11, sur `4db0787`
(recette 16/16 de #222, antérieure à #226).

## 0. Tableau consolidé (mis à jour le 26/11/2026, deuxième revue)

### Décisions

| Validées par le propriétaire (26/11) | En attente | Qui décide |
|---|---|---|
| A1 formats ; A2 liste **à soumettre** ; A4 calendrier ; A5 PDF fermés ; A6 rédaction fermée ; A7 recette DEV par le propriétaire ; #223 principe (navigateur réel, déclenchements ciblés) ; #231 cinq PR fonctionnelles | EX.4 (§ 3) | Propriétaire |
| | Participation des parents au pilote (priorité de la PR 1) | Propriétaire |
| | Liste des 8 cours et 4 sujets | Professeur |
| | Maquettes (§ 8) | Propriétaire |
| | Configuration et coûts de #223 (§ 7) | Propriétaire |
| | Contribution des quiz de dossier à la maîtrise (§ 10) | Professeur (pertinence), propriétaire (évolution) |
| | Alignement documentaire de la version de Node (§ 11) | Propriétaire |

### Fonctionnalités

Le détail par fonction est au § 2. Synthèse :

| Niveau de preuve | Fonctions concernées |
|---|---|
| **Présentes dans le code (C)** | Classes pilotes, validation V2-D15, dossiers (import, versions, ouverture), quiz, « Je sais », suivi des classes, modification d'un dossier, PDF élève et professeur, rubriques, « Mon cours » (liens), rédaction en ligne (fermée), simulation, suivi parental partiel |
| **Testées automatiquement (T)** | Toutes les précédentes, sauf l'écran parent du Français ; CI verte sur `88e6ea6` |
| **Vérifiées dans un navigateur (N)** | En local seulement, le 23/11 sur `4db0787` : classes pilotes, validation, dossiers, PDF du dossier, simulation, non-régression maths et anglais ; **quiz et suivi (#226) non vérifiés dans un navigateur** |
| **Validées sur DEV (D)** | **Aucune** |
| **Absentes** | Présentations de #111, accueil de la matière, écran parent du Français, 7 cours sur 8 |

## 1. Décisions et tickets

| Sujet | Décision | Ticket |
|---|---|---|
| A1 — Formats | Chapitres YAML (conjugaison, grammaire, orthographe sous grammaire, rédaction avec #187) ; dossiers (compréhension, brevet) ; interface unifiée | #175, #177 |
| A2 — Huit cours | Liste à soumettre au professeur : [`PROPOSITION-8-COURS.md`](PROPOSITION-8-COURS.md) | #177, #55 |
| A3 — Suivi parental | Nécessaire ; priorité selon la participation des parents au pilote ; conception au § 5 | #231 |
| A4 — Présentations | Guidé P1 décembre 2026 ; Objectif brevet P1 au plus tard le 1er mars 2027 ; Bibliothèque P2 février 2027 ; EX.4 au § 3 | #111 |
| A5 — PDF de « Mon cours » | `PKP_PDF_FRANCAIS_OUVERT=false` maintenu | #4, #180 |
| A6 — Rédaction | `PKP_REDACTION_ACTIVE=false` maintenu | #179, #183 |
| A7 — Recette DEV | Par le propriétaire : [`RECETTE-DEV.md`](RECETTE-DEV.md) | #217 |
| #223 | Recette navigateur réelle, déclenchements ciblés ; configuration au § 7 | #223 |
| #231 | Cinq PR fonctionnelles ; conception au § 4 | #231 |

## 2. État des fonctions par niveau de preuve

| Fonction | C | T | N | D | Remarque |
|---|---|---|---|---|---|
| Accès réservé aux classes pilotes (SEC-D6) | ✅ | ✅ | ✅ local (23/11) | — | |
| Validation par validateur ou administrateur, jamais l'auteur (V2-D15) | ✅ | ✅ | ✅ local (23/11) | — | |
| Dossiers : import au déploiement, versions, ouverture à la classe | ✅ | ✅ | ✅ local (23/11) | — | |
| Quiz, « Je sais », suivi des classes, modification d'un dossier (#226) | ✅ | ✅ | ⚠️ étapes ajoutées à la recette, exécution non jointe | — | |
| PDF élève / professeur d'un chapitre et d'un dossier | ✅ | ✅ | ✅ local pour le dossier | — | Non-divulgation testée côté API |
| Rubriques des chapitres | ✅ | ✅ | — | — | Aucun chapitre de français : rien à afficher |
| « Mon cours » (liens) | ✅ | ✅ | — | — | PDF fermés (A5) |
| Rédaction en ligne (#187, #226) | ✅ | ✅ | — | — | Fermée (A6) |
| Présentations de #111 | ❌ | — | — | — | Cadrage seulement |
| Suivi parental du Français | ⚠️ API partielle, écran provisoire | — | — | — | § 5 |
| Contenus pédagogiques | 1 dossier sur 8 cours | — | — | — | Chemin critique (#177) |

## 3. EX.4 — persistance des présentations (décision en attente)

### 3.1 Ce qui est déjà décidé et ce qu'il faut préciser

- **V2-D12 — présentation (14/11)** : le professeur choisit la présentation « pour un groupe ou une séance » ;
  priorité **séance explicite → groupe → parcours guidé** ; option « Hériter du groupe » ; pas de réglage par
  élève ; l'élève ne choisit pas.
- **EX.4** refuse toute nouvelle classe ou tout nouveau groupe dans un domaine non public. **SEC-D6** autorise, par
  exception, les **classes pilotes** désignées par un administrateur.
- **#110 (ARCH-4)** a déjà tranché un problème identique pour le mode de correction : réglage de la **classe**
  (`classe.mode_correction`), surchargé pour un **contenu** (`mode_correction_dossier_francais`, migration `0049`).

**Trois mots à ne pas confondre** :

| Terme | Ce que c'est dans le code | Conséquence |
|---|---|---|
| Objet technique `Seance` | `models.Seance` : passage d'exercices d'**un** élève, avec **une seule question en cours** (`question_courante_id`) | **Ne porte jamais** la présentation : il n'existe que pendant que l'élève répond |
| `SeanceAnglais` | Un **contenu** d'anglais versionné et validé | En anglais, la « séance » de #110 est un contenu ; le réglage « par séance » y est donc un réglage **par contenu** |
| **Séance pédagogique** | Le cours que le professeur fait à une date donnée avec une classe | **N'existe pas** dans le code ; à créer si on veut un réglage daté |
| Groupe | En français, aucun objet distinct : le « groupe » du cadrage de #111 correspond à la **classe** (les élèves de français sont les `Eleve` des classes, D6 du 19/11) | Sous-groupes d'une classe : à créer si besoin |

### 3.2 Comparatif des quatre niveaux de réglage

| Niveau | Réalisation proposée | EX.4 | Migration | Compatible avec V2-D12 | Pour janvier |
|---|---|---|---|---|---|
| **Classe** (défaut) | Colonne `presentation` sur `classe`, comme `mode_correction` | Aucun impact : la classe pilote existe déjà | 1 colonne | Oui : « groupe » = classe | **Oui** |
| **Contenu ouvert** | Surcharge par chapitre ou dossier **ouvert à la classe**, comme `mode_correction_dossier_francais` | Aucun impact | 1 table | Oui : c'est la « séance » au sens de #110 | **Oui** |
| **Groupe** (futur) | Sous-groupe de besoin à l'intérieur d'une classe pilote, avec sa présentation | Création de groupes dans un domaine fermé : **exception à EX.4 à décider**, ou attendre l'ouverture publique | Nouvelle entité, affectation des élèves | Oui | Non |
| **Séance pédagogique** (futur) | Réglage daté (classe ou sous-groupe, plage horaire, présentation), qui l'emporte pendant sa durée | Aucun impact si rattaché à une classe pilote | 1 table | Oui : « séance explicite » | Non (Objectif brevet en mars) |

### 3.3 Architecture proposée

Une seule fonction côté serveur calcule la **présentation effective** pour un élève et un contenu, en parcourant les
niveaux du plus précis au plus général et en s'arrêtant au premier réglage trouvé :

```
séance pédagogique active  →  sous-groupe  →  contenu ouvert  →  classe  →  parcours guidé
         (futur)                 (futur)        (janvier)        (janvier)     (défaut)
```

- Pour janvier, seuls les niveaux « contenu ouvert » et « classe » existent ; les deux autres s'ajoutent sans
  modifier les précédents.
- Aucun contenu n'est dupliqué : la présentation change l'ordre et le regroupement, jamais les questions.
- Tests : la règle de priorité, « Hériter » à chaque niveau, et l'absence de sélecteur côté élève.

**Recommandation** : décider maintenant les niveaux **classe** et **contenu ouvert** (aucune exception à EX.4),
et noter les niveaux **groupe** et **séance pédagogique** comme évolutions prévues dans l'architecture.
La décision sur les sous-groupes (et donc sur EX.4) peut attendre l'après-pilote. **EX.4 reste en attente de
validation.** Sans décision, la PR 3 livre le parcours guidé sans réglage enregistré.

## 4. Conception des cinq PR de #231

Règles communes : branche issue de `develop`, PR en brouillon, une PR = un ensemble fonctionnel, `Refs #231` et
`Refs #175`. Responsive (ordinateur, tablette, mobile) et accessibilité clavier **dès la première PR**.
Composants communs aux trois matières dès que possible. Aucune modification des règles de sécurité, de maîtrise
(ARCH-5) ou de validation (V2-D15). Drapeaux A5 et A6 inchangés.

| PR | Objet | Périmètre probable | Dépend de | Risques | Critères d'acceptation |
|---|---|---|---|---|---|
| **1. Suivi parental** | Le parent voit l'activité de Français de son enfant (§ 5) | `api/app/parents.py`, `api/app/routes/familles.py`, `api/app/schemas.py`, `web/src/parent/EspaceParent.jsx` | Décision de priorité (A3) ; maquette | Fuite de contenu pilote ou de texte rédigé ; requêtes N+1 | Aucun texte rédigé ni énoncé de contenu pilote dans la réponse (test) ; isolement entre familles et classes (test) ; maths et anglais inchangés |
| **2. Accueil et navigation élève** | « Mon espace Français » : reprise, quatre rubriques, compréhension et brevet, progression ; chapitres et dossiers présentés ensemble | `web/src/eleve/EspaceEleve.jsx`, nouvel accueil de matière, `Cours.jsx`, `DossiersFrancais.jsx` ; éventuellement une route API de synthèse « où reprendre » | Maquette ; peu de contenu tant que #177 n'avance pas (données de démonstration) | Casser la navigation maths ; doubler un écran existant | Parcours « accueil → rubrique → leçon → entraînement → correction → progression » au clavier ; onglets maths inchangés (test) ; recette navigateur étendue |
| **3. Parcours guidé** | Architecture des trois présentations, guidé seul activé | Calcul de la présentation effective côté serveur (classe, puis contenu) si EX.4 option 1 ; composant d'ordonnancement des contenus | Arbitrage EX.4 (§ 3) ; PR 2 | Créer un réglage persistant sans décision | Guidé par défaut ; aucune duplication de contenu ; élève sans sélecteur ; tests de la règle « contenu → classe → guidé » |
| **4. Espaces adultes** | Professeur, validateur, administrateur : préparation, ressources, validation, simulation, ouverture, suivi, depuis les espaces habituels | `web/src/enseignant/`, `web/src/admin/`, `web/src/francais/` | Captures ; PR 2 pour la cohérence | Régression des files de validation maths et anglais | Chaque action accessible en deux clics depuis l'espace habituel ; recette des rôles verte ; non-régression validation maths et anglais |
| **5. Vérification finale** | Passe responsive, clavier, contrastes, zoom, cohérence graphique | `web/src/styles.css`, `web/src/theme.css`, composants touchés | PR 1 à 4 ; contrôles de #154 | Régressions visuelles hors Français | Captures avant / après aux trois tailles ; obstacles relevés traités ou documentés |

## 5. Conception du suivi parental (PR 1)

**Constat (C).** `GET /parents/famille` renvoie `francais: list[EnfantResume]`, construit par `parents.resume`, qui
ne compte que les **réponses aux chapitres** (`historique_eleve`). L'activité des dossiers (`progression_francais`,
`reponse_quiz_francais`, `reponse_redigee_francais`) et les rédactions (`redaction`) n'y figurent pas. L'écran
affiche « Le français arrive bientôt ». L'espace parent ne voit que les **enfants de famille** inscrits à une
classe : un élève de classe pilote créé par le professeur n'a pas forcément de parent rattaché.

**Proposition.**

| Élément | Source | Exposé au parent | Jamais exposé |
|---|---|---|---|
| Chapitres (exercices autocorrigés) | `parents.resume` existant | Réponses, taux de réussite, compétences maîtrisées (moteur ARCH-5) | Énoncés et corrigés si l'accès de la classe est refusé (SEC-D6) |
| Quiz des dossiers | `progression_francais` | Libellé du dossier, meilleur score, premier essai, nombre d'essais | Questions et choix |
| « Je sais » | `progression_francais.auto_evaluation` | Nombre de phrases par niveau (non observé, avec aide, en cours, autonome) | — |
| Réponses rédigées et rédactions | `reponse_redigee_francais`, `redaction` | **Nombre** remises et corrigées, date du dernier retour | **Texte de l'élève et commentaire du professeur** (RGPD-2) |
| Progression | `progression_eleve` | Compétences travaillées, limitées selon SEC-D6 | — |

- Schéma : un modèle commun « progression par dossier » pour l'anglais et le français, sur le modèle de
  `ProgressionAnglaisEnfant`, plutôt qu'un schéma propre au Français.
- Contrôles : le parent ne voit que ses enfants (contrôle existant de `familles.py`) ; masquage de SEC-D6 réutilisé ;
  aucune nouvelle donnée personnelle ; requêtes en nombre fixe (test).
- Tests : un parent n'obtient jamais un texte rédigé ; un autre parent reçoit 404 ; classe retirée du pilote :
  libellés et résultats seulement ; maths et anglais inchangés.

## 6. Stratégie de tests et de non-régression

| Niveau | Outil | Quand | Couverture |
|---|---|---|---|
| Moteur, API, contenu | `ci.yml` (pytest, `app.contenu verifier`) | Chaque PR | Règles, droits, non-divulgation, migrations |
| Front | `ci.yml` (Vitest, build, `npm audit`) | Chaque PR | Composants, navigation, onglets par matière |
| Navigateur, pile jetable | `scripts/recette/pile-locale.sh` + `recette-francais.mjs` | Chaque PR qui touche le Français ; en CI selon le § 7 | Cinq rôles, aucun corrigé côté élève, simulation, non-régression maths et anglais |
| Contenu | `app.contenu verifier`, inventaire, test de non-divulgation du PDF élève | Chaque PR de contenu | 9 questions par cours, registre des sources |
| DEV | `RECETTE-DEV.md` | Après chaque déploiement d'un lot | Preuve D, par le propriétaire |

Chaque PR ajoute les étapes de recette navigateur de son écran. Une PR n'est demandée en relecture qu'avec la CI
verte (AGENTS.md § 3.5).

## 7. Recette navigateur en CI (#223) — configuration proposée et coûts

### 7.1 Constat sur `develop` `88e6ea6`

- `recette-francais.yml` (#219) relance `tests/test_francais.py` et les tests front, déjà exécutés par `ci.yml`,
  **sans navigateur**. Il utilise Node `^24.15.0`, comme `ci.yml` (voir § 11).
- Aucun workflow ne déclare `concurrency` : une poussée qui suit une autre ne l'annule pas.

### 7.2 Configuration proposée (à valider avant implémentation sous #223)

- **Un job unique** « Recette navigateur Français » remplace les deux jobs actuels de `recette-francais.yml`.
  - Python 3.12 et **Node 24.15** (version de référence de la CI, § 11), avec cache pip et npm.
  - Chromium en cache (`~/.cache/ms-playwright`, clé = version de Playwright).
  - `bash scripts/recette/pile-locale.sh rapports/`.
  - Rapport et captures en artefact, conservés 14 jours.
- **`concurrency`** avec `group: recette-francais-${{ github.ref }}` et `cancel-in-progress: true`.
- **Déclenchement `pull_request` vers `develop` et `main`** sur ces chemins :
  - `api/app/**`, `api/migrations/**`, `engine/**` ;
  - `web/src/**`, `web/package*.json`, `web/vite.config.*` ;
  - `contenu/francais/**`, `scripts/recette/**` ;
  - `api/pyproject.toml`, `engine/pyproject.toml`, `.github/workflows/recette-francais.yml`.

  Sont exclus : `docs/**`, `*.md`, les contenus de maths et d'anglais, `infrastructure/**`.
- **Levier optionnel**, à choisir par le propriétaire : ne pas lancer la recette sur une PR **en brouillon**
  (`if: github.event.pull_request.draft == false`, types `ready_for_review` et `synchronize`). La recette tourne
  alors seulement quand la PR est proposée à la relecture. Ce levier réduit fortement la fréquence, car les PR des
  agents reçoivent souvent plusieurs poussées en brouillon.
- **`workflow_dispatch`** (lancement manuel) et exécution avant chaque fusion vers `main`.
- Pas de matrice de navigateurs. Ni VM, ni exécuteur auto-hébergé.

### 7.3 Données mesurées (API GitHub, 1er au 26/11/2026)

| Élément | Valeur | Source |
|---|---|---|
| Visibilité du dépôt | **Public** (`"visibility": "public"`) ; l'API répond aussi **sans authentification** (HTTP 200) | `GET /repos/Photon53/boussole-maitrise-plus`, vérifié le 26/11 à 22 h 55 |
| Exécutions de workflows | 346 exécutions, 786 jobs | `GET /actions/runs`, puis les jobs de chaque exécution |
| Durée réelle cumulée | 3 917 min | Somme de `completed_at − started_at` |
| Minutes arrondies à la minute par job (règle de facturation) | **4 292 min** | Idem, arrondi supérieur par job |
| dont prébuilds Codespaces (exécutions « [develop]: Merge pull request… ») | **1 804 min** | Étiquette `codespaces-prebuild` |
| dont `CI` | 1 745 min (156 exécutions, dont 141 sur PR) | |
| dont « DEV - publication des versions » | 695 min (75 exécutions) | |
| dont `recette-francais.yml` actuel | 8 min (4 exécutions de 2 jobs) | |
| Quota et facturation du compte | **Non lisibles depuis la session de l'agent** (accès limité au dépôt) | À relever par le propriétaire : *Settings → Billing and licensing* du compte Photon53 |

### 7.4 Estimation du coût de #223

**Hypothèses** :
- **Durée** : 6 à 7 minutes par exécution. Elle se compose de l'installation en cache (environ 2 min), de Chromium
  en cache, de la pile locale et de la recette (2 à 3 min). La recette locale du 23/11 comptait 16 étapes.
  **À mesurer** sur la première exécution réelle.
- **Fréquence sans le levier « brouillon »** : de 115 à 165 exécutions par mois, soit 70 à 100 % des exécutions
  de `CI` sur PR (141 en 26 jours, environ 163 sur un mois).
- **Fréquence avec le levier « brouillon »** : environ 30 à 60 exécutions par mois (estimation).
- **Économie** : la suppression des deux jobs redondants de `recette-francais.yml` libère environ 2 minutes
  facturables par exécution.

| Scénario | Minutes ajoutées par mois | Coût si le dépôt est public | Coût marginal si le dépôt devenait privé (0,006 $ / min Linux 2 cœurs) |
|---|---|---|---|
| Sans levier « brouillon » | environ 460 à 825 (net) | **0 $** : exécuteurs standard gratuits pour un dépôt public | environ 2,80 à 5 $ |
| Avec levier « brouillon » | environ 120 à 300 (net) | **0 $** | environ 0,70 à 1,80 $ |

Point d'attention, indépendant de #223 : **si le dépôt devenait privé**, la consommation actuelle (environ
4 300 min par mois) **dépasserait déjà** l'allocation incluse des offres individuelles. Cette allocation, en
dollars, vaut environ 2 000 min Linux pour Free et 3 000 min pour Pro, selon la documentation GitHub en vigueur.
Les **prébuilds Codespaces** (1 804 min ce mois-ci, environ 42 % du total) en sont le premier poste. Leur
facturation (minutes et stockage) est à vérifier dans la page de facturation. Leur réduction relève de #142, pas
de #223.

Le barème et les allocations doivent être revérifiés dans la documentation GitHub au moment de la décision.

## 8. Captures et maquettes

### 8.1 État

- **Captures des interfaces actuelles** : **bloquées**. Chromium (Playwright) fonctionne dans l'environnement de
  l'agent, mais les installations Python et npm sont refusées par le proxy de la session (constaté le 26/11 à
  22 h 55 : `pypi.org`, `registry.npmjs.org` et `nodejs.org` refusés).
  - **Réglage indiqué par le proxy lui-même** : sur claude.ai, dans un navigateur, *Settings → Capabilities*
    (offre individuelle payante), ou *Organization settings → Capabilities* par l'administrateur (offres Team et
    Enterprise).
  - **Domaines strictement nécessaires** :
    - `pypi.org` et `files.pythonhosted.org` : dépendances Python ;
    - `registry.npmjs.org` : dépendances du front ;
    - `nodejs.org` : Node 24.15, version de la CI (l'environnement a Node 22).
  - Aucun domaine Playwright n'est nécessaire.
  - Les captures seront faites sur une installation locale jetable, avec des données fictives, pour les cinq rôles
    et trois tailles d'écran, puis jointes à #231.
- **Maquettes cibles** : [`maquettes/maquettes-francais.html`](maquettes/maquettes-francais.html) et ses images.
  Elles sont conceptuelles, avec des données fictives, reprennent les jetons de `web/src/theme.css` et restent
  soumises à la validation du propriétaire.

### 8.2 Changements proposés par rôle

La colonne « actuel » s'appuie sur la lecture du code (C). Elle sera remplacée par les captures (N) dès le déblocage.

| Rôle | Actuel (code) | Cible (maquette) | Justification |
|---|---|---|---|
| Élève | Jusqu'à 9 onglets ; « S'entraîner » vide en français ; dossiers dans « Cours », chapitres ailleurs (`EspaceEleve.jsx`) | Accueil « Mon espace Français » : reprise, **cinq entrées** (quatre rubriques et « Comprendre un texte »), progression et retours | A1 (interface unifiée) ; #175 § 5 (navigation niveau → cours → leçon → entraînement → correction → progression) |
| Parent | « Le français arrive bientôt » (`EspaceParent.jsx`) ; l'API ne compte que les chapitres | Onglet Français : compétences, temps, activités (exercices, quiz, « Je sais », rédactions **en nombre**) ; encadré « ce que vous ne voyez pas » | A3 ; SEC-D6 et RGPD-2 rendus explicites pour le parent |
| Professeur | Espace `/francais` atteint par un lien ; suivi dans un onglet séparé | Page de classe : à corriger, notions fragiles, exports, progression du cours avec ouverture et aperçu | #175 § 4 et § 5 (accès rapide aux corrections, exports, erreurs fréquentes) |
| Validateur | File du français distincte de celle des maths (#221) | File par matière, chapitres et dossiers ensemble, actions dans la ligne ; son propre contenu signalé | V2-D15 ; cohérence entre matières |
| Administrateur | Domaines, habilitations, classes pilotes et validation sur des écrans séparés | Page de la matière : accès, contenus (objectifs 8/72/4), fonctions sensibles **en lecture seule**, habilitations, simulation | #217 (pilotage par l'administrateur) ; A5 et A6 visibles sans être modifiables |

Points à arbitrer sur les maquettes :
- les cinq entrées de l'élève ;
- la séparation entre maîtrise et retours humains (R8) ;
- le réglage de présentation par classe, qui suppose les niveaux « classe » et « contenu ouvert » d'EX.4 (§ 3) ;
- les drapeaux visibles mais non modifiables dans l'écran de l'administrateur.

## 9. Risques, blocages et décisions encore nécessaires

| # | Point | Type | Décideur |
|---|---|---|---|
| R1 | Contenus : 1 cours sur 8, aucune question autocorrigée de chapitre ; validation par le professeur sur le chemin critique | **Risque principal** | Professeur |
| R2 | Pas de preuve sur DEV depuis #221 et #226 | Blocage du GO pilote | Propriétaire (A7) |
| R3 | Production associative (#228) : affichage incomplet signalé | Risque | Propriétaire |
| R4 | En français, les types d'exercices autocorrigés sont `qcm` et `texte` ; `choix_multiples` est réservé au diagnostic | Contrainte | Information |
| R5 | `docs/CONTENU.md` ne décrit pas le type `texte` dans son tableau des types | Écart documentaire | À corriger dans la PR de contenu |
| R6 | `reponse_quiz_francais` ne mémorise pas la **version** du dossier : une nouvelle version qui réordonne le quiz rend les anciennes réponses ambiguës (§ 10) | Risque de données | Information, à traiter avant toute évolution de la maîtrise |
| R7 | Version de Node incohérente dans le dépôt (§ 11) | Écart documentaire | Propriétaire |
| R8 | Prébuilds Codespaces : environ 42 % des minutes Actions du mois (§ 7.3) | Coût | Propriétaire (#142) |
| D1 | Arbitrage EX.4 (§ 3) | Décision | Propriétaire |
| D2 | Participation des parents au pilote (priorité de la PR 1) | Décision | Propriétaire |
| D3 | Validation de la liste des huit cours | Décision | Professeur |
| D4 | Validation des maquettes | Décision | Propriétaire |
| D5 | Configuration de #223, levier « brouillon » compris (§ 7) | Décision | Propriétaire |
| D6 | Contribution des quiz de dossier à la maîtrise (§ 10) | Décision | Professeur, puis propriétaire |

## 10. Quiz des dossiers et taux de maîtrise (analyse, sans modification)

**Aucune modification du moteur ni des règles de maîtrise.** Les auto-évaluations « Je sais » et les corrections
humaines n'alimentent jamais le taux de maîtrise.

### 10.1 Comportement actuel (C, T)

- **Moteur** (`engine/src/pkp_engine/maitrise.py`, ARCH-5) : fonction pure `calculer_maitrise(historique,
  competence_id)`. Elle utilise les 10 dernières réponses de la compétence, une pondération de 0,9 et un a priori
  de 1 ; le seuil de maîtrise est 0,8. L'historique est une liste de `pkp_engine.Reponse(question_id,
  competence_id, correcte, duree_s)`.
- **Chapitres** : `conversions.historique_eleve` construit cet historique à partir de `reponse` ⨝ `question`
  (`question.competence_id`) ⨝ `seance`. Seules les questions d'une table `question` rattachées à une `Competence`
  comptent.
- **Quiz des dossiers** : réponses dans `reponse_quiz_francais` (`code` du dossier, `essai`, **indice** de la
  question, `choix`, `juste`) et résumé dans `progression_francais` (meilleur score, premier essai figé, nombre
  d'essais). Les questions du quiz vivent en JSON dans `dossier_francais_version.quiz`. Elles n'ont **ni
  identifiant stable ni compétence**. Le dossier déclare seulement des **codes locaux** (`competences_locales`,
  par exemple `FR3-L01`), qui ne sont pas des lignes de la table `competence`.

### 10.2 Écarts avec les chapitres

| Point | Chapitre | Quiz de dossier |
|---|---|---|
| Identifiant de question | `question.id`, stable ; jamais supprimée (ARCH-3) | Indice dans une liste JSON propre à chaque version |
| Compétence | `question.competence_id` | Aucune |
| Version dans la réponse | La question est versionnée par sa ligne | **Absente** de `reponse_quiz_francais` (R6) |
| Essais | Une réponse par question servie | Plusieurs essais du même quiz (« Recommencer ») |
| Validation | Par question (`statut_validation`) | Par version de dossier |

### 10.3 Possibilités de réutiliser le moteur commun

| Option | Principe | Code | Données | Avis |
|---|---|---|---|---|
| **M0** | Statu quo : le quiz donne un score, pas de maîtrise | Aucun | Aucune | Valable pour les questions de compréhension **propres à un texte** |
| **M1** | Mettre les questions qui évaluent une **compétence transférable** (accords, par exemple) dans un **chapitre YAML** associé au dossier ; le quiz garde les questions propres au texte | Aucun | Nouveau contenu seulement | **Recommandé pour janvier** : moteur et règles inchangés, aucun doublon si chaque question n'existe qu'à un endroit |
| **M2** | Rattacher chaque question de quiz à une **compétence** du référentiel (extension compatible du contrat `boussole-francais-dossier/1`) ; à la lecture, convertir le **premier essai** de chaque question en `pkp_engine.Reponse` et l'ajouter à l'historique avant `calculer_maitrise` | Conversion dans `api/app/db/conversions.py` ; moteur **inchangé** | Version du dossier à ajouter dans `reponse_quiz_francais` (migration) ; compétences de français à créer dans le référentiel | Possible après le pilote, sur décision ; pas de second moteur, pas de table dérivée (ARCH-5) |
| M3 | Transformer les questions de quiz en lignes `question` | Lourd : deux chemins vers les mêmes questions | Migration de données | Déconseillé |

### 10.4 Impacts de l'option M2 sur les données et les tests

- **Données** :
  - ajouter une colonne de version à `reponse_quiz_francais` (migration relue à la main, ARCH-2) ;
  - ajouter un champ `competence` par question de quiz dans le contrat (rétrocompatible ; absent = M0) ;
  - créer les compétences de français dans le référentiel.
- **Tests** :
  - le moteur reste inchangé et ses tests aussi ;
  - nouveaux tests API : conversion, premier essai seul, version, question sans compétence ignorée, isolement
    entre élèves ;
  - non-régression de la progression des maths.
- **Choix de la question suivante** : les réponses converties ne doivent servir **qu'au calcul de la maîtrise**,
  jamais à `choisir_prochaine_question` (`selection.py`) (identifiants de questions distincts, sinon effets de bord).

### 10.5 Risques de double comptabilisation

1. **Essais répétés** : un élève qui recommence le même quiz jusqu'à réussir ferait monter sa maîtrise par
   mémorisation. Proposition : ne compter que le **premier essai**, déjà figé (#110).
2. **Même question à deux endroits** (chapitre et quiz) : comptée deux fois. Proposition : une question n'existe
   qu'à un seul endroit (règle de contenu vérifiée à l'import).
3. **Poids d'un quiz** : 9 réponses d'un coup peuvent remplir presque toute la fenêtre de 10 réponses d'une
   compétence. C'est une décision pédagogique, pas technique.
4. **Changement de version** : sans la version dans la réponse, une réponse peut être rattachée à la mauvaise
   question (R6).

### 10.6 Décisions pédagogiques nécessaires

- **Professeur** : quelles questions de quiz mesurent une **compétence transférable** (et laquelle), et lesquelles
  ne mesurent que la compréhension d'**un** texte ? Faut-il un taux de maîtrise pour les cours de 3e ?
- **Professeur** : un quiz doit-il peser autant que des exercices servis un par un ?
- **Propriétaire** : M1 pour janvier, et M2 à étudier après le pilote ?

## 11. Version de Node.js — vérification

Constat sur `develop` `88e6ea6` (C) :

| Emplacement | Version |
|---|---|
| `.github/workflows/ci.yml`, job « Front » | `^24.15.0` (#197) |
| `.github/workflows/dev-deploy.yml` (publication DEV) | `^24.15.0` (#205, PR #206) |
| `deploy/Dockerfile.web` (image de compilation) | `node:24.15.0-alpine` (PR #207) |
| `.github/workflows/recette-francais.yml` | `^24.15.0` |
| `.github/workflows/pkp-anglais-beta.yml` | `20` |
| `.nvmrc` | `20` |
| `AGENTS.md` § 3 | « Node.js **20** (`.nvmrc`) » |
| `scripts/preparer-environnement.sh` | `NODE_VERSION=20.20.2`, contrôlé contre `.nvmrc` |

**Version de référence : Node 24.15**, celle de la CI, de la publication DEV et de l'image. **Correction** : la
première version de ce document affirmait que `ci.yml` utilisait Node 20 ; c'était faux. Les fichiers `.nvmrc`,
`AGENTS.md` § 3, `scripts/preparer-environnement.sh` et `pkp-anglais-beta.yml` sont restés à Node 20. C'est une
contradiction documentaire qui n'est **pas tranchée ici** (AGENTS.md § 0). Proposition : une PR dédiée, rattachée à
#197 ou #205, qui aligne les quatre emplacements sur 24.15. `pkp-anglais-beta.yml` touche un workflow : il demande
une issue dédiée (AGENTS.md § 1).

L'environnement local de recette de l'agent utilisera Node 24.15. Il ne réintroduit pas Node 20.
