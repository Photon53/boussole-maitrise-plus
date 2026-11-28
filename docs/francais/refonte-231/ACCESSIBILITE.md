<!-- Issue #231 — Rapport d'accessibilité des écrans Français, pour #154 (Claude) -->
# Accessibilité des écrans Français : rapport de contrôle

Issue #231 (passe finale, PR 5), pour #154. Rédigé par Claude (Claude Code), 27/11/2026.

**Ce rapport n'est pas un audit de conformité.** Il consigne des contrôles automatiques et un parcours au clavier
scripté sur les écrans de la refonte Français. Il ne remplace ni un essai avec un lecteur d'écran, ni un essai avec des
élèves et un référent (#154 § « Travail attendu »).

## Méthode

- **Version** : branche `feat/issue-231-accessibilite` (`develop` + espace parent #249), base locale jetable.
- **Outil** : [`scripts/recette/accessibilite-francais.mjs`](../../../scripts/recette/accessibilite-francais.mjs), dans
  Chromium (Playwright), préférence « réduire les animations » active, comptes fictifs. Le script refuse toute
  adresse non locale.
- **Contrôle automatique** : axe-core 4.14.0 (licence MPL 2.0, dépendance de développement seulement), règles
  WCAG 2.0 et 2.1, niveaux A et AA, sur 17 écrans × 2 tailles (1 366 px et 390 px), soit 34 contrôles :
  élève (accueil, mes cours, dossier par étape, cours par étape, exercice, correction, progression, « Plus »),
  professeur, validateur, administrateur, parent.
- **Recomposition** : largeur de 320 px (équivalent d'un zoom à 400 % sur 1 280 px, WCAG 1.4.10), aucun défilement
  horizontal de la page.
- **Clavier** : parcours complet sans souris ni clic, focus visible relevé à chaque étape.

Reproduire, après avoir lancé une pile locale jetable :

```bash
BASE_URL=http://127.0.0.1:5765 SORTIE=rapport-a11y node scripts/recette/accessibilite-francais.mjs
```

## Obstacles trouvés et corrigés

| Obstacle | Effet | Correction |
|---|---|---|
| Liste des sept étapes masquée sur mobile et tablette | L'élève ne pouvait que passer à l'étape suivante ou précédente | Bande d'étapes défilante, toutes les étapes atteignables (`styles.css`) |
| Texte du dossier et tableaux qui défilent sans être atteignables au clavier (`scrollable-region-focusable`) | Contenu non lisible au clavier | Régions nommées, `tabIndex=0` (`LectureDossier.jsx`, `TableauFrancais.jsx`, `FrancaisAdmin.jsx`) |
| Contraste insuffisant des badges « ok » (3,9:1), « alerte » (4,3:1) et « accent » (2,7:1) | Texte peu lisible, dans toute l'application | Jetons de texte `--ok-texte`, `--alerte-texte`, `--accent-texte` (≥ 5,5:1 en clair ; mode sombre déjà conforme) |
| `aria-expanded` sur un champ de recherche (`aria-allowed-attr`, critique) | Recherche globale de l'administration mal annoncée | Rôle `combobox` avec `aria-autocomplete="list"` (`BandeauAdmin.jsx`) |
| Contenu des espaces adultes élargi par un tableau large | Défilement horizontal de toute la page sur mobile (page « Validation ») | `minmax(0, 1fr)` et `min-width: 0` sur la colonne de contenu (`styles.css`) : le tableau défile dans son cadre |
| Changement d'étape sans annonce | Le lecteur d'écran ne signale pas le nouveau contenu | Le focus va au titre de l'étape (`EcranCours.jsx`, `LectureDossier.jsx`) |

## Résultats, version b466aee


| Rôle | Écran | Taille | Violations axe | Débordement horizontal |
|---|---|---|---|---|
| eleve | Accueil Français | ordinateur | aucune | non |
| eleve | Mes cours | ordinateur | aucune | non |
| eleve | Dossier · Découvrir | ordinateur | aucune | non |
| eleve | Dossier · Appliquer (quiz) | ordinateur | aucune | non |
| eleve | Dossier · S'entraîner (texte et questions) | ordinateur | aucune | non |
| eleve | Dossier · Consolider | ordinateur | aucune | non |
| eleve | Cours · Comprendre | ordinateur | aucune | non |
| eleve | Cours · S'entraîner | ordinateur | aucune | non |
| eleve | Exercice | ordinateur | aucune | non |
| eleve | Correction | ordinateur | aucune | non |
| eleve | Ma progression | ordinateur | aucune | non |
| eleve | Plus | ordinateur | aucune | non |
| professeur | Tableau de bord | ordinateur | aucune | non |
| professeur | Mes classes | ordinateur | aucune | non |
| validateur | Validation des questions | ordinateur | aucune | non |
| administrateur | Page Français | ordinateur | aucune | non |
| parent | Bilan Français | ordinateur | aucune | non |
| eleve | Accueil Français | mobile | aucune | non |
| eleve | Mes cours | mobile | aucune | non |
| eleve | Dossier · Découvrir | mobile | aucune | non |
| eleve | Dossier · Appliquer (quiz) | mobile | aucune | non |
| eleve | Dossier · S'entraîner (texte et questions) | mobile | aucune | non |
| eleve | Dossier · Consolider | mobile | aucune | non |
| eleve | Cours · Comprendre | mobile | aucune | non |
| eleve | Cours · S'entraîner | mobile | aucune | non |
| eleve | Exercice | mobile | aucune | non |
| eleve | Correction | mobile | aucune | non |
| eleve | Ma progression | mobile | aucune | non |
| eleve | Plus | mobile | aucune | non |
| professeur | Tableau de bord | mobile | aucune | non |
| professeur | Mes classes | mobile | aucune | non |
| validateur | Validation des questions | mobile | aucune | non |
| administrateur | Page Français | mobile | aucune | non |
| parent | Bilan Français | mobile | aucune | non |

## Recomposition à 320 px

| Écran | Largeur de page | Résultat |
|---|---|---|
| Accueil Français | 320 | OK |
| Mes cours | 320 | OK |
| Dossier · Découvrir | 320 | OK |
| Dossier · Appliquer (quiz) | 320 | OK |
| Dossier · S'entraîner (texte et questions) | 320 | OK |
| Dossier · Consolider | 320 | OK |
| Cours · Comprendre | 320 | OK |
| Cours · S'entraîner | 320 | OK |

## Parcours au clavier seul

| Étape | Résultat | Détail |
|---|---|---|
| Connexion au clavier | OK | prénom, code classe, code personnel, Entrée |
| Accueil → reprendre le cours (Tab, Entrée) | OK | 7 appuis ; focus visible : oui |
| Rail des étapes au clavier | OK | 2 appuis ; focus visible : oui |
| Aller à l'entraînement | OK | 18 appuis |
| Répondre au clavier | OK | QCM : 11 appuis jusqu'au choix « A arrivé » ; focus visible : oui ; correction affichée ; focus ensuite sur « Question suivante » |
| Progression au clavier | OK | 11 appuis |

## Passe finale du 27/11/2026 (PR 5 de la refonte)

Mêmes outils, sur `develop` après la fusion de toute la refonte (exercice et correction #251, rédaction #253, file de
validation #255, correction des rédactions #258, « Ma progression » #259, découpage des styles #257). Le script ajoute :
la **tablette** (820 px), le **zoom à 200 %** (683 px de large, WCAG 1.4.4), l'**atelier de rédaction**, l'écran
**Rédactions** de la professeure et la **file de validation**, et peut enregistrer une capture de chaque écran
(`CAPTURES=1`).

**Résultat : 0 violation axe et aucun débordement horizontal sur 60 contrôles** (20 écrans × 3 tailles) ; recomposition
à 320 px et zoom à 200 % sans défilement horizontal ; parcours au clavier complet. Le QCM d'un exercice de français
reçoit désormais le focus sur son premier choix (0 appui, contre 11 avant #251).

Correctif de la passe : « Entrainement ciblé » devient « Entraînement ciblé » (écran d'exercice commun).

Complément du 28/11 : la **validation des dossiers** (#267) est auditée, avec une révision fictive du dossier soumise par l'administrateur (les élèves lisent toujours la version validée).

Recette des cinq rôles, avec l'avant et l'après de chaque écran : [`RECETTE-FINALE.md`](RECETTE-FINALE.md).

| Rôle | Écran | Taille | Violations axe | Débordement horizontal |
|---|---|---|---|---|
| eleve | Accueil Français | ordinateur | aucune | non |
| eleve | Mes cours | ordinateur | aucune | non |
| eleve | Dossier · Découvrir | ordinateur | aucune | non |
| eleve | Dossier · Appliquer (quiz) | ordinateur | aucune | non |
| eleve | Dossier · S'entraîner (texte et questions) | ordinateur | aucune | non |
| eleve | Dossier · Consolider | ordinateur | aucune | non |
| eleve | Cours · Comprendre | ordinateur | aucune | non |
| eleve | Cours · S'entraîner | ordinateur | aucune | non |
| eleve | Exercice | ordinateur | aucune | non |
| eleve | Correction | ordinateur | aucune | non |
| eleve | Rédaction · atelier | ordinateur | aucune | non |
| eleve | Ma progression | ordinateur | aucune | non |
| eleve | Plus | ordinateur | aucune | non |
| professeur | Tableau de bord | ordinateur | aucune | non |
| professeur | Mes classes | ordinateur | aucune | non |
| professeur | Rédactions | ordinateur | aucune | non |
| validateur | File de validation | ordinateur | aucune | non |
| validateur | Validation des dossiers | ordinateur | aucune | non |
| administrateur | Page Français | ordinateur | aucune | non |
| parent | Bilan Français | ordinateur | aucune | non |
| eleve | Accueil Français | tablette | aucune | non |
| eleve | Mes cours | tablette | aucune | non |
| eleve | Dossier · Découvrir | tablette | aucune | non |
| eleve | Dossier · Appliquer (quiz) | tablette | aucune | non |
| eleve | Dossier · S'entraîner (texte et questions) | tablette | aucune | non |
| eleve | Dossier · Consolider | tablette | aucune | non |
| eleve | Cours · Comprendre | tablette | aucune | non |
| eleve | Cours · S'entraîner | tablette | aucune | non |
| eleve | Exercice | tablette | aucune | non |
| eleve | Correction | tablette | aucune | non |
| eleve | Rédaction · atelier | tablette | aucune | non |
| eleve | Ma progression | tablette | aucune | non |
| eleve | Plus | tablette | aucune | non |
| professeur | Tableau de bord | tablette | aucune | non |
| professeur | Mes classes | tablette | aucune | non |
| professeur | Rédactions | tablette | aucune | non |
| validateur | File de validation | tablette | aucune | non |
| validateur | Validation des dossiers | tablette | aucune | non |
| administrateur | Page Français | tablette | aucune | non |
| parent | Bilan Français | tablette | aucune | non |
| eleve | Accueil Français | mobile | aucune | non |
| eleve | Mes cours | mobile | aucune | non |
| eleve | Dossier · Découvrir | mobile | aucune | non |
| eleve | Dossier · Appliquer (quiz) | mobile | aucune | non |
| eleve | Dossier · S'entraîner (texte et questions) | mobile | aucune | non |
| eleve | Dossier · Consolider | mobile | aucune | non |
| eleve | Cours · Comprendre | mobile | aucune | non |
| eleve | Cours · S'entraîner | mobile | aucune | non |
| eleve | Exercice | mobile | aucune | non |
| eleve | Correction | mobile | aucune | non |
| eleve | Rédaction · atelier | mobile | aucune | non |
| eleve | Ma progression | mobile | aucune | non |
| eleve | Plus | mobile | aucune | non |
| professeur | Tableau de bord | mobile | aucune | non |
| professeur | Mes classes | mobile | aucune | non |
| professeur | Rédactions | mobile | aucune | non |
| validateur | File de validation | mobile | aucune | non |
| validateur | Validation des dossiers | mobile | aucune | non |
| administrateur | Page Français | mobile | aucune | non |
| parent | Bilan Français | mobile | aucune | non |

### Recomposition à 320 px

| Écran | Largeur de page | Résultat |
|---|---|---|
| Accueil Français | 320 | OK |
| Mes cours | 320 | OK |
| Dossier · Découvrir | 320 | OK |
| Dossier · Appliquer (quiz) | 320 | OK |
| Dossier · S'entraîner (texte et questions) | 320 | OK |
| Dossier · Consolider | 320 | OK |
| Cours · Comprendre | 320 | OK |
| Cours · S'entraîner | 320 | OK |

### Zoom à 200 % (683 px)

| Écran | Largeur de page | Résultat |
|---|---|---|
| Accueil Français | 683 | OK |
| Mes cours | 683 | OK |
| Dossier · Découvrir | 683 | OK |
| Dossier · Appliquer (quiz) | 683 | OK |
| Dossier · S'entraîner (texte et questions) | 683 | OK |
| Dossier · Consolider | 683 | OK |
| Cours · Comprendre | 683 | OK |
| Cours · S'entraîner | 683 | OK |

### Parcours au clavier seul

| Étape | Résultat | Détail |
|---|---|---|
| Connexion au clavier | OK | prénom, code classe, code personnel, Entrée |
| Accueil → reprendre le cours (Tab, Entrée) | OK | 7 appuis ; focus visible : oui |
| Rail des étapes au clavier | OK | 2 appuis ; focus visible : oui |
| Aller à l'entraînement | OK | 18 appuis |
| Répondre au clavier | OK | QCM : 0 appuis jusqu'au choix « A arrivé » ; focus visible : oui ; correction affichée ; focus ensuite sur « Question suivante » |
| Progression au clavier | OK | 11 appuis |

## Limites et suite

- **Lecteur d'écran** : non essayé (NVDA, VoiceOver). Les rôles et noms vérifiés par axe ne garantissent pas une
  restitution compréhensible : essai à faire avec le référent (#154).
- **Essais avec des élèves** : à faire pendant le pilote, notamment la charge des consignes après distraction.
- **Zoom 200 %** : mesuré par une fenêtre de 683 px (passe finale) ; le zoom réel du navigateur, police comprise,
  reste à essayer à la main.
- **Exercice au clavier** : réglé en français (#251, focus sur le premier choix d'un QCM) ; les maths gardent leur
  comportement tant que ce n'est pas décidé pour toutes les matières.
- **Fonctions non livrées** : aucun réglage de taille, d'espacement ou de police « DYS », aucune lecture audio ; #154
  demande de ne pas les présumer et de les cadrer séparément.
- **Écrans hors refonte** (cours de maths, anglais) : non audités ici ; seules les corrections communes (badges,
  colonne de contenu adulte, recherche) les touchent.
