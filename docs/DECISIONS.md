# Registre des décisions — Boussole Maîtrise+

Ce registre **recense** les décisions structurantes du projet, sans les déplacer : chaque entrée renvoie au
document où la décision est argumentée. Il sert à répondre vite à « qu'a-t-on décidé, quand, et pourquoi ? » et à
voir ce qui reste à trancher.

## Comment lire les identifiants

Trois séries de décisions numérotées « D » ont été créées indépendamment, avec des numéros qui se chevauchent.
Pour lever l'ambiguïté, ce registre les **préfixe** ; les documents sources gardent leur numérotation.

| Préfixe | Source | Numéros utilisés |
|---|---|---|
| `SEC-D` | Audit de sécurité, `docs/audit/lot-a-securite.md`, `docs/audit/README.md` | D1 à D3 |
| `V2-D` | Cahier des charges V2, `docs/CAHIER-DES-CHARGES-V2.md` § 15 | D1 à D14 |
| `DEV-D` | Ticket #65 (pipeline DEV GitHub → GCP) et ses commentaires | D1 à D5 |
| `ARCH` | `docs/ARCHITECTURE.md` « Décisions validées » (non numérotées à la source) | — |
| `RGPD` | Décisions du propriétaire sur les données personnelles, consignées dans ce registre et `docs/RGPD.md` | 1 |

Exemple : « D1 » seul est ambigu ; `SEC-D1` désigne le code personnel des élèves, `V2-D1` le premier client visé,
`DEV-D1` la fusion de la PR #64.

Statuts : **Prise** (arbitrée et appliquée ou en cours d'application), **En attente** (à trancher),
**Suspendue** (décision reportée, avec la raison), **Écartée** (option refusée).

Attention : le tableau « Décisions à prendre » du cahier des charges V2 (§ 15) donne une **recommandation** pour
chacune de ses 14 décisions. Seules celles qui sont appliquées dans le code ou arbitrées par écrit sont
comptées ici comme prises (V2-D3, V2-D11) ; les autres restent en attente, recommandation comprise.

## Décisions prises

### Architecture et produit

| Id | Date | Décision | Conséquence | Source |
|---|---|---|---|---|
| ARCH-1 | 2026 (phase 1) | Moteur pédagogique pur, sans dépendance web ni base | `engine/` n'importe ni FastAPI ni SQLAlchemy ; `api/app/db/conversions.py` traduit | `docs/ARCHITECTURE.md` |
| ARCH-2 | phase 3 | Schéma normalisé (8 tables + `lecon`, puis extensions par migrations) | Toute modification de modèle exige une migration Alembic relue à la main | `docs/ARCHITECTURE.md` |
| ARCH-3 | phase 3 | Une question n'est jamais supprimée, elle est archivée | Colonne `archivee`, garde ORM `SuppressionInterdite`, clé étrangère `RESTRICT` | `docs/ARCHITECTURE.md` |
| ARCH-4 | phase 4 ; précisée le 2026-11-14 (#17) | La bonne réponse n'est révélée qu'après soumission. **Précision du propriétaire** : les corrigés sont réservés aux adultes (professeur, administrateur, parent) ; un élève ou un enfant ne voit le corrigé d'une question qu'après y avoir répondu, réponse enregistrée. Vaut pour les maths, l'anglais et le français | `QuestionPublique` sans solution ; `ResultatReponse` la renvoie ; fiches PKP Math (`/pkp-math/chapitres`) : `corrige_visible` faux et solution vide côté élève tant qu'aucune réponse n'est enregistrée. Anglais : vue élève sans corrigé ; reste ouvert le quiz envoyé vide, qui renvoie les bonnes réponses (#17) | `docs/ARCHITECTURE.md` |
| ARCH-5 | phase 2 | Maîtrise = taux 0–1 calculé sur les 10 dernières réponses, pondération 0,9, a priori 1, seuil 0,8 | `engine/src/pkp_engine/maitrise.py` ; pas de table dérivée | `docs/ARCHITECTURE.md` |
| ARCH-6 | 2026 | Code, documentation et vocabulaire en **français** | Tables, classes, routes, tests, commentaires en français ; pas de traduction anglaise des concepts | `docs/CONSIGNES-DEVELOPPEUR.md` (constat du dépôt) |
| V2-D3 | 2026-10-30 | Ne servir que les questions validées en production, chapitre par chapitre | **Appliquée dans le code** : réglage `PKP_SERVIR_QUESTIONS_NON_VALIDEES`, choix explicite obligatoire en production (E0.4) | CDC V2 § 15, § 5 |
| V2-D11 | 2026-11-03 | **Pas** de compte unique pour tous les utilisateurs | **Appliquée dans le code** : trois familles de comptes conservées ; rôles avec périmètre via `habilitation` (EX.6 à EX.9-bis, migration 0023) | CDC V2 § 3.2, § 15 |

### Sécurité et données personnelles

| Id | Date | Décision | Conséquence | Source |
|---|---|---|---|---|
| SEC-D1 | 2026-10-29 | Chaque élève a un **code personnel** généré par l'enseignant, stocké haché (correction de A-07) | Connexion = prénom + code classe + code personnel ; 5 essais / 15 min par compte ; comptes créés par l'enseignant | `docs/audit/lot-a-securite.md` § « Correction de A-07 (d) » |
| RGPD-1 | 2026-11-13 | **Enfant** : identifié par son **prénom suivi d'un numéro, sans séparateur** (`Lina1`, `Lina2`…), unique sur toute la plateforme, comparé sans casse ni accents (`Léa1` = `lea1`), numéro **jamais réattribué** ; **aucun nom de famille**. Base de l'identifiant : le prénom **sans accents**, lettres d'origine conservées (`à` → `a`, `é` → `e`), identifiant de **40 caractères au plus** (prénom raccourci). Les **identifiants déjà émis sont conservés** ; le nouveau format ne s'applique qu'aux nouveaux comptes. **Parent** : nom et prénom conservés | Pas encore appliquée dans le code : retrait de `Enfant.nom`, nouvel identifiant, migration avec sauvegarde préalable, contrainte d'unicité, limitation des tentatives revérifiée (#87) ; `docs/RGPD.md` mis à jour | #83 (décision du propriétaire), #87 |
| SEC-D3 | 2026-10 | Banque de questions commune : tout enseignant peut archiver toute question | Comportement actuel assumé (contrôle A-08) | `docs/audit/README.md`, `lot-a-securite.md` |
| DEV-D5 | 2026-11-13 | **Exception D5 (DEV)** : `boussole-dev-tf-plan` peut lister les objets du bucket de déploiement et leurs métadonnées, mais ne doit jamais lire leur contenu | Contrôle `scripts/controle-acces-sauvegardes.sh` affiche « exception D5 acceptée » ; aucun identifiant personnel dans les noms ni métadonnées des sauvegardes ; réduction des droits suivie dans #74 | #65 (commentaires du 13/11) |

### Pipeline DEV (GitHub → GCP), ticket #65

| Id | Date | Décision | Conséquence | Source |
|---|---|---|---|---|
| DEV-A1 à A8 | 2026-11-11 | Huit arbitrages d'architecture du pipeline : isolation DEV par surcharge Compose, rollback conditionné aux révisions Alembic réelles et aux données, manifestes immuables et pointeur conditionnel dans GCS, rétention Artifact Registry en simulation, fenêtre sans écriture pour sauvegarde et migration, contrôle de version par `docker inspect`, comptes WIF séparés par workflow, réutilisation CI seulement sur le SHA exact | Structure des PR 1 à 4 du ticket | #65, « Arbitrage après revue du 11/11 » |
| DEV-D1 | 2026-11-12 | Intégrer la PR #64 (déploiement manuel durci) avant la PR 3 | Fait : #64 fusionnée | #65 |
| DEV-D2 | 2026-11-12 | Retirer les liaisons IAM historiques du bucket via Terraform, en PR séparée (3a), **option A** : conserver uniquement `projectOwner` → `legacyBucketOwner` | Fait : #71 appliquée, politique vérifiée, PLAN `No changes` | #65, #71 |
| DEV-D3 | 2026-11-12 | En V1, l'état « version déployée » n'est connu que sur la VM (`active.json`, `--etat`, journaux) | Pas de remontée vers GCS pour l'instant | #65 |
| DEV-D5 | 2026-11-13 | Voir « Sécurité » ci-dessus | | |

## Décisions en attente

| Id | Décision à prendre | Recommandation documentée | Qui | Bloque |
|---|---|---|---|---|
| V2-D8 | Qui relit le contenu, à quel rythme, pour chaque domaine | **À prendre en premier** : fixe la date de vente | Propriétaire + référent pédagogique | La vente |
| V2-D5 | Statut juridique et TVA du vendeur | Avec un comptable, avant la première facture | Propriétaire | La vente |
| V2-D1 | Premier client : enseignant indépendant ou centre | Enseignant indépendant ; centre en lot 1-bis | Propriétaire | Lot 1 |
| V2-D7 | Domaines vendus au lancement | Maths lycée seul, ou Maths lycée + Anglais collège | Propriétaire | Lot 1, V2-D13 |
| V2-D9 | Contenu de l'offre Découverte | Tous les chapitres ; corrigés détaillés, devoirs et vue de classe réservés au payant | Propriétaire | Lot 1 |
| V2-D2 | Essai gratuit | 30 jours sans carte, puis Découverte | Propriétaire | Lot 1 |
| V2-D4 | Prestataire d'e-mails | Hébergé dans l'UE, choisi sur délivrabilité et prix | Propriétaire | Lot 1 (inscription) |
| V2-D6 | Hébergeur de production | Une VM dans l'UE ; région à confirmer | Propriétaire | Mise en production |
| V2-D13 | Seuil d'ouverture publique d'un domaine | Par exemple 80 % des compétences d'un niveau couvertes par du contenu publié | Propriétaire + référent | Ouverture de chaque domaine |
| V2-D10 | Avancer la vue de classe au lot 1 | Oui (recommandation du CDC, non actée) | Propriétaire | Périmètre du lot 1 |
| V2-D12 | Cadrage du français : types d'exercices, textes, auteurs | Fiche dédiée avant tout développement ; pas avant les vagues 1 et 2 | Propriétaire + référent | Lot D (français) |
| V2-D14 | Abonnement par domaine ou tous domaines inclus | Par domaine au lancement, bouquet plus tard | Propriétaire | Lot 1 (offres) |
| SEC-D2 | Politique de correction : forme exigée (développée, factorisée, simplifiée, libre) par question | Le moteur ne vérifie que l'équivalence ; le lot B de l'audit ne peut pas définir « correct » sans cette règle | Référent pédagogique | Audit lot B |
| DEV-D4 | Retirer `roles/editor` du compte Compute par défaut | Accord de principe ; **suspendu** tant que l'absence d'usage n'est pas démontrée (plusieurs contrôles incomplets) ; prévoir des droits de remplacement | Propriétaire | Rien (sécurité en profondeur) |
| DEV-#74 | Réduire les droits de `boussole-dev-tf-plan` après inventaire des besoins Terraform (option B de D5) | Rôle plus étroit sans permission de liste, bascule sans couper le PLAN | Propriétaire | Rien : l'exception D5 couvre la mise en service DEV |
| DEV-TS | Critère d'acceptation des accès aux sauvegardes : code 0 (confirmé par Policy Troubleshooter) exigé, ou dérogation au code 3 (analyse des politiques seule) | Code 0 exigé ; le diagnostic réel du 13/11 a renvoyé une **évaluation incomplète** (`NOT_GRANTED` avec erreurs), à analyser avant toute conclusion | Propriétaire | Première sauvegarde (PR 3b) |
| CONV-1 | Ajouter un linter et un formateur (ruff, ESLint) en CI | Oui, en PR dédiée après le ticket #65, formatage initial séparé | Propriétaire | Rien |
| CONV-2 | Licence du dépôt (UNLICENSE héritée de la migration) | À examiner avant commercialisation | Propriétaire | La vente |

Ordre conseillé par le cahier des charges : **V2-D8** et **V2-D5** (elles bloquent la vente), puis **V2-D1**,
**V2-D7** et **V2-D9** ensemble, puis les autres.

## Décisions écartées

| Id | Option écartée | Raison | Source |
|---|---|---|---|
| V2-D11 | Compte unique pour tous les utilisateurs (proposition V2.0) | Obligerait à migrer la connexion des élèves, la fonction la plus utilisée et la plus sensible, sans bénéfice | CDC V2 § 3.2 |
| DEV-D5 option B immédiate | Remplacer tout de suite `iam.securityReviewer` de `tf-plan` par un rôle personnalisé | Touche les droits du PLAN qui fonctionne ; demande un inventaire préalable ; ne bloque pas la mise en service | #65, #74 |
| DEV (PR 3a) | Autoriser la liste GCS par préfixe avec `objectListPrefix` dans une liaison conditionnelle | Attribut pris en charge seulement dans les Credential Access Boundaries | #65, commit annulé `f4e119a` |
| Consignes | Code en anglais (`Competency`, `MasteryLevel`…) | Le dépôt est intégralement en français ; deux vocabulaires dans le même code | `docs/CONSIGNES-DEVELOPPEUR.md` |

## Ajouter une décision

Une entrée tient sur une ligne : identifiant préfixé, date, décision, conséquence dans le code ou
l'exploitation, source. La discussion et les options comparées restent dans le document ou le ticket source ;
ce registre ne les duplique pas. Quand une décision en attente est prise, la déplacer dans « Décisions prises »
en gardant son identifiant.
