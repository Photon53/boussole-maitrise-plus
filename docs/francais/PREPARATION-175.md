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

## 3. EX.4 — persistance des présentations (décision à prendre)

**Rappel.** EX.4 refuse toute nouvelle classe ou tout nouveau groupe dans un domaine non public. SEC-D6 autorise
déjà, par exception, les **classes pilotes** désignées par un administrateur. Le mode de correction (#110) est
déjà porté par la classe (`classe.mode_correction`) et par dossier ouvert
(`mode_correction_dossier_francais`, migration `0049`), avec une règle « contenu explicite, sinon classe ».

| Option | Description | Impacts | Avis |
|---|---|---|---|
| **1. Classe + contenu ouvert** | Présentation par défaut de la **classe** (nouvelle colonne), surcharge possible pour un **contenu ouvert** à la classe (chapitre ou dossier), sur le modèle exact du mode de correction. La « séance » de #111 devient le contenu ouvert pour une période | Une migration, aucun nouveau groupe, **aucune exception à EX.4** (la classe pilote existe déjà) ; règle « séance → groupe → guidé » respectée au sens « contenu → classe → guidé » ; tests calqués sur ceux du mode de correction | **Recommandée** |
| 2. Groupes de préparation sans élèves | Option 1 de la fiche #111 : groupes créés par le professeur dans un domaine fermé, sans élève, pour préparer | Exception explicite à EX.4, nouveau CRUD, nouveaux tests d'isolement ; ne sert pas les élèves du pilote | Non recommandée pour janvier |
| 3. Sous-groupes d'une classe | Groupes de besoin à l'intérieur d'une classe pilote, avec leur présentation | Nouvelle entité, affectation d'élèves, impacts sur le suivi et le RGPD ; utile pour la différenciation | Après le pilote |

**Proposition.** Retenir l'option 1 pour la PR 3 et noter l'option 3 comme évolution. L'élève ne choisit jamais la
présentation (décision du 14/11). Sans arbitrage, la PR 3 livre le parcours guidé **sans réglage persistant**.

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

**Constat.** `recette-francais.yml` (#219) relance `tests/test_francais.py` et les tests front, déjà exécutés par
`ci.yml`, sans navigateur, avec Node `^24.15.0` alors que `ci.yml` et `.nvmrc` utilisent Node 20. Aucun des deux
workflows ne déclare `concurrency`.

**Proposition** (à valider avant implémentation ; modification de `.github/workflows/**` sous #223) :

- Remplacer les deux jobs de `recette-francais.yml` par un job unique « Recette navigateur Français » :
  Python 3.12 et Node 20 avec cache pip et npm, cache de Chromium (`~/.cache/ms-playwright`, clé = version de
  Playwright), `bash scripts/recette/pile-locale.sh rapports/`, rapport et captures en artefact (14 jours).
- `concurrency: { group: recette-francais-${{ github.ref }}, cancel-in-progress: true }`.
- Déclenchement `pull_request` vers `develop` et `main` sur ces chemins :
  `api/app/**`, `api/migrations/**`, `engine/**`, `web/src/**`, `web/package*.json`, `web/vite.config.*`,
  `contenu/francais/**`, `scripts/recette/**`, `api/pyproject.toml`, `engine/pyproject.toml`,
  `.github/workflows/recette-francais.yml`. Exclus : `docs/**`, `*.md`, contenus maths et anglais,
  `infrastructure/**`.
- `workflow_dispatch` (demande manuelle) et exécution sur la branche de livraison avant chaque fusion vers `main`.
- Une seule exécution de la recette par PR et par commit ; pas de matrice de navigateurs.

**Coûts estimés.**

| Élément | Valeur |
|---|---|
| Durée observée de `recette-francais.yml` actuel | environ 1 min par job, 2 jobs |
| Durée estimée du job proposé | 5 à 7 min (installation en cache 2 min, Chromium en cache, recette 2 à 3 min) |
| Exécutions | Une par commit poussé sur une PR concernée, les obsolètes annulées |
| Dépôt | **Public** : minutes des exécuteurs standard **gratuites** |
| Si le dépôt devenait privé | 0,006 $ par minute Linux 2 cœurs (barème GitHub en vigueur, à revérifier), arrondi à la minute par job : environ 60 exécutions par mois × 7 min ≈ 2,50 $ |

Le job proposé remplace deux jobs redondants : à fréquence égale, le volume net ajouté est d'environ 4 à 5 minutes
par exécution.

## 8. Captures et maquettes

- **Captures des interfaces actuelles** : non réalisées au 26/11. L'environnement de l'agent n'avait ni accès aux
  paquets Python ni accès npm. Chromium est disponible. Réglage réseau demandé au propriétaire : PyPI et npm
  seulement (voir le compte rendu dans #175). Elles seront faites sur pile locale jetable, avec des données fictives,
  pour les cinq rôles et trois tailles d'écran, et jointes à #231.
- **Maquettes cibles** : [`maquettes/maquettes-francais.html`](maquettes/maquettes-francais.html), rendues en
  images pour la relecture : élève (ordinateur, tablette, mobile), parent (ordinateur, mobile), professeur,
  validateur et administrateur (ordinateur). Elles sont conceptuelles, avec des données fictives, reprennent les
  jetons de `web/src/theme.css` et restent soumises à la validation du propriétaire. Points à arbitrer sur les
  maquettes :
  - l'élève voit **cinq entrées** : les quatre rubriques et « Comprendre un texte » (dossiers de compréhension et de
    brevet), conformément à l'organisation cible du 26/11 ;
  - la progression de l'élève et du parent sépare les résultats autocorrigés (maîtrise) des retours humains (R8) ;
  - le professeur change la présentation de sa classe (suppose l'option 1 d'EX.4, § 3) ;
  - la file du validateur réunit chapitres et dossiers ;
  - l'administrateur voit l'état des drapeaux A5 et A6 **sans pouvoir les modifier** depuis l'écran.

## 9. Risques, blocages et décisions encore nécessaires

| # | Point | Type | Décideur |
|---|---|---|---|
| R1 | Contenus : 1 cours sur 8, aucune question autocorrigée de chapitre ; validation par le professeur sur le chemin critique | Risque calendrier | Professeur |
| R2 | Pas de preuve sur DEV depuis #221 et #226 | Blocage du GO pilote | Propriétaire (A7) |
| R3 | Production associative (#228) : affichage incomplet signalé | Risque | Propriétaire |
| R4 | En français, les types d'exercices autocorrigés sont `qcm` et `texte` ; `choix_multiples` est réservé au diagnostic. La variété de formats demandée par #175 en dépend | Contrainte | Information |
| R5 | `docs/CONTENU.md` ne décrit pas le type `texte` dans son tableau des types | Écart documentaire | À corriger dans la PR de contenu |
| D1 | Arbitrage EX.4 (§ 3) | Décision | Propriétaire |
| D2 | Participation des parents au pilote (priorité de la PR 1) | Décision | Propriétaire |
| D3 | Validation de la liste des huit cours | Décision | Professeur |
| D4 | Validation des maquettes | Décision | Propriétaire |
| D5 | Configuration de #223 (§ 7) | Décision | Propriétaire |
