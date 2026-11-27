# Recette du Français sur GCP DEV — procédure du propriétaire

Issue #175 / #217 — Claude — 26/11/2026. Décision `V2-D12 — recette sur DEV (A7)`.

**Exécutée par le propriétaire uniquement.** Aucun agent n'intervient sur DEV (AGENTS.md § 1). Cette procédure
n'ouvre aucune fonction sensible : `PKP_REDACTION_ACTIVE` et `PKP_PDF_FRANCAIS_OUVERT` restent faux (A5, A6).
Elle complète [`INTEGRATION-DEV.md`](INTEGRATION-DEV.md) et [`../../scripts/recette/README.md`](../../scripts/recette/README.md),
qui font foi en cas d'écart.

## 1. Prérequis

| Élément | Vérification |
|---|---|
| Poste avec le dépôt à jour sur le SHA à recetter | `git fetch && git checkout <SHA>` ; `git rev-parse --short HEAD` |
| Node.js 24.15, version de la CI et de l'image web | `node --version` (`v24.15` ou plus récent en 24.x) |
| Playwright avec Chromium, sur le poste | `npm install -g playwright && npx playwright install chromium` ; `node -e "require('playwright')"` sans erreur |
| SDK Google Cloud, compte avec IAP et OS Login sur `mer-boussole-dev` | `gcloud auth list` ; rôles `roles/iap.tunnelResourceAccessor` et `roles/compute.osLogin` |
| Compte administrateur de l'instance DEV (TOTP compris) | Connexion manuelle à l'écran réussie |
| Version publiée | Run « DEV - publication des versions » réussi pour le SHA de fusion |

## 2. Relever la version déployée

Sur la VM (lecture seule) :

```bash
gcloud compute ssh boussole-dev --project mer-boussole-dev --zone europe-west9-a --tunnel-through-iap
sudo boussole-dev-sync --etat
```

Attendu : **version active = SHA de fusion à recetter**, aucune version rejetée, conteneurs `db`, `api` et `web`
démarrés. Noter le SHA actif et la révision Alembic (attendue au 26/11 : `0049`). Si la version active n'est pas
celle attendue, **arrêter la recette** et voir le § 6.

Relevé des données du Français (lecture seule, aucune donnée personnelle), depuis la VM, comme dans #212. `$DC` est
défini dans [`INTEGRATION-DEV.md`](INTEGRATION-DEV.md) § 1 :

```bash
$DC exec -T db psql -U pkp -d pkp \
  -c "SELECT code, actif, public FROM domaine_pedagogique WHERE code LIKE 'francais%';" \
  -c "SELECT d.code, v.numero, v.statut FROM dossier_francais d JOIN dossier_francais_version v ON v.dossier_id = d.id ORDER BY 1, 2;" \
  -c "SELECT count(*) AS classes_pilotes FROM classe_pilote;"
```

Attendu : `francais-college` actif et **non public** ; `FR3-DNB27-01` présent avec ses versions.

## 3. Ouvrir le tunnel

Sous Windows : `scripts/tester-ihm-gcp.ps1` (contrôles, puis tunnel sur le port local 8443 par défaut). Laisser la
fenêtre ouverte pendant toute la recette.

## 4. Lancer la recette

Depuis la racine du dépôt, **juste après** avoir lu le code TOTP (valable 30 secondes) :

```bash
BASE_URL=http://127.0.0.1:<port du tunnel> VERSION=<SHA actif> \
  ADMIN_EMAIL=<compte admin> ADMIN_MDP=<mot de passe> ADMIN_TOTP=<code à 6 chiffres> \
  SORTIE=recette-dev-$(date +%Y%m%d-%H%M) \
  node scripts/recette/recette-francais.mjs
```

- `BASE_URL` : l'adresse et le port affichés par le script du tunnel (voir `scripts/recette/README.md` § 2).
- **Mode lecture par défaut** : rien n'est validé ni ouvert. Les étapes élève passent en « N/A » tant qu'aucune
  version du dossier n'est **validée par un professeur et ouverte** à une classe pilote sur DEV.
- `MODE=complet` valide et ouvre un contenu : à n'utiliser sur DEV qu'avec votre accord explicite, la validation
  d'un contenu réel étant une décision pédagogique humaine.
- Les comptes et classes créés sont fictifs, préfixés `recette-<horodatage>`, rappelés dans le rapport.

Ne jamais coller le mot de passe ni le code TOTP dans un ticket, un rapport ou un message.

## 5. Scénarios et résultats attendus

| Rôle | Étape | Résultat attendu |
|---|---|---|
| Système | API joignable, version consignée | `/api/health` répond ; `VERSION` dans le rapport |
| Système | Dossier importé, domaine actif | Au moins un dossier ; `francais-college` actif |
| Administrateur | Connexion à l'écran, accès au Français depuis l'administration | Sans seconde connexion |
| Administrateur | Supports professeur et PDF élève | PDF élève **sans corrigé** |
| Administrateur | Validation (V2-D15) | Possible sur un contenu dont il n'est pas l'auteur ; N/A en mode lecture |
| Validateur | Lien depuis `/enseignant`, file de validation | Dossier soumis visible, boutons Valider / Refuser |
| Professeur 3e | Dossier, PDF professeur, ouverture à la classe | Ouverture N/A en mode lecture |
| Professeur hors périmètre (6e) | Liste et adresse directe | Aucun dossier ; 404 |
| Élève pilote | « Cours », quiz | Dossier lisible, **aucun corrigé avant réponse** ; N/A sans ouverture |
| Élève hors pilote | « Cours » et adresse directe | Rien ; 403 |
| Simulation | Élève fictif du professeur | Dossier ouvert visible ; aucune route adulte |
| Non-régression | Listes Maths et Anglais de l'administration | Inchangées |

## 6. Collecte des preuves

1. Joindre à #217 : `rapport.md`, `rapport.json` et le dossier de captures du répertoire `SORTIE`.
2. Indiquer dans le commentaire : SHA actif, révision Alembic, mode (lecture ou complet), date et heure.
3. Pour toute étape en échec : capture, message du rapport, réponse HTTP si elle figure dans le rapport.

## 7. Diagnostic en cas d'échec

| Symptôme | Cause probable | Vérification |
|---|---|---|
| Version active différente du SHA attendu | Déploiement non appliqué ou rejeté | `boussole-dev-sync --etat` (version rejetée ?) ; run de publication ; ne pas forcer de version sans décision |
| « API joignable » en échec | Tunnel fermé, mauvais port ou schéma, conteneur `api` arrêté | Fenêtre du tunnel ; `$DC ps` sur la VM |
| Connexion administrateur refusée | TOTP expiré, compte ou mot de passe | Relancer avec un nouveau code ; tester à l'écran |
| Aucun dossier importé | Import du déploiement absent ou en erreur | Ligne « Dossiers de français : … » dans la sortie de `boussole-dev-sync` ; requête du § 2 |
| Domaine inactif | Réglage de l'administration | Administration → Domaines : activer `francais-college` **sans** le rendre public |
| Professeur hors périmètre voit un dossier | Habilitation trop large | Habilitations du compte de recette ; **anomalie de sécurité** : ouvrir un ticket |
| Élève hors pilote voit un contenu | Contrôle SEC-D6 | **Anomalie de sécurité bloquante** : arrêter, ouvrir un ticket P0 |
| Corrigé visible côté élève | Protection ARCH-4 | **Anomalie bloquante** : capture, ticket P0 |
| Étapes élève « N/A » | Aucune version validée et ouverte | Normal en mode lecture ; validation par un professeur puis ouverture, ou `MODE=complet` sur accord |
| Non-régression Maths ou Anglais en échec | Régression commune | Comparer avec la dernière recette verte ; ticket dédié |

Après la recette, les comptes de recette fictifs peuvent rester désactivés ; ne supprimer aucune donnée sans
décision.
