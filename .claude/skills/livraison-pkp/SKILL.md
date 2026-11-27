---
name: livraison-pkp
description: Versions, tags, releases, livraison Boussole et synchronisation vers PKP Éducation. À charger avant toute modification touchant une release, un tag, une migration livrée, un déploiement ou le dépôt PKP.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Livraison Boussole et PKP

Sources qui font foi : `docs/VERSIONNING.md` (tags `boussole-v*` et `pkp-v*`, circuit GO / NO-GO) et
`docs/PKP-LIVRAISON-ASSOCIATIVE.md` (transfert vers PKP Éducation).

- L'agent prépare : PR dédiée, dossier de livraison (SHA complet, migrations, sauvegarde, retour arrière). Il ne
  crée ni tag ni release de production et ne déploie pas : GO humain explicite (`AGENTS.md` § 1).
- Vers PKP : inventaire explicite des commits et fichiers ; exclure prix, paiement, abonnement, facturation,
  secrets et fonctionnalités commerciales ; conserver le nom « PKP Éducation » et ses configurations propres.
- `import-pkp-main.yml` importe dans l'autre sens (PKP `main` → branche `migration-pkp-vers-boussole`).
- Un contrôle annoncé par la politique mais pas encore imposé par la CI se signale comme manquant ; ne jamais le
  présenter comme automatisé.
