# Déploiement — PKP Math Lycée

```
Internet ──443──▶ Caddy (web) ──▶ /api/* ──▶ API FastAPI ──▶ PostgreSQL
                     │                         ▲
                     └── fichiers du front     └── purge RGPD (quotidienne)
```

Seul Caddy est exposé. Il obtient seul le certificat HTTPS (Let's Encrypt).

Une fois le site installé : fiches d'exploitation et de maintenance dans [exploitation/](exploitation/README.md).

## Prérequis

- Un serveur Linux (2 Go de RAM suffisent) hébergé dans l'UE, avec Docker et Docker Compose.
  Chaque connexion enseignant calcule un hachage scrypt de 128 Mo (mesuré : environ 4 s sur un PC de développement
  chargé) : c'est voulu (résistance aux attaques par force brute). Au plus 2 hachages tournent en même temps
  (≈ 256 Mo), pour qu'une rafale de connexions ne sature pas la mémoire.
- Un nom de domaine dont l'enregistrement DNS pointe vers ce serveur.
- Ports 80 et 443 ouverts (le 80 sert à la validation du certificat).

## Première installation

```bash
cd deploy
cp .env.example .env
python3 -c "import secrets; print(secrets.token_urlsafe(48))"   # → PKP_SECRET_KEY
python3 -c "import secrets; print(secrets.token_urlsafe(24))"   # → PKP_DB_MOT_DE_PASSE
nano .env                                                        # domaine + les deux secrets
docker compose up -d --build
docker compose exec api python -m app.admin creer --email prof@lycee.fr --nom "Mme Martin"
```

Vérifier : `https://<domaine>/api/health` répond `{"status":"ok"}`, puis se connecter sur
`https://<domaine>/enseignant`.

Les migrations de base de données sont appliquées automatiquement à chaque démarrage de l'API.
Les données de démo ne sont **jamais** chargées en production.

## Oracle Cloud (Oracle Linux) : script d'installation

`deploy/installer-oracle.sh` fait toute l'installation sur une VM Oracle Linux 9 ou 10 : fichier d'échange si
la mémoire est faible, Docker, ouverture de firewalld (80, 443), clonage du dépôt, `.env` avec secrets générés,
démarrage, attente du certificat HTTPS. Il est relançable pour mettre à jour : les secrets et la base sont conservés.

1. Console Oracle : dans la « Security List » du sous-réseau de la VM, ajouter des règles entrantes
   TCP 80 et TCP 443 depuis `0.0.0.0/0` (le port 22 y est déjà).
2. Depuis le PC, copier le script sur la VM :
   `scp -i ~/.ssh/oracle.key deploy/installer-oracle.sh opc@<IP>:`
3. Sur la VM (`ssh -i ~/.ssh/oracle.key opc@<IP>`) :
   `bash installer-oracle.sh --email prof@lycee.fr --nom "Mme Martin"`
   (ajouter `--domaine maths.mon-lycee.fr` si un domaine pointe déjà vers la VM ; sinon une adresse
   `<ip>.sslip.io`, provisoire, est utilisée).

Docker y est lancé avec `sudo` ; après une reconnexion SSH, l'utilisateur `opc` peut s'en passer.

## Passer une installation V1 à la V2

Deux scripts, un par hébergeur, à copier sur la VM puis à lancer dans une session SSH interactive :
`deploy/mettre-a-jour-v2-oracle.sh` (Oracle Linux) et `deploy/mettre-a-jour-v2-gcp.sh` (Ubuntu ou Debian).
Ils sauvegardent la base et `.env` dans `~/sauvegardes`, mettent à jour le code, reconstruisent, vérifient la
migration 0008 et HTTPS, puis créent ou promeuvent l'administrateur et affichent son second facteur.

```bash
# Prérequis : la V2 est poussée sur GitHub (branche main).
scp deploy/mettre-a-jour-v2-oracle.sh opc@<IP>:            # ou : gcloud compute scp deploy/mettre-a-jour-v2-gcp.sh <vm>:
bash mettre-a-jour-v2-oracle.sh --admin-email moi@lycee.fr   # compte V1 existant → administrateur
bash mettre-a-jour-v2-oracle.sh --retour                     # revenir à la V1 (supprime les données propres à la V2)
```

Classes, élèves et réponses sont conservés. L'espace élève passe de `/` à `/eleve` : prévenir les professeurs.

## Exploitation courante

| Besoin | Commande (depuis `deploy/`) |
|--------|-----------------------------|
| Mettre à jour | `git pull && docker compose up -d --build` |
| Journaux | `docker compose logs -f api web` |
| Purge : voir ce qui serait supprimé | `docker compose exec api python -m app.purge --simulation` |
| Nouveau compte enseignant | `docker compose exec api python -m app.admin creer --email … --nom …` |
| Mot de passe oublié | `docker compose exec api python -m app.admin mot-de-passe --email …` |
| Sauvegarde | `sudo boussole-sauvegarde --sauvegarder --motif manuelle` : base, PDF et `.env`, chiffrés et copiés hors VM ; automatique chaque nuit (installation : [technique.md, T-04](exploitation/technique.md#t-04--sauvegarder)) |
| Restauration | contrôle sans risque : `--restaurer-isole` ; restauration réelle : [technique.md, T-05](exploitation/technique.md#t-05--restaurer-une-sauvegarde) |
| Premier administrateur | `docker compose exec api python -m app.admin creer --email … --nom "Équipe PKP" --admin`, puis `docker compose exec api python -m app.admin totp --email …` (second facteur obligatoire en production) |
| Contrôle des liens | Automatique chaque semaine (service `purge`) ; à la demande : `docker compose exec api python -m app.ressources verifier-liens` |

### Disque plein

Chaque mise à jour reconstruit les images Docker : sans nettoyage, le disque de la VM se remplit
(images et cache de compilation, journaux, anciennes sauvegardes de la base). Sur la VM :

```bash
bash deploy/nettoyer-disque.sh --simulation   # ce qui occupe le disque, sans rien supprimer
bash deploy/nettoyer-disque.sh                # nettoie ; demande confirmation avant les sauvegardes
```

Le script garde les 3 sauvegardes de base les plus récentes (`--garder-sauvegardes <n>`) et toutes les copies
de `.env`. Il ne supprime jamais les volumes Docker (base, PDF, certificats). Si Docker ou PKP se sont arrêtés
faute de place, il les relance. S'il reste moins de 3 Go libres, il indique comment agrandir le disque.

Sauvegardes : chiffrées, copiées hors du serveur, gardées 60 jours, restauration de contrôle chaque trimestre
([technique.md, T-04 et T-05](exploitation/technique.md#t-04--sauvegarder), ticket #8).

## Limites connues

- **Changement de mot de passe** (`python -m app.admin mot-de-passe`) : déconnecte l'enseignant de tous ses appareils.
- **Codes personnels des élèves** : après la migration 0005, les élèves déjà inscrits n'ont pas de code et ne peuvent
  pas se connecter. Chaque enseignant ouvre sa classe, clique « Générer les codes manquants », imprime la fiche et
  la distribue. Les codes ne sont affichés qu'une fois : un code perdu se remplace par « Nouveau code ».
- **Chapitres ouverts** : la migration 0007 ouvre, pour chaque classe existante, tous les chapitres de son programme
  présents à ce moment-là. Les chapitres ajoutés ensuite à `contenu/` restent fermés tant que l'enseignant ne les
  coche pas (onglet Classes → « Chapitres proposés »).
- **Un seul processus API** : la limitation des tentatives de connexion est en mémoire. Pour
  plusieurs serveurs ou workers, il faudrait un stockage partagé (Redis). Un redémarrage remet
  les compteurs à zéro.
- **Blocage d'un compte enseignant** : 5 mots de passe faux en 15 min bloquent ce compte
  15 min, même pour son propriétaire. C'est voulu, mais un tiers peut le provoquer.
- **Lycée derrière une seule IP** : les plafonds par IP (300 connexions, 30 codes classe faux et
  60 échecs de connexion élève par 15 min, SEC-D5) sont réglés pour une classe entière ; voir `PKP_CONNEXION_*`
  dans `app/config.py`. Plusieurs classes qui se connectent en même temps derrière la même adresse peuvent
  approcher le plafond de 60 échecs : l'augmenter avec `PKP_CONNEXION_ELEVE_MAX_ECHECS_PAR_IP` dans `.env` si besoin.
- **PDF des ressources de français** (#180) : fermés pendant le pilote (liens seulement). Ils s'ouvriront après le renforcement du contrôle des PDF (#4), par `PKP_PDF_FRANCAIS_OUVERT=true` dans `.env` ; ne pas l'activer avant.
