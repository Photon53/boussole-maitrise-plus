---
name: integration-git
description: Branches, commits, PR, synchronisation avec develop, résolution des conflits et coordination de plusieurs agents en parallèle sur ce dépôt. À charger avant de créer une branche, d'ouvrir une PR, de mettre une branche à jour ou de résoudre un conflit.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Intégration Git

Les interdits (`AGENTS.md` § 2) et la traçabilité (§ 4) s'appliquent toujours ; cette skill dit comment faire.

## Circuit réel

Branche d'issue → PR vers `develop` (intégration ; chaque push publie le DEV via `dev-deploy.yml`) → `main`
(livraison Boussole, par une personne) → PKP : dépôt séparé `Photon53/pkp-math-lycee`, transfert sélectif selon
la skill `livraison-pkp`. Aucune branche `deploy` n'existe : ne pas en créer (gouvernance, `AGENTS.md` § 1).

## Démarrer

1. `git fetch origin develop` puis brancher depuis `origin/develop` (jamais depuis une autre branche de travail,
   sauf dépendance réelle : alors PR vers `develop` après fusion de la première, pas vers sa branche).
2. Avant de toucher un fichier partagé (liste ci-dessous), regarder les PR ouvertes qui le modifient :
   `gh pr list --state open --json number,headRefName,files` ; si l'une le touche, rester dans une zone distincte
   du fichier ou attendre sa fusion pour cette partie et avancer sur le reste.

## Fichiers partagés et règles anti-conflit

| Fichier | Règle |
|---|---|
| `docs/*/README.md` avec tableau d'avancement | ne plus y ajouter de ligne d'avancement : l'avancement va dans l'issue et la PR |
| `web/src/styles.css` | nouvelles règles d'un écran dans un fichier dédié `web/src/styles/<ecran>.css`, importé par le composant |
| `docs/CONTENU-INVENTAIRE.md`, `docs/audit/CORRIGES-INVENTAIRE.md`, `web/package-lock.json` | générés : jamais édités ni fusionnés à la main, régénérés |
| `api/migrations/versions/` | une seule tête Alembic : après synchronisation, `(cd api && alembic heads)` ; si deux têtes, renuméroter la sienne et corriger `down_revision` vers la tête de `develop` |
| `scripts/recette/recette-francais.mjs`, `web/src/eleve/EspaceEleve.jsx` | modifications courtes et localisées ; pas de réindentation ni de réordonnancement |

## Synchroniser et résoudre

`bash scripts/synchroniser-branche.sh` : fusionne `origin/develop` dans la branche courante (jamais de rebase sur
une branche qui porte une PR), régénère les fichiers générés en conflit, et s'arrête en listant les autres
conflits. Passer `AGENT=<agent> ISSUE=<n>` pour que le commit de régénération des inventaires porte
`(#N)`, `Agent:` et `Refs:` (le numéro se déduit d'une branche `…issue-<n>-…`). Résoudre les autres conflits soi-même : garder les deux apports quand ils s'ajoutent (lignes de tableau, règles
CSS, tests), choisir le code de `develop` puis réappliquer son intention quand ils se contredisent. Lancer ensuite
les tests ciblés des fichiers touchés, puis les contrôles complets avant de pousser (skill `controles-ci`).

Synchroniser **une fois**, juste avant de demander la relecture ou après la fusion d'une PR qui touche les mêmes
fichiers ; pas à chaque commit (chaque push relance la CI).

## Plusieurs agents en parallèle

- Un périmètre par agent (écran, route, matière) ; fichiers partagés selon le tableau ci-dessus.
- Intégration séquentielle : une PR fusionnée à la fois ; les autres se synchronisent ensuite.
- Pousser par lots (fin d'étape testée), pas à chaque commit.
- Un résultat d'exploration utile aux autres va dans un commentaire de l'issue, pas dans un nouveau fichier.

## Commentaire de traitement (issue)

```markdown
## Traitement — PR #<n>
**Fait** : …
**Fichiers** : `…`
**Tests** : `commande` → N passed ; `…` → non exécuté : raison ; vérifié par la CI (job « … »)
**Choix d'agent** : … (option écartée : …)
**Reste à faire / limites** : …
<sub>🤖 Produit par **<Agent>** (<outil>), <date>.</sub>
```
