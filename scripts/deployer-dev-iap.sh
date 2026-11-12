#!/usr/bin/env bash
# Boussole Maîtrise+ — installation complète de l'environnement DEV privé (IAP), depuis Cloud Shell.
#
# Usage (dans Cloud Shell) :
#   bash deployer-dev-iap.sh
#   bash deployer-dev-iap.sh --admin-email moi@exemple.fr --admin-nom "Équipe DEV"
#   bash deployer-dev-iap.sh --installer-synchro    # installe ou met à jour boussole-dev-sync (ticket #65, PR 3b)
#
# Ce que fait le script, dans l'ordre, en s'arrêtant à la première erreur :
#   1. Contrôles : outils, compte gcloud, VM RUNNING, pas d'IP externe, SSH IAP, sudo.
#   2. Code : copie dédiée de origin/develop (~/.boussole-deploiement), commit comparé à GitHub, git bundle.
#   3. Transfert du bundle vers la VM par IAP (la VM n'a aucun accès à GitHub).
#   4. Sur la VM : /opt/boussole-dev = develop (commit vérifié), swap, secrets (.env), Compose en mode
#      privé (HTTP sur 127.0.0.1:8080 uniquement, pas de 80/443 publics), build, démarrage, contrôles.
#   5. Optionnel : compte administrateur (mot de passe aléatoire + second facteur TOTP).
#   6. Validation de bout en bout : tunnel IAP depuis Cloud Shell, /api/health et page d'accueil.
#
# Relançable sans risque : .env (secrets) et la base sont conservés, un admin existant n'est pas modifié.
# Aucun terraform apply, aucune modification d'infrastructure.
#
# À SAVOIR AVANT DE LANCER :
#   - Si la VM est arrêtée (TERMINATED, STOPPED, SUSPENDED), le script la DÉMARRE : elle est facturée tant
#     qu'elle tourne (gcloud compute instances stop … pour l'arrêter ensuite).
#   - Avec --admin-email, à la création du compte, le mot de passe et l'URI TOTP sont AFFICHÉS dans le terminal
#     et copiés dans /root/boussole-admin-initial.txt sur la VM (mode 600). Ne jamais les coller dans un ticket,
#     une PR ou un journal ; effacer l'écran et supprimer ce fichier après les avoir mis en lieu sûr.
#   - La clé d'hôte SSH de GitHub est vérifiée (empreinte officielle et API GitHub) avant toute connexion.
#   - Mode normal : reconstruit les images sur la VM. Il est REFUSÉ sur la VM dès que la synchronisation
#     automatique est installée (/etc/boussole-dev-sync/installe) : il écraserait la version déployée par digest.
#   - --installer-synchro : met à jour le code, installe boussole-dev-sync, le Compose DEV, les unités systemd
#     (timer NON activé) et la rotation du journal ; adopte le déploiement manuel s'il n'est pas déjà repris ;
#     lance une simulation. AUCUN conteneur n'est arrêté ni reconstruit. Voir
#     docs/exploitation/pipeline-dev-pr3b-deploiement.md pour la première bascule et l'activation du timer.
set -Eeuo pipefail

PROJECT="mer-boussole-dev"
ZONE="europe-west9-a"
VM="boussole-dev"
# Accès SSH (clé déjà configurée dans Cloud Shell) ; surcharge possible : REPO_URL=... bash deployer-dev-iap.sh
REPO_URL="${REPO_URL:-git@github.com:Photon53/boussole-maitrise-plus.git}"
CLE_GH="${CLE_GH:-$HOME/.ssh/id_ed25519}"   # clé SSH GitHub de Cloud Shell
AGENT_LANCE=""
# Empreinte officielle de la clé d'hôte SSH ed25519 de GitHub :
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
GH_ED25519_SHA256="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
DOSSIER_VM=""         # répertoire temporaire privé sur la VM (mktemp -d), supprimé en fin d'exécution
BRANCH="develop"
TRAVAIL="$HOME/.boussole-deploiement"
PORT_VM=8080          # port de l'application sur la VM (lié à 127.0.0.1)
PORT_TEST=18080       # port local Cloud Shell pour le test du tunnel
ADMIN_EMAIL=""
ADMIN_NOM="Administrateur DEV"
MODE="manuel"         # manuel | synchro

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-email) ADMIN_EMAIL="$2"; shift 2 ;;
    --admin-nom)   ADMIN_NOM="$2"; shift 2 ;;
    --installer-synchro) MODE="synchro"; shift ;;
    -h|--help)     usage ;;
    *) echo "Option inconnue : $1"; usage 1 ;;
  esac
done

[[ "$MODE" == manuel || -z "$ADMIN_EMAIL" ]] || { echo "--admin-email est incompatible avec --installer-synchro"; exit 1; }

REPORT=()
TUNNEL_PID=""
etape() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m[OK]\033[0m %s\n' "$*"; REPORT+=("OK        $*"); }
warn()  { printf '  \033[33m[ATTENTION]\033[0m %s\n' "$*"; REPORT+=("ATTENTION $*"); }
echec() { printf '  \033[31m[ECHEC]\033[0m %s\n' "$*"; REPORT+=("ECHEC     $*"); exit 1; }
fin() {
  local code=$?
  fermer_tunnel
  if [[ -n "$DOSSIER_VM" ]]; then gssh --command "rm -rf -- '$DOSSIER_VM'" >/dev/null 2>&1 || true; fi
  if [[ -n "$AGENT_LANCE" ]]; then kill "$AGENT_LANCE" 2>/dev/null || true; fi
  printf '\n====== RAPPORT BOUSSOLE DEV (IAP) ======\n'
  printf '%s\n' "${REPORT[@]}"
  if [[ $code -eq 0 ]]; then printf 'RESULTAT : SUCCES\n'; else printf 'RESULTAT : ECHEC (code %s)\n' "$code"; fi
  printf '========================================\n'
}
trap fin EXIT

GC=(--project "$PROJECT" --zone "$ZONE")
gssh() { gcloud compute ssh "$VM" "${GC[@]}" --tunnel-through-iap --quiet "$@"; }
# Le tunnel est lancé dans son propre groupe de processus (setsid) : on ferme ce groupe et rien d'autre.
fermer_tunnel() {
  [[ -n "$TUNNEL_PID" ]] || return 0
  kill -- "-$TUNNEL_PID" 2>/dev/null || kill "$TUNNEL_PID" 2>/dev/null || true
  wait "$TUNNEL_PID" 2>/dev/null || true
  TUNNEL_PID=""
}
# Clé d'hôte GitHub : acceptée seulement si son empreinte est l'empreinte officielle et si la clé est celle
# publiée par l'API GitHub (HTTPS). Une entrée existante dans known_hosts est vérifiée de la même façon.
verifier_cle_github() {
  local cle empreinte meta
  cle="$(ssh-keyscan -t ed25519 github.com 2>/dev/null | awk '$2 == "ssh-ed25519" {print $2" "$3; exit}')"
  [[ -n "$cle" ]] || echec "ssh-keyscan github.com n'a renvoyé aucune clé ed25519"
  empreinte="$(ssh-keygen -lf - <<<"github.com $cle" | grep -oE 'SHA256:[A-Za-z0-9+/]+' | head -1)"
  [[ "$empreinte" == "$GH_ED25519_SHA256" ]] \
    || echec "Clé d'hôte GitHub inattendue ($empreinte, attendu $GH_ED25519_SHA256) : connexion refusée"
  if meta="$(curl -fsS --max-time 15 https://api.github.com/meta 2>/dev/null)"; then
    python3 -c 'import json,sys; sys.exit(0 if sys.argv[1] in json.load(sys.stdin).get("ssh_keys", []) else 1)' "$cle" <<<"$meta" \
      || echec "La clé d'hôte GitHub ne figure pas dans https://api.github.com/meta : connexion refusée"
    ok "Clé d'hôte GitHub conforme (empreinte officielle et API GitHub)"
  else
    warn "API GitHub injoignable : clé d'hôte vérifiée par l'empreinte officielle seule"
  fi
  # Entrées ed25519 déjà connues pour github.com : toutes doivent être la clé officielle, sinon arrêt.
  local connues
  connues="$(ssh-keygen -F github.com -l 2>/dev/null | grep -i 'ed25519' | grep -oE 'SHA256:[A-Za-z0-9+/]+' || true)"
  if [[ -n "$connues" ]]; then
    ! grep -qvxF "$GH_ED25519_SHA256" <<<"$connues" \
      || echec "known_hosts contient pour github.com une clé ed25519 différente de la clé officielle : vérifier ~/.ssh/known_hosts"
    ok "Clé d'hôte GitHub déjà connue et conforme"
  else
    printf 'github.com %s\n' "$cle" >> "$HOME/.ssh/known_hosts"
    ok "Clé d'hôte GitHub ajoutée à known_hosts"
  fi
}

# ---------------------------------------------------------------------------------------------
etape "1. Contrôles préalables"
for outil in gcloud git curl; do command -v "$outil" >/dev/null || echec "Commande absente : $outil"; done
COMPTE="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
[[ -n "$COMPTE" ]] || echec "Aucun compte gcloud actif (gcloud auth login)"
ok "Compte gcloud actif"
gcloud projects describe "$PROJECT" --format='value(projectId)' >/dev/null 2>&1 || echec "Projet $PROJECT inaccessible"
ok "Projet $PROJECT accessible"

ETAT="$(gcloud compute instances describe "$VM" "${GC[@]}" --format='value(status)' 2>/dev/null || true)"
case "$ETAT" in
  RUNNING) ok "VM $VM : RUNNING" ;;
  TERMINATED|STOPPED|SUSPENDED)
    warn "VM $VM : $ETAT -> démarrage"
    gcloud compute instances start "$VM" "${GC[@]}" --quiet
    ok "VM $VM démarrée" ;;
  "") echec "VM $VM introuvable dans $ZONE" ;;
  *) echec "VM $VM dans un état inattendu : $ETAT" ;;
esac

IP_EXT="$(gcloud compute instances describe "$VM" "${GC[@]}" --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
if [[ -z "$IP_EXT" ]]; then ok "Aucune IP externe (accès privé uniquement)"; else warn "IP externe présente : $IP_EXT (non utilisée par ce script)"; fi

for essai in 1 2 3 4 5 6; do
  if gssh --command 'true' >/dev/null 2>&1; then break; fi
  [[ $essai -lt 6 ]] || echec "SSH via IAP impossible (droits IAP / OS Login, règle pare-feu 35.235.240.0/20:22)"
  sleep 10
done
ok "SSH via IAP"
gssh --command 'sudo -n true' >/dev/null 2>&1 || echec "sudo refusé sur la VM : rôle roles/compute.osAdminLogin requis"
ok "sudo disponible (OS Login admin)"

# ---------------------------------------------------------------------------------------------
etape "2. Code de la branche $BRANCH"
mkdir -p "$TRAVAIL" && chmod 700 "$TRAVAIL"
DEPOT="$TRAVAIL/depot"
if [[ "$REPO_URL" == git@* ]]; then
  # Ajoute la clé d'hôte GitHub si absente (sinon git demande une confirmation interactive).
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  verifier_cle_github
  # Seule la clé ed25519 vérifiée ci-dessus est acceptée (pas d'autre type de clé connu pour github.com).
  export GIT_SSH_COMMAND="ssh -o HostKeyAlgorithms=ssh-ed25519 -o StrictHostKeyChecking=yes"
  # Clé protégée par passphrase : chargée une seule fois dans un ssh-agent pour toute la durée du script.
  [[ -f "$CLE_GH" && -f "$CLE_GH.pub" ]] || echec "Clé SSH GitHub introuvable : $CLE_GH (variable CLE_GH)"
  etat_agent=0; ssh-add -l >/dev/null 2>&1 || etat_agent=$?
  if (( etat_agent == 2 )); then
    eval "$(ssh-agent -s)" >/dev/null
    AGENT_LANCE="$SSH_AGENT_PID"
  fi
  empreinte="$(ssh-keygen -lf "$CLE_GH.pub" | awk '{print $2}')"
  if ! ssh-add -l 2>/dev/null | grep -qF "$empreinte"; then
    echo "  Passphrase de la clé GitHub demandée une seule fois :"
    ssh-add "$CLE_GH" || echec "Clé GitHub non chargée (passphrase incorrecte ?)"
  fi
  ok "Clé GitHub chargée dans ssh-agent"
  # ssh -T git@github.com sort toujours en code 1, même authentifié : on lit le message.
  reponse_gh="$($GIT_SSH_COMMAND -T -o BatchMode=yes -o ConnectTimeout=15 git@github.com 2>&1 || true)"
  [[ "$reponse_gh" == *"successfully authenticated"* ]] \
    || echec "Clé SSH GitHub non reconnue dans Cloud Shell (ssh -T git@github.com)"
  ok "Authentification SSH GitHub"
fi
if [[ -d "$DEPOT/.git" ]]; then
  git -C "$DEPOT" remote set-url origin "$REPO_URL"
  git -C "$DEPOT" fetch -q origin "$BRANCH" || echec "git fetch impossible depuis $REPO_URL"
else
  rm -rf "$DEPOT"
  git clone -q --branch "$BRANCH" --single-branch "$REPO_URL" "$DEPOT" || echec "git clone impossible depuis $REPO_URL"
fi
git -C "$DEPOT" checkout -q -B "$BRANCH" "origin/$BRANCH"
git -C "$DEPOT" reset -q --hard "origin/$BRANCH"
SHA="$(git -C "$DEPOT" rev-parse HEAD)"
SHA_GH="$(git ls-remote "$REPO_URL" "refs/heads/$BRANCH" | cut -f1)"
[[ "$SHA" == "$SHA_GH" ]] || echec "Commit local $SHA différent de GitHub $SHA_GH"
ok "develop = $(git -C "$DEPOT" log -1 --format='%h %s' | cut -c1-70)"
for f in deploy/docker-compose.yml deploy/Caddyfile deploy/Dockerfile.api deploy/Dockerfile.web; do
  [[ -f "$DEPOT/$f" ]] || echec "Fichier manquant dans develop : $f"
done
ok "Fichiers de déploiement présents"

BUNDLE="$TRAVAIL/boussole-develop.bundle"
rm -f "$BUNDLE"
git -C "$DEPOT" bundle create -q "$BUNDLE" "$BRANCH"
git -C "$DEPOT" bundle verify -q "$BUNDLE" >/dev/null 2>&1 || echec "Bundle Git invalide"
ok "Bundle Git créé ($(du -h "$BUNDLE" | cut -f1))"

# ---------------------------------------------------------------------------------------------
# Script exécuté sur la VM (root). Arguments : commit attendu, bundle, e-mail admin, nom admin, mode.
INSTALLEUR="$TRAVAIL/boussole-installer-vm.sh"
cat > "$INSTALLEUR" <<'VM_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SHA_ATTENDU="$1"; BUNDLE="$2"; ADMIN_EMAIL="${3:-}"; ADMIN_NOM="${4:-Administrateur DEV}"; MODE="${5:-manuel}"
MARQUEUR_SYNCHRO=/etc/boussole-dev-sync/installe
DIR=/opt/boussole-dev
COMPOSE_DEV=docker-compose.dev-iap.yml
PROJET=boussole
PORT=8080
etape() { printf '\n  --- [VM] %s\n' "$*"; }
ok()    { printf '  [VM][OK] %s\n' "$*"; }
warn()  { printf '  [VM][ATTENTION] %s\n' "$*"; }
echec() { printf '  [VM][ECHEC] %s\n' "$*"; exit 1; }
trap 'rm -f "$BUNDLE"' EXIT
gen() { openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n'; }

[[ $EUID -eq 0 ]] || echec "À lancer avec sudo"
for c in git docker openssl curl ss; do command -v "$c" >/dev/null || echec "Commande absente sur la VM : $c"; done
docker info >/dev/null 2>&1 || echec "Moteur Docker arrêté"
docker compose version >/dev/null 2>&1 || echec "Plugin docker compose absent"
ok "Docker $(docker version --format '{{.Server.Version}}'), $(docker compose version --short)"

# Synchronisation installée : le déploiement manuel (construction sur la VM) écraserait la version déployée
# par digest et contournerait sauvegarde, contrôles et retour arrière. Refus avant toute modification.
if [[ "$MODE" != synchro && -e "$MARQUEUR_SYNCHRO" ]]; then
  echec "Synchronisation automatique installée ($MARQUEUR_SYNCHRO) : déploiement manuel REFUSÉ. Utiliser boussole-dev-sync (--etat, --appliquer, --version, --retour-manuel) ou relancer ce script avec --installer-synchro pour le mettre à jour."
fi

etape "Code dans $DIR"
if [[ -d "$DIR/.git" ]]; then
  [[ -z "$(git -C "$DIR" status --porcelain --untracked-files=no)" ]] \
    || { git -C "$DIR" status --short --untracked-files=no; echec "Fichiers suivis modifiés sur la VM (git stash dans $DIR)"; }
  git -C "$DIR" fetch -q "$BUNDLE" develop
  git -C "$DIR" checkout -q -B develop FETCH_HEAD
else
  if [[ -e "$DIR" ]]; then
    if [[ -n "$(ls -A "$DIR")" ]]; then
      mv "$DIR" "$DIR.avant-git-$(date +%Y%m%d-%H%M%S)"; warn "Ancien contenu non Git de $DIR mis de côté"
    else rmdir "$DIR"; fi
  fi
  git clone -q -b develop "$BUNDLE" "$DIR"
fi
chmod 750 "$DIR"
SHA="$(git -C "$DIR" rev-parse HEAD)"
[[ "$SHA" == "$SHA_ATTENDU" ]] || echec "Commit sur la VM $SHA différent de $SHA_ATTENDU"
ok "Commit vérifié : ${SHA:0:12}"

etape "Ressources"
ram_mo=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
swap_actif() { (( $(awk 'NR > 1' /proc/swaps | wc -l) > 0 )); }
if (( ram_mo < 6000 )) && ! swap_actif; then
  [[ -e /swapfile ]] || { fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null; }
  swapon /swapfile 2>/dev/null || warn "Swap non activé : la compilation du front peut manquer de mémoire"
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap defaults 0 0' >> /etc/fstab
fi
swap_actif && ok "RAM ${ram_mo} Mo + swap actif" || warn "RAM ${ram_mo} Mo sans swap"
libre_go=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
(( libre_go >= 5 )) || echec "Moins de 5 Go libres ($libre_go Go) : docker system prune"
ok "Disque libre : ${libre_go} Go"

if [[ "$MODE" == synchro ]]; then
  etape "Installation de la synchronisation automatique (aucun conteneur arrêté ni reconstruit)"
  [[ -f "$DIR/deploy/.env" ]] || echec "$DIR/deploy/.env absent : la synchronisation reprend un déploiement existant"
  for f in deploy/vm/boussole-dev-sync deploy/vm/boussole-dev-sync.service deploy/vm/boussole-dev-sync.timer \
           deploy/vm/logrotate-boussole-deploy deploy/vm/config.exemple deploy/docker-compose.dev.yml; do
    [[ -f "$DIR/$f" ]] || echec "Fichier manquant dans develop : $f"
  done
  install -d -m 700 /etc/boussole-dev-sync
  install -m 755 "$DIR/deploy/vm/boussole-dev-sync" /usr/local/sbin/boussole-dev-sync
  install -m 600 "$DIR/deploy/docker-compose.dev.yml" /etc/boussole-dev-sync/docker-compose.dev.yml
  [[ -f /etc/boussole-dev-sync/config ]] || install -m 600 "$DIR/deploy/vm/config.exemple" /etc/boussole-dev-sync/config
  install -m 644 "$DIR/deploy/vm/boussole-dev-sync.service" "$DIR/deploy/vm/boussole-dev-sync.timer" /etc/systemd/system/
  install -m 644 "$DIR/deploy/vm/logrotate-boussole-deploy" /etc/logrotate.d/boussole-deploy
  systemctl daemon-reload
  printf 'commit=%s\ninstalle_le=%s\n' "$SHA" "$(date -Iseconds)" > "$MARQUEUR_SYNCHRO"
  ok "boussole-dev-sync, Compose DEV, unités systemd et rotation du journal installés (commit ${SHA:0:12})"
  if systemctl is-enabled --quiet boussole-dev-sync.timer 2>/dev/null; then
    ok "Timer déjà activé : conservé (mise à jour du script seulement)"
  else
    ok "Timer installé mais NON activé"
  fi
  if [[ -f /var/lib/boussole-deploy/active.json ]]; then
    ok "Version active déjà enregistrée : adoption inutile"
  else
    etape "Adoption du déploiement manuel en place"
    /usr/local/sbin/boussole-dev-sync --adopter || echec "Adoption impossible (voir ci-dessus) : rien n'a été modifié dans les conteneurs"
  fi
  etape "Simulation du prochain déploiement (aucun arrêt)"
  /usr/local/sbin/boussole-dev-sync --simulation || warn "Simulation en échec : ne pas lancer --appliquer avant d'avoir compris la cause"
  /usr/local/sbin/boussole-dev-sync --etat || true
  printf '\n  [VM] Prochaines étapes (accord explicite requis) :\n'
  printf '    1. Première bascule : sudo boussole-dev-sync --appliquer\n'
  printf '    2. Après réussite : sudo systemctl enable --now boussole-dev-sync.timer\n'
  exit 0
fi

etape "Configuration privée (.env et Compose)"
cd "$DIR/deploy"
if [[ ! -f .env ]]; then
  if docker volume inspect "${PROJET}_db" >/dev/null 2>&1; then
    echec "Volume ${PROJET}_db existant mais .env absent : mot de passe PostgreSQL inconnu. Restaurer .env ou supprimer le volume (docker volume rm ${PROJET}_db, données perdues)."
  fi
  ( umask 077; cat > .env <<ENV
# Généré le $(date -Iseconds) par deployer-dev-iap.sh — DEV privé (IAP), jamais versionné.
# :80 = Caddy en HTTP simple, sans certificat ; publié uniquement sur 127.0.0.1:${PORT} (voir ${COMPOSE_DEV}).
PKP_DOMAINE=:80
PKP_SECRET_KEY=$(gen)
PKP_DB_MOT_DE_PASSE=$(gen)
PKP_SERVIR_QUESTIONS_NON_VALIDEES=true
PKP_RETENTION_JOURS=365
ENV
  )
  ok ".env créé avec des secrets aléatoires"
else
  # Ajustements préparés sur une copie privée ; .env n'est sauvegardé puis remplacé que s'il change.
  nouveau="$(umask 077; mktemp .env.nouveau.XXXXXX)"
  cp .env "$nouveau"
  if ! grep -qx 'PKP_DOMAINE=:80' "$nouveau"; then
    sed -i 's/^PKP_DOMAINE=.*/PKP_DOMAINE=:80/' "$nouveau"
    grep -qx 'PKP_DOMAINE=:80' "$nouveau" || echo 'PKP_DOMAINE=:80' >> "$nouveau"
  fi
  grep -q '^PKP_SERVIR_QUESTIONS_NON_VALIDEES=' "$nouveau" || echo 'PKP_SERVIR_QUESTIONS_NON_VALIDEES=true' >> "$nouveau"
  if cmp -s .env "$nouveau"; then
    rm -f "$nouveau"
    ok ".env existant conservé, inchangé (aucune copie)"
  else
    ( umask 077; cp -p .env ".env.sauvegarde-$(date +%Y%m%d-%H%M%S)" )
    chmod 600 .env.sauvegarde-* "$nouveau"
    mv -f "$nouveau" .env
    # Seules les 5 copies les plus récentes sont gardées (elles contiennent les secrets).
    ls -1t .env.sauvegarde-* 2>/dev/null | tail -n +6 | xargs -r rm -f --
    warn ".env ajusté (PKP_DOMAINE=:80 et/ou PKP_SERVIR_QUESTIONS_NON_VALIDEES) ; ancienne version sauvegardée, 5 copies max"
  fi
fi
chmod 600 .env
for v in PKP_SECRET_KEY PKP_DB_MOT_DE_PASSE; do
  val="$(grep -E "^$v=" .env | cut -d= -f2-)"
  (( ${#val} >= 32 )) || echec "$v vide ou trop courte dans .env"
done

# Copie du Compose officiel : 80/443 publics remplacés par 127.0.0.1:8080 seulement.
{
  echo "# GÉNÉRÉ par deployer-dev-iap.sh depuis docker-compose.yml — ne pas modifier, ne pas versionner."
  awk -v p="$PORT" '
    /^[[:space:]]*- "80:80"/  { sub(/"80:80"/, "\"127.0.0.1:" p ":80\""); print; next }
    /^[[:space:]]*- "443:443/ { next }
    { print }' docker-compose.yml
} > "$COMPOSE_DEV"
grep -q "\"127.0.0.1:${PORT}:80\"" "$COMPOSE_DEV" || echec "Port privé non appliqué dans $COMPOSE_DEV"
! grep -q '443:443' "$COMPOSE_DEV" || echec "Port 443 encore publié"
grep -qx "deploy/$COMPOSE_DEV" "$DIR/.git/info/exclude" 2>/dev/null || echo "deploy/$COMPOSE_DEV" >> "$DIR/.git/info/exclude"
dc() { docker compose -p "$PROJET" --env-file .env -f "$COMPOSE_DEV" "$@"; }
dc config -q || echec "Configuration Compose invalide"
ok "Compose privé : web sur 127.0.0.1:${PORT}, API et PostgreSQL non publiés"

etape "Construction et démarrage (plusieurs minutes : tests et compilation du front)"
dc up -d --build --remove-orphans || { dc logs --tail 60; echec "docker compose up a échoué"; }

etape "Contrôles"
pret=false
for _ in $(seq 100); do
  if dc exec -T api python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" >/dev/null 2>&1; then pret=true; break; fi
  sleep 3
done
$pret || { dc logs --tail 80 api; echec "L'API ne répond pas après 5 minutes"; }
ok "API prête"
schema="$(dc exec -T api alembic current 2>/dev/null | tail -1)"
[[ "$schema" == *"(head)"* ]] || echec "Schéma de base non à jour : $schema"
ok "Migrations appliquées : $schema"
services="$(dc ps --status running --services | sort | tr '\n' ' ')"
for s in api db purge web; do [[ " $services " == *" $s "* ]] || echec "Service $s non démarré (en cours : $services)"; done
ok "Services en marche : $services"
sante="$(curl -fsS --max-time 10 "http://127.0.0.1:${PORT}/api/health")" || { dc logs --tail 40 web; echec "Caddy ne relaie pas /api/health"; }
[[ "$sante" == *'"ok"'* ]] || echec "Réponse /api/health inattendue : $sante"
ok "http://127.0.0.1:${PORT}/api/health -> $sante"
curl -fsS --max-time 10 "http://127.0.0.1:${PORT}/" | grep -qi '<html' || echec "La page d'accueil ne renvoie pas de HTML"
ok "Page d'accueil servie"
publics="$(ss -ltnH | awk '{print $4}' | grep -E '^(0\.0\.0\.0|\[::\]|\*):(80|443|8080|8000|5432)$' || true)"
[[ -z "$publics" ]] || echec "Ports ouverts sur toutes les interfaces : $publics"
ok "Aucun port applicatif ouvert hors 127.0.0.1"

if [[ -n "$ADMIN_EMAIL" ]]; then
  etape "Administrateur $ADMIN_EMAIL"
  if dc exec -T api python -m app.admin promouvoir --email "$ADMIN_EMAIL" >/dev/null 2>&1; then
    ok "Compte existant : rôle administrateur confirmé (mot de passe et 2FA inchangés)"
  else
    MDP="$(gen | cut -c1-24)"
    printf '%s\n' "$MDP" | dc exec -T api python -m app.admin creer --email "$ADMIN_EMAIL" --nom "$ADMIN_NOM" --admin >/dev/null \
      || echec "Création du compte administrateur impossible"
    URI="$(dc exec -T api python -m app.admin totp --email "$ADMIN_EMAIL" | grep -m1 '^otpauth://' || true)"
    [[ -n "$URI" ]] || echec "Second facteur non configuré"
    ( umask 077; printf 'E-mail : %s\nMot de passe : %s\nTOTP : %s\n' "$ADMIN_EMAIL" "$MDP" "$URI" > /root/boussole-admin-initial.txt )
    ok "Compte administrateur créé"
    printf '\n  ************ IDENTIFIANTS ADMIN (affichés une seule fois) ************\n'
    printf '  E-mail       : %s\n  Mot de passe : %s\n  TOTP (URI)   : %s\n' "$ADMIN_EMAIL" "$MDP" "$URI"
    printf '  Copie sur la VM : /root/boussole-admin-initial.txt (à supprimer après sauvegarde)\n'
    printf '  *********************************************************************\n'
    if command -v qrencode >/dev/null; then qrencode -t ansiutf8 "$URI"; fi
  fi
fi
printf '\n  [VM] Installation terminée : commit %s\n' "${SHA:0:12}"
VM_EOF
bash -n "$INSTALLEUR" || echec "Script VM invalide"

# ---------------------------------------------------------------------------------------------
etape "3. Transfert vers la VM (IAP)"
# Répertoire privé (mode 700, propriétaire : le compte OS Login), supprimé en fin d'exécution, même en échec.
DOSSIER_VM="$(gssh --command 'mktemp -d /tmp/boussole-deploiement.XXXXXXXX' 2>/dev/null | tr -d '\r' | tail -1)"
[[ "$DOSSIER_VM" =~ ^/tmp/boussole-deploiement\.[A-Za-z0-9]{8}$ ]] || echec "Répertoire temporaire privé non créé sur la VM"
gcloud compute scp "$BUNDLE" "$INSTALLEUR" "$VM:$DOSSIER_VM/" "${GC[@]}" --tunnel-through-iap --quiet >/dev/null \
  || echec "Transfert scp via IAP impossible"
ok "Bundle et installeur copiés dans un répertoire privé de la VM ($DOSSIER_VM)"

# ---------------------------------------------------------------------------------------------
etape "4. Installation sur la VM"
printf -v CMD 'sudo bash %q %q %q %q %q %q; c=$?; rm -rf -- %q; exit $c' \
  "$DOSSIER_VM/boussole-installer-vm.sh" "$SHA" "$DOSSIER_VM/boussole-develop.bundle" "$ADMIN_EMAIL" "$ADMIN_NOM" "$MODE" "$DOSSIER_VM"
gssh --command "$CMD" -- -o ServerAliveInterval=30 -o ServerAliveCountMax=20 \
  || echec "Installation sur la VM en échec (voir les lignes [VM] ci-dessus)"
DOSSIER_VM=""   # supprimé par la commande d'installation
if [[ "$MODE" == synchro ]]; then
  ok "Synchronisation installée sur la VM (commit ${SHA:0:12}) ; aucun conteneur modifié, timer non activé"
else
  ok "Application installée et contrôlée sur la VM (commit ${SHA:0:12})"
fi
[[ -z "$ADMIN_EMAIL" ]] || ok "Administrateur $ADMIN_EMAIL traité"

# ---------------------------------------------------------------------------------------------
etape "5. Validation de bout en bout par tunnel IAP (comme depuis Windows)"
# Port local déjà utilisé (autre tunnel, autre outil) : on ne ferme rien qui n'appartient pas au script.
if (exec 3<>"/dev/tcp/127.0.0.1/${PORT_TEST}") 2>/dev/null; then
  echec "Port local ${PORT_TEST} déjà utilisé dans Cloud Shell : fermer le processus concerné, puis relancer"
fi
setsid gcloud compute ssh "$VM" "${GC[@]}" --tunnel-through-iap --quiet -- -N -L "${PORT_TEST}:localhost:${PORT_VM}" \
  -o ExitOnForwardFailure=yes >"$TRAVAIL/tunnel.log" 2>&1 &
TUNNEL_PID=$!
sante=""
for _ in $(seq 30); do
  sante="$(curl -fsS --max-time 5 "http://localhost:${PORT_TEST}/api/health" 2>/dev/null || true)"
  [[ -n "$sante" ]] && break
  kill -0 "$TUNNEL_PID" 2>/dev/null || { cat "$TRAVAIL/tunnel.log"; echec "Le tunnel IAP s'est fermé"; }
  sleep 2
done
[[ "$sante" == *'"ok"'* ]] || { cat "$TRAVAIL/tunnel.log"; echec "/api/health inaccessible par le tunnel"; }
ok "Tunnel IAP : /api/health -> $sante"
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://localhost:${PORT_TEST}/")"
[[ "$code" == 200 ]] || echec "Page d'accueil par le tunnel : HTTP $code"
ok "Tunnel IAP : page d'accueil HTTP 200"
for chemin in eleve enseignant admin; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://localhost:${PORT_TEST}/$chemin")"
  if [[ "$code" == 200 ]]; then ok "Tunnel IAP : /$chemin HTTP 200"; else warn "/$chemin : HTTP $code"; fi
done
fermer_tunnel

etape "Terminé"
cat <<FIN
  Depuis ton poste Windows (PowerShell, gcloud installé et connecté au même compte) :

    gcloud compute ssh $VM --project $PROJECT --zone $ZONE --tunnel-through-iap -- -N -L 8080:localhost:$PORT_VM

  puis, tant que cette fenêtre reste ouverte :
    http://localhost:8080/              accueil
    http://localhost:8080/api/health    santé de l'API
    http://localhost:8080/admin         administration (e-mail, mot de passe, code TOTP)

  Commandes utiles sur la VM (gcloud compute ssh $VM --zone $ZONE --tunnel-through-iap) :
    sudo boussole-dev-sync --etat                    (si la synchronisation est installée)
    sudo journalctl -u boussole-dev-sync --since today
    cd /opt/boussole-dev/deploy && sudo docker compose -p boussole -f docker-compose.dev-iap.yml ps   (déploiement manuel)
    cd /opt/boussole-dev/deploy && sudo docker compose -p boussole -f docker-compose.dev-iap.yml logs -f api

  Économie : gcloud compute instances stop $VM --project $PROJECT --zone $ZONE
FIN
