# Analyse du projet `Photon53/boussole-maitrise-plus`

**Date de l'analyse :** 13 novembre 2026
**Commit analysé :** `78ecf3a` — *Merge pull request #28 from Photon53/develop* (10/11/2026)
**Branche :** `main` · dépôt **privé** (clone superficiel, 23 commits visibles)
**Méthode :** lecture du code et de la documentation, statistiques du dépôt, exécution des tests du moteur dans un environnement isolé.

---

## 1. Synthèse

**Verdict : projet techniquement très au-dessus de la moyenne**, avec une discipline d'ingénierie rare (documentation d'architecture qui correspond au code, audit exécutable avec preuves, configuration qui refuse de démarrer en production si elle est dangereuse).

Ce n'est **pas** un prototype : c'est une application complète et cohérente, avec un moteur pédagogique réel, 4 espaces utilisateurs, 31 migrations de base, 204 routes HTTP, 389 fonctions de test côté API, 105 tests de front et 139 cas de test pour le moteur.

Les vrais freins ne sont plus techniques :

| Frein | Nature | Gravité |
|---|---|---|
| Licence **UNLICENSE** (domaine public) | Juridique | 🔴 Bloquant pour vendre |
| **0 question validée** sur 1 775 | Produit / pédagogique | 🔴 Bloquant pour ouvrir aux élèves |
| Pas d'inscription ni de paiement | Commercial | 🟠 La V2 n'est pas commencée |
| Sauvegardes manuelles, pas de supervision | Exploitation | 🟠 |

**Note par dimension :**

| Dimension | Note | Commentaire |
|---|:--:|---|
| Architecture | 9/10 | 3 couches propres, moteur pur sans dépendance, sens des dépendances respecté |
| Sécurité | 8/10 | scrypt 128 Mo, HMAC versionné, TOTP, CSP stricte, garde-fous de production |
| Tests | 8/10 | 461 fonctions Python + 105 tests front ; pas de mesure de couverture |
| Documentation | 10/10 | Exceptionnelle, honnête, vérifiable (audit avec preuves brutes) |
| Contenu pédagogique | 6/10 | Volume impressionnant (1 775 questions) mais **zéro validation** |
| Exploitation | 6/10 | Docker/Caddy/Terraform propres, mais sauvegardes et supervision absentes |
| Maintenabilité | 6/10 | Fichiers très gros (860 lignes), pas d'outillage lint/format |
| Modèle économique | 2/10 | Licence inadaptée, paiement absent |

---

## 2. Fiche d'identité

| | |
|---|---|
| **Nom** | Boussole Maîtrise+ (anciennement « PKP Math Lycée ») |
| **Promesse** | Plateforme pédagogique adaptative, collège + lycée, maths (et anglais) |
| **Public** | Élèves (6e → Terminale), enseignants, parents, administrateurs |
| **Origine** | Migration de `Photon53/pkp-math-lycee` (commit source `9530db4`), identifiants internes « PKP » conservés |
| **Licence** | UNLICENSE (domaine public) — mentionnée comme « à examiner avant commercialisation » dans `MIGRATION.md` |
| **État** | V1 complète et déployée ; V2 commerciale cadrée (cahier des charges 708 lignes) mais non développée |

---

## 3. Architecture

```
web/ (React 18 + Vite)  ──HTTP/JSON──▶  api/ (FastAPI)  ──▶  PostgreSQL / SQLite
                                          │
                                          └──▶  engine/ (Python pur, aucune dépendance)
```

Le point structurel le plus fort : **le moteur ne connaît ni le web ni la base**. Il reçoit et renvoie des dataclasses ; `api/app/db/conversions.py` fait la traduction. Conséquence directe : 139 tests unitaires ultra-rapides (1,4 s) sur les règles pédagogiques, sans base ni HTTP.

| Couche | Techno | Volume |
|---|---|---|
| `engine/` | Python pur (dataclasses) | 18 fichiers · 1 174 lignes |
| `api/` | FastAPI, SQLAlchemy 2, Alembic, Pydantic v2 | 53 fichiers · 10 064 lignes (+ 33 fichiers de tests, 4 218 lignes) |
| `web/` | React 18, Vite, sans routeur ni store | 78 fichiers · 14 064 lignes |
| `contenu/` | YAML (chapitres, compétences, questions, cours) | 154 fichiers · 37 174 lignes |
| `deploy/` | Docker Compose, Caddy, PostgreSQL 16 | 13 fichiers |

### Décisions d'architecture notables

- **8 tables normalisées + `lecon`** ; une question n'est **jamais supprimée** (colonne `archivee`) — l'historique reste lisible.
- **Une seule question en cours par séance** côté serveur : pas de « joker », la durée est mesurée par le serveur, pas déclarée par le navigateur.
- **Maîtrise calculée**, pas stockée : moyenne pondérée des 10 dernières réponses (poids 1, puis ×0,9), a priori « 0 » de poids 1, seuil à 0,8.
- **Séparation maths / anglais** assumée : tables distinctes, pas de fusion ; une vue commune par « domaine » (matière × cycle) a été ajoutée en V2 (migration 0024).
- **Domaines pédagogiques** : 6 domaines déclarés, 2 publics (maths lycée, anglais collège), les autres inactifs.

---

## 4. Inventaire fonctionnel

| Espace | Route | Contenu |
|---|---|---|
| Élève maths | `/eleve` | Connexion prénom + code classe + code personnel (6 car.), séances sur chapitres choisis, correction, jauge de maîtrise, historique |
| Élève anglais | `/anglais/eleve` | Séances chronométrées, supports audio/PDF, QCM |
| Enseignant | `/enseignant` | Classes, codes, chapitres ouverts, tableau de bord, progression, questions, archivage, RGPD |
| Parent | `/parent` | Suivi de plusieurs enfants, activité 14 jours, historique, changement de code |
| Admin | `/admin` | Comptes, habilitations par domaine, contenu, versioning des leçons, journal d'audit, statistiques, répertoire |
| Public | `/` et `/methode` | Accueil, présentation de la « Méthode Spirale » |

**204 routes HTTP** réparties sur **18 modules** de routage.

### La banque de contenu

| Indicateur | Valeur |
|---|---|
| Chapitres | **154** |
| Compétences | **327** |
| Questions actives | **1 775** |
| Questions **validées** pédagogiquement | **0** |
| Niveaux couverts | 6e, 5e, 4e, 3e, 2nde, 1re, Terminale (+ anglais 4e/3e) |
| Référentiels sources | 9 dossiers (`referentiels/`), programmes 2026, 2020, 2019 |

Chaque question porte un **registre des sources** (source, URL, licence, adaptation), un statut de validation, et un contrôle de cohérence exécuté en CI (`python -m app.contenu verifier`).

---

## 5. Qualité d'ingénierie — ce qui est remarquable

### 5.1 Sécurité

| Mesure | Implémentation |
|---|---|
| Hachage des mots de passe | scrypt **N = 2¹⁷, r = 8, p = 1** (recommandation OWASP, 128 Mo), paramètres stockés dans l'empreinte, **re-hachage automatique** si les paramètres ont augmenté |
| Limitation de charge | `BoundedSemaphore(2)` : au plus 2 hachages simultanés (~256 Mo), sinon 40 connexions parallèles satureraient 5 Go |
| Jetons | HMAC-SHA256 maison, charge `role:id:expiration:version`, comparaison à **temps constant** |
| Révocation | La `version` du jeton est un hash du secret courant : changer un mot de passe ou régénérer un code **invalide tous les jetons émis** |
| Second facteur | TOTP RFC 6238 (SHA-1, 6 chiffres, 30 s, ±1 pas) obligatoire pour l'admin en production |
| Codes élèves | 31⁶ ≈ 887 M de combinaisons, alphabet sans caractères ambigus, hachés, comparaison constante |
| En-têtes | CSP `default-src 'self'`, HSTS 1 an, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, Permissions-Policy |
| Garde-fou de production | L'API **refuse de démarrer** si `PKP_SECRET_KEY` est faible, si la base est SQLite, si CORS contient `localhost` ou `*`, ou si le mode « questions non validées » n'est pas choisi explicitement |
| Injection | Aucun `eval`, aucun `exec`, aucun `subprocess`, aucune requête SQL brute (SQLAlchemy) |
| Analyse d'expressions | Parseur `ast` avec **liste blanche de nœuds**, saisie limitée à 200 caractères, jamais d'exception renvoyée à l'élève |
| Docker | Utilisateur non-root (uid 10001), API sans port publié (seul Caddy la joint) |

Le contrôle `docs/audit/` est un dispositif rare : chaque contrôle est écrit **avant** exécution avec ses critères de réussite/échec, puis complété par la sortie brute de l'outil (`bandit`, `semgrep`, `pip-audit`, `npm audit`, `gitleaks`) dans `preuves/`. L'audit a trouvé et fait corriger 1 Critique et 3 Élevés (A-07 usurpation d'élève → décision D1, code personnel ; A-09 jetons non révoqués → version de jeton).

### 5.2 Tests et CI

| Suite | Contenu | Exécution ici |
|---|---|---|
| Moteur | 72 fonctions de test, **139 cas** après paramétrage (correction, maîtrise, sélection, gabarits, anglais) | ✅ **139 passed en 1,44 s** |
| API | **389 fonctions de test** (élève, enseignant, admin, RGPD, migrations, anglais) | ⚠️ non exécutable dans ce bac à sable (voir § 7) |
| Front | **105 tests** (Vitest + Testing Library) | ⚠️ non exécuté (dépendances npm non installées) |

**CI GitHub Actions** (`.github/workflows/ci.yml`) sur chaque push/PR : vérification du contenu YAML → tests moteur → tests API → `npm audit --omit=dev --audit-level=high` → `npm test` → `npm run build`. Le build de l'image web exécute aussi `npm test` : **une image ne peut pas être construite avec des tests rouges**.

### 5.3 Documentation

25 fichiers Markdown, ~3 750 lignes, dont :

- `ARCHITECTURE.md` — décisions, schéma, règles du moteur, limites connues (« Non fait : révocation individuelle des jetons »)
- `RGPD.md` — checklist pour mineurs, avec ce que fait le logiciel vs ce qui reste à l'établissement
- `DEPLOIEMENT.md` — installation, exploitation, **limites connues** assumées
- `CAHIER-DES-CHARGES-V2.md` — 708 lignes, état des lieux **vérifié dans le code**, lots, recette
- `docs/audit/` — protocole + preuves brutes
- `docs/exploitation/` — fiches par rôle (professeur, administrateur, technique, maintenance)

La documentation dit aussi ce qui **n'est pas** fait. C'est le signe d'un projet sérieux.

---

## 6. Faiblesses et risques

### 🔴 6.1 Licence inadaptée à la commercialisation

`LICENSE` est une **UNLICENSE** : « anyone is free to copy, modify, publish, use, compile, **sell** or distribute this software ». Le code est dans le domaine public.

`MIGRATION.md` le signale lui-même : *« La licence UNLICENSE préexistante du dépôt cible est conservée et doit être examinée avant commercialisation. »*

Conséquence : tant que ce n'est pas tranché, **n'importe qui peut revendre le produit**. C'est le point le plus urgent du projet, et il n'est pas technique.

### 🔴 6.2 Contenu pédagogique non validé

L'inventaire généré indique : **1 775 questions actives, 0 validée, 1 775 à valider**. Le circuit de validation existe côté anglais (soumettre → valider, un référent ne valide jamais ses propres séances), mais le circuit maths est embryonnaire : le statut se change « d'un clic, sans soumission ni commentaire de relecture » (constat du CDC V2).

Or `PKP_SERVIR_QUESTIONS_NON_VALIDEES` vaut **`true` par défaut** : en l'état, un élève peut recevoir des questions jamais relues. Une erreur d'énoncé ou de corrigé en maths se voit immédiatement et coûte la crédibilité du produit.

### 🟠 6.3 Pas de monétisation

Aucune inscription publique, aucun paiement, aucun e-mail transactionnel. Le CDC V2 prévoit Stripe, une table `offre`, des plafonds par offre, et pose encore des décisions ouvertes (D1 client cible, D9 contenu de l'offre gratuite, D12 périmètre français). Rien n'est codé.

### 🟠 6.4 Exploitation non industrialisée

| Sujet | État |
|---|---|
| Sauvegardes | **Manuelles** (`pg_dump` documenté), aucun cron, aucun test de restauration |
| Supervision | Aucune alerte (erreurs, disque, certificat, latence) |
| Instances | 1 seul worker API : la limitation de connexions est **en mémoire**, un redémarrage remet les compteurs à zéro |
| Domaine | Provisoire (`<ip>.sslip.io`) |

### 🟠 6.5 SSRF via la vérification des liens

`api/app/ressources.py::lien_repond()` fait un `urllib.request.urlopen()` sur une URL fournie par un enseignant. La protection actuelle est une **liste de domaines interdits en base** (`DomaineInterdit`) et le schéma `https://`.

Il manque : résolution DNS puis refus des plages privées/loopback/link-local (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16` — dont le **métadonnée cloud** `169.254.169.254`), et désactivation des redirections. Le risque est réel sur une VM cloud.

### 🟡 6.6 Monolithe qui grossit

| Fichier | Lignes |
|---|--:|
| `api/app/routes/admin.py` | 860 |
| `api/app/contenu.py` | 657 |
| `api/app/schemas.py` | 598 |
| `api/app/db/models.py` | 594 |
| `web/src/admin/Repertoire.jsx` | 615 |
| `web/src/enseignant/Classes.jsx` | 614 |

204 routes dans 19 modules, sans séparation par domaine métier. C'est encore gérable, mais le rythme d'ajout (V2 à venir) va accélérer la dette.

### 🟡 6.7 Outillage qualité absent

- Pas de **linter ni de formateur** configuré (ni `ruff`/`black`, ni `eslint`/`prettier`) : la cohérence de style est maintenue à la main.
- Pas de **pre-commit**.
- Pas de **mesure de couverture** (`pytest-cov` absent), donc pas de seuil de non-régression.
- Pas de **Dependabot/Renovate** : les mises à jour de dépendances sont manuelles (seul `npm audit` bloquant existe côté front).

### 🟡 6.8 Dette de nommage

Le produit s'appelle « Boussole Maîtrise+ », mais le code, les tables, les variables d'environnement et une partie des docs restent « PKP » (`pkp_engine`, `PKP_*`, `/pkp/…`). Assumé dans `MIGRATION.md` (« identifiants internes conservés pour compatibilité »), mais coûteux à corriger plus tard.

### 🟡 6.9 Point d'attention sécurité opérationnelle (cette session)

Pour me connecter à GitHub, le jeton `gh` a dû être stocké **en clair** dans `.gh-config/hosts.yml` du workspace (le stockage chiffré Windows et `%APPDATA%` sont inaccessibles au bac à sable). Ce jeton `gho_…` donne accès à tes dépôts. **Révoque-le** quand tu n'en as plus besoin : <https://github.com/settings/applications>.

---

## 7. Vérifications exécutées

| Vérification | Résultat |
|---|---|
| Clone du dépôt privé | ✅ 615 fichiers suivis par Git, 15,1 Mo |
| Tests du moteur (`pytest engine/tests`) | ✅ **139 passed en 1,44 s** |
| Tests de l'API | ⚠️ **non exécutés** — le bac à sable Windows refuse l'accès aux dossiers temporaires créés par pytest (`PermissionError WinError 5` sur `%TEMP%\…\pytest-of-…` et sur un `--basetemp` interne). Diagnostic ACL exécuté : verdict `NOT_THIS_CLASS`, aucune réparation applicable. Ce n'est **pas** un défaut du projet. |
| Tests du front | ⚠️ non exécutés (installation npm non tentée) |
| Recherche `eval` / `exec` / `subprocess` | ✅ aucun résultat |
| Recherche `TODO` / `FIXME` | ✅ aucun (hors donnée de test) |
| Recherche `console.log` | ✅ aucun |

Pour lancer les tests toi-même sur ta machine (hors bac à sable) :

```powershell
cd api; python -m venv .venv; .venv\Scripts\activate
pip install -e ..\engine -e ".[dev]"
pytest -q
```

---

## 8. Recommandations priorisées

### P0 — avant toute mise en service commerciale

1. **Trancher la licence.** Remplacer l'UNLICENSE par une licence propriétaire (ou AGPL + licence commerciale double). C'est un préalable juridique : sans cela, le produit n'est pas vendable.
2. **Valider le contenu.** 1 775 questions à relire est le vrai goulot d'étranglement. Prioriser les chapitres des niveaux ouverts à la vente, créer le rôle validateur côté maths (comme pour l'anglais), et **passer `PKP_SERVIR_QUESTIONS_NON_VALIDEES=false`** chapitre par chapitre dès qu'il est relu.
3. **Décider le périmètre commercial minimal** (D1/D9 du CDC) avant d'écrire une ligne de paiement.

### P1 — fiabiliser l'exploitation (2 à 4 semaines)

4. **Sauvegardes automatiques** chiffrées, hors serveur, avec **test de restauration trimestriel** documenté.
5. **Supervision** : uptime, taux d'erreur 5xx, espace disque, expiration du certificat. Un simple Prometheus/Node exporter + alerte mail suffit.
6. **Corriger le SSRF** dans `ressources.py` : résoudre le nom, refuser les IP privées/link-local, ne pas suivre les redirections.
7. **Outillage qualité** : `ruff` + `eslint` + `prettier` + `pre-commit`, `pytest-cov` avec un seuil de non-régression (le moteur doit rester à 100 %), et **Dependabot** sur pip et npm.
8. **Révoquer le jeton GitHub** utilisé pour cette analyse.

### P2 — industrialiser (à mesure que la V2 avance)

9. **Découper `routes/admin.py`** (860 lignes) par sous-domaine (comptes, contenu, répertoire, journal) avant d'ajouter les lots V2.
10. **Extraire la logique des gros composants React** (`Repertoire.jsx`, `Classes.jsx`) en hooks + composants de présentation.
11. **Limitation de connexions partagée** (Redis) avant toute montée à plusieurs instances ou workers.
12. **Tests de bout en bout** (Playwright) sur les 3 parcours critiques : connexion élève → séance → bilan ; création de classe → codes ; espace parent.
13. **Révocation individuelle des jetons** si le besoin de sécurité augmente (table `session` plutôt que version par secret).

---

## 9. Ce que je retiens

Ce dépôt raconte l'histoire d'un projet mené avec un soin inhabituel : les décisions sont écrites, les limites sont assumées, les contrôles de sécurité sont exécutés **et** prouvés, et le code fait ce que la documentation dit.

Le risque n'est donc pas là où on l'attendrait. Il n'est pas dans la qualité du logiciel, il est dans **trois décisions qui ne sont pas encore prises** : la licence, la validation du contenu, et le modèle commercial. Tant qu'elles restent ouvertes, le projet est une excellente plateforme pédagogique qui ne peut pas encore devenir un produit.

Le meilleur investissement à court terme n'est pas une ligne de code : c'est **la relecture des 1 775 questions** et **un avocat sur la licence**.

---

*Rapport produit par analyse statique du dépôt cloné le 13/11/2026. Aucune modification n'a été apportée au dépôt : le clone est intact, la remote `origin` pointe sur l'URL HTTPS propre.*

---

## Signature

**Analyse produite par DeepSeek** (DeepSeek Harness) le 13/11/2026.

| | |
|---|---|
| Dépôt analysé | `Photon53/boussole-maitrise-plus` |
| Commit | `78ecf3a` (branche `main`, 10/11/2026) |
| Empreinte SHA-256 du rapport d'origine | `101e5ee5063fae817357d03b3acaaeec4a8754f1c53c0ff3daab5262b60ff2b3` |
| Suivi | issue #80 — constats #77, #78, #79, #3 |