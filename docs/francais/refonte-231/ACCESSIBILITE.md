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

## Limites et suite

- **Lecteur d'écran** : non essayé (NVDA, VoiceOver). Les rôles et noms vérifiés par axe ne garantissent pas une
  restitution compréhensible : essai à faire avec le référent (#154).
- **Essais avec des élèves** : à faire pendant le pilote, notamment la charge des consignes après distraction.
- **Zoom 200 % réel du navigateur** : couvert indirectement par la recomposition à 320 px et 390 px.
- **Exercice au clavier** : un QCM demande 11 appuis sur Tab depuis le haut de la page, car le focus n'est pas placé
  sur la question à son affichage (il l'est pour une réponse courte). Amélioration proposée, sans effet sur les maths
  tant qu'elle n'est pas décidée pour toutes les matières.
- **Fonctions non livrées** : aucun réglage de taille, d'espacement ou de police « DYS », aucune lecture audio ; #154
  demande de ne pas les présumer et de les cadrer séparément.
- **Écrans hors refonte** (cours de maths, anglais) : non audités ici ; seules les corrections communes (badges,
  colonne de contenu adulte, recherche) les touchent.
