---
name: securite-rgpd
description: Sécurité, habilitations et données personnelles (mineurs, RGPD-1, isolation des périmètres, corrigés protégés). À charger avant de modifier un modèle de données, une route API, une habilitation ou une donnée sur une personne.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Sécurité et RGPD

Les invariants (`AGENTS.md` § 3) et les cas d'arrêt (§ 1) s'appliquent même sans cette skill.

| Sujet | Document qui fait foi |
|---|---|
| Minimisation, conservation, droits, espaces parents, rédactions | `docs/RGPD.md` (section utile), décisions `RGPD-` dans `docs/DECISIONS.md` |
| Audit de sécurité, lots corrigés, preuves | `docs/audit/README.md`, `docs/audit/lot-a-securite.md` |
| Architecture des habilitations | `docs/ARCHITECTURE.md` |

Contrôles avant PR, pour toute route ou modèle touché :

1. Nouvelle route d'adulte : `exiger(permission, domaine)` et filtre de périmètre ; test d'un adulte hors périmètre refusé.
2. Route élève : aucune `solution` ni texte d'un autre élève dans la réponse avant soumission ; test dédié.
3. Aucune nouvelle donnée sur un enfant (nom de famille, e-mail, date de naissance…) : sinon arrêt (§ 1).
4. Aucun secret ni donnée réelle dans le code, les tests, les journaux ou les captures.
