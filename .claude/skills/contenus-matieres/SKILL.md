---
name: contenus-matieres
description: Créer ou modifier un contenu pédagogique (contenu/**/*.yaml, cours, corrigés, dossiers de français) ou ajouter une matière. À charger avant toute modification de contenu/ ou du paramétrage d'une matière.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Contenus pédagogiques et matières

| Sujet | Document qui fait foi (lire la section utile) |
|---|---|
| Format YAML, registre des sources, corrigés, difficulté | `docs/CONTENU.md` |
| Format d'import Français | `docs/francais/FORMAT-IMPORT.md` |
| Ajouter une matière (paramétrage, contrôles par rôle, recette) | `docs/MATIERES.md` § 4 |
| Relecture et validation humaines | `docs/PROTOCOLE-RELECTURE-PEDAGOGIQUE.md`, `docs/PREVALIDATION-IA.md` |

Rappels permanents (`AGENTS.md` § 3) : registre des sources rempli, rien de `sources/` versionné, aucune question
supprimée, aucun corrigé visible par l'élève avant sa réponse, validation réservée à un professeur.

Après modification : `(cd api && python -m app.contenu verifier)`, puis `inventaire` et, si les corrigés changent,
`corrections` ; inclure les fichiers régénérés dans le commit.
