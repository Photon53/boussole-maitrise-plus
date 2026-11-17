<!-- Issue #148 — Accueils Boussole et PKP (Claude) -->
# Variantes de présentation : Boussole Maîtrise+ et PKP Éducation

Une seule application, deux présentations publiques. Les écrans, les droits, l'API et la base sont communs ;
seuls les textes de l'accueil et l'identité (nom, logo, titre de l'onglet, pied de page) changent.

| Variante | Code | Public visé | Particularités |
|---|---|---|---|
| Boussole Maîtrise+ | `boussole` (par défaut) | familles et professionnels ; offre commerciale **en préparation, non annoncée** | monogramme boussole, Méthode Spirale mise en avant |
| PKP Éducation | `pkp` | projet associatif | logo texte, pas de mention « Spirale » ni « Maîtrise+ » sur l'accueil |

## Choisir la variante

Aucun mécanisme de marque n'existait sur `develop` avant l'issue #148. La configuration retenue est minimale :
une variable lue **à la construction** du front.

```bash
(cd web && npm run build)                      # Boussole Maîtrise+ (comportement inchangé)
(cd web && VITE_MARQUE=pkp npm run build)      # PKP Éducation
```

- Sans variable, ou avec une valeur inconnue, c'est Boussole : la CI, l'image Docker et le déploiement DEV ne
  changent pas.
- Les textes de chaque variante sont dans `web/src/marque.js` ; la page d'accueil `web/src/Accueil.jsx` est
  commune et reçoit la variante en paramètre (les tests vérifient les deux).
- Les cinq étapes de la méthode et les conseils fixes sont dans `web/src/methodeEtapes.js`, sans KaTeX : l'accueil
  reste léger.

## Ce qui n'est pas fait (hors périmètre de #148)

- **Aucune publication PKP** : pas de nouveau déploiement, d'image ni de synchronisation avec le dépôt PKP. Publier
  la variante PKP demande une décision du propriétaire (domaine, construction dédiée avec `VITE_MARQUE=pkp`).
- Les espaces connectés (élève, parent, professeur, administration) gardent les libellés actuels
  (« Boussole Maths », « Boussole Anglais », menus « Boussole Éducation ») : seuls l'en-tête public, le pied de page
  et la page Méthode suivent la variante.
- Le texte de `web/index.html` (`<title>`, description) reste celui de Boussole ; le titre de l'onglet est remplacé
  au chargement par celui de la variante.
- Aucun tarif, témoignage ni résultat n'est affiché ; aucune mention d'ouverture commerciale.
- Aucun diagnostic de niveau n'existe dans l'application : l'aide « Comment bien travailler ? » n'y renvoie donc pas.
