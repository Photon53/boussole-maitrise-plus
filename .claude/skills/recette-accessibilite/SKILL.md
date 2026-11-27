---
name: recette-accessibilite
description: Recette fonctionnelle multi-rôles dans un navigateur local et audit d'accessibilité (axe-core, clavier, 320 px). À charger pour vérifier un écran dans le vrai navigateur ou avant une PR d'interface.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Recette et accessibilité

Toujours contre la **pile locale jetable** ; vers une instance partagée, ces scripts sont interdits (`AGENTS.md` § 2).

| Besoin | Commande | Référence |
|---|---|---|
| Recette Français multi-rôles (Chromium, base SQLite temporaire) | `bash scripts/recette/pile-locale.sh` | `docs/RECETTE_AUTOMATIQUE_FRANCAIS.md`, `docs/francais/RECETTE-DEV.md` |
| Audit d'accessibilité (axe-core, recomposition 320 px, clavier) | `scripts/recette/accessibilite-francais.mjs` sur la pile locale | `docs/francais/refonte-231/ACCESSIBILITE.md` |

- Chromium et Playwright sont préinstallés dans les sessions cloud : ne pas réinstaller Playwright.
- Une PR d'interface Français : recette locale réussie, ou « non exécuté » avec la raison.
- Une capture n'entre dans le dépôt que si un document la cite.
