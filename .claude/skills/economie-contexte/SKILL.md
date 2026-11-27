---
name: economie-contexte
description: Réduire les tokens consommés par mission sans perte de qualité — lecture ciblée, sous-agents, choix du modèle, restitutions courtes, reprise de contexte. À charger au début d'une mission longue ou multi-agents.
---
<!-- Issue #252 — Économie de contexte et intégration (Claude) -->

# Économie de contexte

L'indicateur suivi : tokens consommés par ticket terminé, testé et stable, reprises et sous-agents compris.

## Lire peu, lire juste

- Partir de l'issue et du diff concerné ; ouvrir une section (`grep -n` puis lecture par plage), pas un document entier.
- Ne pas relire un fichier déjà lu dans la session, ni la documentation générale à chaque mission.
- Décisions : `grep -n "<identifiant>" docs/DECISIONS.md` plutôt que la lecture complète.

## Sous-agents

- Seulement pour une exploration large (beaucoup de fichiers, réponse courte attendue) ou des tâches réellement
  indépendantes ; pas pour une recherche que deux `grep` règlent.
- Consigne de restitution : « réponds en moins de 15 lignes : `fichier:ligne`, conclusion, anomalies, actions ».
- Un seul agent explore un sujet ; son résultat utile aux autres est posté dans l'issue.

## Modèle et effort

| Tâche | Modèle |
|---|---|
| Recherche, inventaire, résumé, analyse de journaux | Haiku (sous-agent `Explore` ou `model: haiku`) |
| Développement courant, tests, correction, relecture, intégration | Sonnet (défaut) |
| Architecture complexe, incident difficile, refactorisation majeure, risque élevé | Opus |

Le modèle de la session principale est réglé par la personne (`/model`) ; l'agent choisit celui des sous-agents.
Effort de raisonnement proportionné : bas pour une modification mécanique, élevé seulement pour un vrai risque.

## Cache et reprise

- `AGENTS.md` est le préfixe stable : ne pas y mettre d'information datée ou propre à une mission.
- Missions indépendantes : contexte neuf (`/clear` ou nouvelle session) après avoir consigné l'état utile dans
  l'issue ou la PR (fait, reste à faire, branche, SHA).
- Pas de résumés ou rapports intermédiaires sans lecteur ; un bilan final court suffit.
- Sorties de commandes longues : skill `controles-ci`, § Journaux.
