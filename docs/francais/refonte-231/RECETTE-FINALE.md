<!-- Issue #231 — Recette finale de la refonte Français : cinq rôles, avant et après (Claude) -->
# Refonte Français : recette finale des cinq rôles

Issue #231, PR 5 de la refonte (passe finale). Rédigé par Claude (Claude Code), le 27/11/2026.

Cette recette a été faite sur `develop`, une fois toute la refonte fusionnée, avec une base locale jetable et des
comptes fictifs. Elle ne remplace ni l'essai par la professeure et le validateur sur DEV, ni un essai avec des élèves,
ni un essai avec un lecteur d'écran (#154). Ces essais relèvent du propriétaire.

## Ce qui a été vérifié

| Contrôle | Outil | Résultat |
|---|---|---|
| Recette fonctionnelle multi-rôles (élève, professeure, validateur, administrateur, parent) | `scripts/recette/pile-locale.sh` | 20/20 |
| Accessibilité automatique, 20 écrans × 3 tailles (1 366, 820 et 390 px) | `scripts/recette/accessibilite-francais.mjs` (axe-core, WCAG 2.1 A et AA) | 0 violation sur 60 contrôles |
| Débordement horizontal, mêmes écrans et mêmes tailles | idem | aucun |
| Zoom à 200 % (683 px) et recomposition à 320 px | idem | aucun défilement horizontal |
| Parcours au clavier seul : connexion, cours, exercice, réponse, correction, progression | idem | complet, focus visible |
| Tests automatiques | Vitest, pytest (API et moteur) | tous verts (voir la PR) |

Le détail par écran se trouve dans [`ACCESSIBILITE.md`](ACCESSIBILITE.md), section « Passe finale ».

## Avant et après, par rôle

Les captures « avant » viennent de l'audit initial ([`audit/`](audit/)). Les captures « après » ont été prises sur les
écrans livrés ([`apres/`](apres/)).

### Élève

| Écran | Avant | Après |
|---|---|---|
| Accueil | [`eleve-ordinateur-cours`](audit/eleve-ordinateur-cours.png) : huit onglets, chapitres sans rubrique | [ordinateur](apres/eleve-ordinateur-accueil.png) · [tablette](apres/eleve-tablette-accueil.png) · [mobile](apres/eleve-mobile-accueil.png) : reprise du cours, quatre rubriques |
| Mes cours | [`eleve-ordinateur-cours`](audit/eleve-ordinateur-cours.png) : dossiers et chapitres séparés | [ordinateur](apres/eleve-ordinateur-mes-cours.png) · [mobile](apres/eleve-mobile-mes-cours.png) : une seule liste, filtrable |
| Cours en sept étapes | [`eleve-ordinateur-mon-cours`](audit/eleve-ordinateur-mon-cours.png) | [Comprendre](apres/eleve-ordinateur-cours-comprendre.png) · [S'entraîner](apres/eleve-ordinateur-cours-sentrainer.png) · [mobile](apres/eleve-mobile-cours-comprendre.png) |
| Dossier de lecture | [`eleve-ordinateur-dossier-ouvert-haut`](audit/eleve-ordinateur-dossier-ouvert-haut.png) : mentions internes visibles (N2) | [texte et questions côte à côte](apres/eleve-ordinateur-dossier-etapes.png) |
| Exercice et correction | [`eleve-ordinateur-s-entrai-ner`](audit/eleve-ordinateur-s-entrai-ner.png) | [question](apres/exercice-ordinateur-question.png) · [correction expliquée](apres/exercice-ordinateur-correction.png) · [mobile](apres/exercice-mobile-correction.png) |
| Rédaction | [`eleve-ordinateur-re-daction`](audit/eleve-ordinateur-re-daction.png) : « pas encore ouverte » sans consigne | [atelier, brouillon sur l'appareil](apres/redaction-ordinateur-fermee.png) · [tablette](apres/eleve-tablette-redaction.png) · [mobile](apres/redaction-mobile-fermee.png) |
| Ma progression | [`eleve-ordinateur-ma-progression`](audit/eleve-ordinateur-ma-progression.png) : barres par compétence | [ordinateur](apres/progression-ordinateur.png) · [tablette](apres/eleve-tablette-progression.png) · [mobile](apres/progression-mobile.png) |

### Professeure

| Écran | Avant | Après |
|---|---|---|
| Accueil | [`professeur-ordinateur-accueil`](audit/professeur-ordinateur-accueil.png) : « Boussole Maths » pour une professeure de français | [tableau de bord](apres/professeur-ordinateur-tableau-de-bord.png) · [tablette](apres/professeur-tablette-tableau-de-bord.png) · [mobile](apres/professeur-mobile-tableau-de-bord.png) |
| Classes | [`professeur-ordinateur-francais-suivi-des-classes`](audit/professeur-ordinateur-francais-suivi-des-classes.png) | [mes classes](apres/professeur-ordinateur-classes.png) |
| Rédactions | (liste brute, message d'erreur quand c'est fermé) | [liste](apres/redactions-ordinateur-liste.png) · [correction en deux colonnes](apres/redactions-ordinateur-correction.png) · [mobile](apres/redactions-mobile-correction.png) |

### Validateur

| Écran | Avant | Après |
|---|---|---|
| Validation des questions | [`validateur-ordinateur-validation-questions-haut`](audit/validateur-ordinateur-validation-questions-haut.png) : tableau d'environ 14 000 px (N6) | [file en deux volets](apres/validateur-ordinateur-file.png) · [tablette](apres/validateur-tablette-file.png) · [mobile](apres/validateur-mobile-file.png) |
| Validation des dossiers | [`validateur-ordinateur-francais-validation`](audit/validateur-ordinateur-francais-validation.png) : liste déroulante, dossier entier sur une seule page | [file et onglets](apres/validateur-ordinateur-dossier.png) · [corrigé](apres/validateur-ordinateur-dossier-corrige.png) · [tablette](apres/validateur-tablette-dossier.png) · [mobile](apres/validateur-mobile-dossier.png) (#267) |

### Administrateur

| Écran | Avant | Après |
|---|---|---|
| Page Français | [`administrateur-ordinateur-francais`](audit/administrateur-ordinateur-francais.png) | [ordinateur](apres/administrateur-ordinateur-francais.png) · [tablette](apres/administrateur-tablette-francais.png) · [mobile](apres/administrateur-mobile-francais.png) |

### Parent

| Écran | Avant | Après |
|---|---|---|
| Bilan de l'enfant | [`parent-ordinateur`](audit/parent-ordinateur.png) : « le français arrive bientôt » | [ordinateur](apres/parent-ordinateur-francais.png) · [tablette](apres/parent-tablette-francais.png) · [mobile](apres/parent-mobile-francais.png) |

## Ce qui reste hors de cette recette

- **Essais humains** : la professeure et le validateur sur DEV, des élèves pendant le pilote, un lecteur d'écran
  (NVDA, VoiceOver) avec le référent (#154). Ce sont des décisions et des essais du propriétaire.
- **Fonctions fermées** : la rédaction en ligne (`PKP_REDACTION_ACTIVE`) et les PDF de français
  (`PKP_PDF_FRANCAIS_OUVERT`) restent fermés. Leur ouverture est une décision RGPD du propriétaire.
- **Charte d'utilisation** (#183) : elle doit mentionner le brouillon de rédaction gardé sur l'appareil (RGPD-2 bis).
- **Maths et anglais** : leurs écrans n'ont pas été refaits (FR-UI-D5). Seuls les correctifs communs les touchent.
