#!/usr/bin/env bash
# Issue #8 — Sauvegardes automatisées et restauration testée (Claude)
#
# sauvegarde-prod.sh — sauvegarde chiffrée de la production (VM GCP Ubuntu ou Oracle Linux), copiée hors VM dans
# un bucket GCS dédié, et restauration de contrôle dans une base TEMPORAIRE isolée. Commandes (root) :
#
#   sauvegarde-prod.sh --verifier                 contrôle la configuration et les outils ; n'écrit rien
#   sauvegarde-prod.sh --sauvegarder [--motif <m>]  une sauvegarde (lancée chaque nuit par le timer systemd) ;
#                                                 motif : quotidienne (défaut), avant-deploiement, manuelle
#   sauvegarde-prod.sh --etat                     dernière sauvegarde réussie ; code 1 si absente, en échec ou
#                                                 plus vieille que AGE_MAX_HEURES (surveillance)
#   sauvegarde-prod.sh --restaurer-isole <gs://…|fichier.tar.age> --identite <clé privée age>
#                                                 hors VM de production (poste, Cloud Shell, VM de test) :
#                                                 déchiffre, restaure dans un conteneur PostgreSQL temporaire
#                                                 sans réseau, compare révision Alembic et comptages, mesure la
#                                                 durée, puis supprime tout. N'écrit dans aucune base existante.
#
# Contenu d'une sauvegarde (une seule archive chiffrée avec age, pour une ou plusieurs clés PUBLIQUES) :
#   db.dump (pg_dump -Fc, instantané cohérent de la base), fichiers.tar.gz (PDF des ressources), env (le .env :
#   secrets), manifeste.json (date, révision Alembic, comptages, sommes SHA-256 ; aucune donnée personnelle).
# La VM ne détient que les clés publiques : elle chiffre mais ne peut pas relire ses sauvegardes. Aucun fichier en
# clair ne reste sur le disque après l'exécution. Aucun secret dans les journaux.
#
# Codes de sortie : 0 succès ; 1 échec (sauvegarde ou restauration non conforme) ; 3 refus (configuration).
set -Eeuo pipefail
umask 077

# --- Configuration -----------------------------------------------------------------------------------------
if [[ "${BOUSSOLE_SAUVEGARDE_TEST:-}" == 1 ]]; then     # banc de test : faux docker, gcloud et age dans le PATH
  : "${CONFIG:?}" "${ETAT:?}" "${JOURNAL:?}" "${VERROU:?}"
  PAUSE="${PAUSE:-0}"
else
  CONFIG=/etc/boussole-sauvegarde/config
  ETAT=/var/lib/boussole-sauvegarde
  JOURNAL=/var/log/boussole-sauvegarde.log
  VERROU=/run/boussole-sauvegarde.lock
  PAUSE=2
fi
DEPLOY=""             # dossier deploy/ de la production (docker-compose.yml et .env)
DESTINATION=""        # gs://<bucket>/<préfixe>
SITE=""               # gcp | oracle : sous-dossier dans le bucket (aucun nom de personne ni d'établissement)
AGE_DESTINATAIRES=""  # une ou plusieurs clés publiques age (age1…), séparées par des espaces
GARDER_LOCAL=3        # archives CHIFFRÉES gardées sur la VM
AGE_MAX_HEURES=26     # au-delà, --etat signale une sauvegarde manquante
GCLOUD_CONFIG=""      # Oracle : dossier gcloud dédié où le compte de service a été activé (voir la fiche T-04)
# shellcheck disable=SC1090
[[ -f "$CONFIG" ]] && source "$CONFIG"

# Tables comptées à la sauvegarde puis après restauration (comptages seulement : aucune donnée personnelle).
TABLES=(enseignant classe eleve enfant parent seance reponse chapitre question remarque)

# --- Outils ------------------------------------------------------------------------------------------------
horodatage() { date -u +%Y-%m-%dT%H:%M:%SZ; }
journal() { local m; m="$(horodatage) [$1] $2"; echo "$m"; [[ -n "${JOURNAL_ACTIF:-}" ]] && echo "$m" >> "$JOURNAL"; return 0; }
info() { journal info "$1"; }
erreur() { journal erreur "$1" >&2; }
refus() { journal refus "$1" >&2; exit 3; }
TRAVAIL=""; TEMPORAIRE=""
nettoyer() {
  [[ -z "$TEMPORAIRE" ]] || { docker rm -f "$TEMPORAIRE" >/dev/null 2>&1 || true; docker volume rm "$TEMPORAIRE" >/dev/null 2>&1 || true; }
  [[ -z "$TRAVAIL" ]] || rm -rf -- "$TRAVAIL"
}
trap nettoyer EXIT
verrouiller() { exec 9>"$VERROU"; flock -n 9 || refus "Une autre exécution est en cours ($VERROU)"; }
gcloud_() { if [[ -n "$GCLOUD_CONFIG" ]]; then CLOUDSDK_CONFIG="$GCLOUD_CONFIG" gcloud "$@"; else gcloud "$@"; fi; }
dc() { docker compose --project-directory "$DEPLOY" -f "$DEPLOY/docker-compose.yml" "$@"; }
sql_prod() { dc exec -T db psql -U pkp -d pkp -tAc "$1"; }
sql_temp() { docker exec "$TEMPORAIRE" psql -U pkp -d pkp -tAc "$1"; }
comptages() {   # comptages <fonction sql> : JSON {table: nombre | null si la table n'existe pas}
  local t n sortie="{" sep=""
  for t in "${TABLES[@]}"; do
    if [[ "$($1 "SELECT to_regclass('public.$t') IS NOT NULL" | tr -d '[:space:]')" == t ]]; then
      n="$($1 "SELECT count(*) FROM $t" | tr -d '[:space:]')"; [[ "$n" =~ ^[0-9]+$ ]] || return 1
    else n=null; fi
    sortie+="$sep\"$t\": $n"; sep=", "
  done
  echo "$sortie}"
}
ecrire_etat() {   # ecrire_etat <statut> <champs JSON supplémentaires>
  mkdir -p "$ETAT"
  printf '{"statut": "%s", "le": "%s"%s}\n' "$1" "$(horodatage)" "$2" > "$ETAT/derniere.json"
  [[ "$1" != ok ]] || cp -p "$ETAT/derniere.json" "$ETAT/derniere-reussie.json"
}

controler_config() {   # refus explicite de toute configuration incomplète ou dangereuse
  [[ -f "$CONFIG" ]] || refus "Configuration absente : $CONFIG (voir docs/exploitation/technique.md, T-04)"
  [[ -n "$DEPLOY" && -f "$DEPLOY/docker-compose.yml" && -f "$DEPLOY/.env" ]] || refus "DEPLOY ne désigne pas le dossier deploy/ de la production"
  [[ "$DESTINATION" =~ ^gs://[a-z0-9][a-z0-9._-]{1,61}[a-z0-9](/[A-Za-z0-9._-]+)*$ ]] || refus "DESTINATION invalide (attendu : gs://<bucket>/<préfixe>)"
  [[ "$SITE" =~ ^(gcp|oracle)$ ]] || refus "SITE invalide (gcp ou oracle)"
  [[ "$GARDER_LOCAL" =~ ^[0-9]+$ && "$AGE_MAX_HEURES" =~ ^[0-9]+$ ]] || refus "GARDER_LOCAL et AGE_MAX_HEURES : des nombres"
  local cle n=0
  for cle in $AGE_DESTINATAIRES; do
    [[ "$cle" =~ ^age1[0-9a-z]{58}$ ]] || refus "AGE_DESTINATAIRES : « ${cle:0:12}… » n'est pas une clé publique age (age1…)"
    n=$((n + 1))
  done
  (( n >= 1 )) || refus "AGE_DESTINATAIRES vide : aucune clé publique pour chiffrer"
  local outil; for outil in docker age gcloud flock python3; do command -v "$outil" >/dev/null || refus "Outil manquant : $outil"; done
}

# --- Sauvegarde --------------------------------------------------------------------------------------------
cmd_sauvegarder() {
  local motif="$1" debut=$SECONDS nom d archive objet rev compte cle args=() octets
  [[ "$motif" =~ ^(quotidienne|avant-deploiement|manuelle)$ ]] || refus "Motif invalide : $motif"
  controler_config
  mkdir -p "$ETAT/archives"; chmod 700 "$ETAT"
  TRAVAIL="$(mktemp -d "$ETAT/travail.XXXXXX")"; d="$TRAVAIL/contenu"; mkdir "$d"
  nom="$(date -u +%Y%m%dT%H%M%SZ)-$motif"
  echec() { erreur "$1"; ecrire_etat echec ", \"motif\": \"$motif\", \"raison\": \"$1\""; exit 1; }

  dc exec -T db pg_isready -U pkp -d pkp >/dev/null 2>&1 || echec "Base de production injoignable (service db)"
  dc exec -T db pg_dump -U pkp -d pkp -Fc > "$d/db.dump" || echec "pg_dump a échoué"
  [[ -s "$d/db.dump" ]] || echec "Sauvegarde PostgreSQL vide"
  dc exec -T db pg_restore --list < "$d/db.dump" > /dev/null || echec "Sauvegarde PostgreSQL illisible (pg_restore --list)"
  rev="$(sql_prod "SELECT version_num FROM alembic_version" | tr -d '[:space:]')"
  [[ -n "$rev" ]] || echec "Révision Alembic illisible"
  compte="$(comptages sql_prod)" || echec "Comptages impossibles"
  dc exec -T api tar -C /data -czf - fichiers > "$d/fichiers.tar.gz" || echec "Archive des fichiers (PDF) impossible : service api arrêté ?"
  tar -tzf "$d/fichiers.tar.gz" > /dev/null || echec "Archive des fichiers illisible"
  cp "$DEPLOY/.env" "$d/env"
  python3 - "$d" "$nom" "$motif" "$SITE" "$rev" "$compte" <<'PY' || echec "Manifeste non écrit"
import datetime, hashlib, json, os, sys
d, nom, motif, site, rev, compte = sys.argv[1:]
somme = lambda p: hashlib.sha256(open(os.path.join(d, p), "rb").read()).hexdigest()
json.dump({"nom": nom, "motif": motif, "site": site, "revision_alembic": rev, "comptages": json.loads(compte),
           "cree_le": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
           "fichiers": {p: {"sha256": somme(p), "octets": os.path.getsize(os.path.join(d, p))}
                        for p in ("db.dump", "fichiers.tar.gz", "env")}},
          open(os.path.join(d, "manifeste.json"), "w"), indent=2)
PY

  for cle in $AGE_DESTINATAIRES; do args+=(-r "$cle"); done
  archive="$TRAVAIL/$nom.tar.age"
  tar -C "$d" -cf - manifeste.json db.dump fichiers.tar.gz env | age "${args[@]}" -o "$archive" || echec "Chiffrement age impossible"
  rm -rf -- "$d"                       # plus aucun fichier en clair
  octets="$(stat -c %s "$archive")"
  objet="$DESTINATION/$SITE/$nom.tar.age"
  # Le compte de service n'a que le droit de CRÉER des objets : une sauvegarde ne peut être ni lue, ni remplacée,
  # ni supprimée depuis la VM. gcloud vérifie la somme CRC32C de l'envoi.
  gcloud_ storage cp --no-clobber "$archive" "$objet" >/dev/null 2>"$TRAVAIL/gcloud.err" \
    || echec "Copie hors VM impossible ($(tail -1 "$TRAVAIL/gcloud.err" | cut -c1-200))"
  mv "$archive" "$ETAT/archives/"
  find "$ETAT/archives" -maxdepth 1 -name '*.tar.age' -printf '%T@ %p\n' | sort -rn | tail -n +$((GARDER_LOCAL + 1)) \
    | cut -d' ' -f2- | xargs -r rm -f --
  ecrire_etat ok ", \"motif\": \"$motif\", \"objet\": \"$objet\", \"octets\": $octets, \"revision_alembic\": \"$rev\", \"duree_s\": $((SECONDS - debut))"
  info "Sauvegarde $nom chiffrée ($octets octets) et copiée hors VM : $objet (révision $rev, $((SECONDS - debut)) s)"
}

# --- Surveillance ------------------------------------------------------------------------------------------
cmd_etat() {
  local f="$ETAT/derniere-reussie.json"
  [[ -f "$ETAT/derniere.json" ]] && echo "Dernière exécution : $(cat "$ETAT/derniere.json")"
  [[ -f "$f" ]] || { echo "ALERTE : aucune sauvegarde réussie"; return 1; }
  python3 - "$f" "$ETAT/derniere.json" "$AGE_MAX_HEURES" <<'PY'
import datetime, json, sys
ok, der, maxi = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), int(sys.argv[3])
age = (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(ok["le"].replace("Z", "+00:00"))).total_seconds() / 3600
print(f"Dernière sauvegarde réussie : {ok['le']} (il y a {age:.1f} h) — {ok.get('objet', '?')}")
if der["statut"] != "ok":
    sys.exit(f"ALERTE : la dernière exécution a échoué : {der.get('raison', '?')}")
if age > maxi:
    sys.exit(f"ALERTE : dernière sauvegarde réussie plus vieille que {maxi} h")
PY
}

cmd_verifier() {
  controler_config
  dc exec -T db pg_isready -U pkp -d pkp >/dev/null 2>&1 || refus "Base de production injoignable (service db)"
  dc exec -T api true >/dev/null 2>&1 || refus "Service api arrêté : l'archive des fichiers est impossible"
  info "Configuration conforme : $DEPLOY → $DESTINATION/$SITE/ ($(wc -w <<<"$AGE_DESTINATAIRES") clé(s) publique(s), $GARDER_LOCAL archive(s) locale(s))"
}

# --- Restauration isolée (hors VM de production) -----------------------------------------------------------
cmd_restaurer_isole() {
  local source="$1" identite="$2" debut=$SECONDS d archive rev attendu pret=non apres
  [[ -f "$identite" ]] || refus "Clé privée age introuvable : $identite"
  local outil; for outil in docker age python3; do command -v "$outil" >/dev/null || refus "Outil manquant : $outil"; done
  TRAVAIL="$(mktemp -d)"; d="$TRAVAIL/contenu"; mkdir "$d"; archive="$TRAVAIL/archive.tar.age"
  if [[ "$source" == gs://* ]]; then
    command -v gcloud >/dev/null || refus "Outil manquant : gcloud"
    gcloud_ storage cp "$source" "$archive" >/dev/null 2>&1 || refus "Téléchargement impossible : $source"
  else
    [[ -f "$source" ]] || refus "Archive introuvable : $source"; cp "$source" "$archive"
  fi
  age -d -i "$identite" -o "$TRAVAIL/archive.tar" "$archive" 2>/dev/null || { erreur "Déchiffrement impossible (clé ou archive)"; return 1; }
  tar -C "$d" -xf "$TRAVAIL/archive.tar" manifeste.json db.dump fichiers.tar.gz env || { erreur "Archive incomplète"; return 1; }
  rm -f "$TRAVAIL/archive.tar"
  python3 - "$d" <<'PY' || { erreur "Sommes de contrôle non conformes"; return 1; }
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifeste.json")))
for nom, attendu in m["fichiers"].items():
    p = os.path.join(d, nom)
    if hashlib.sha256(open(p, "rb").read()).hexdigest() != attendu["sha256"] or os.path.getsize(p) != attendu["octets"]:
        sys.exit(f"{nom} : somme ou taille différente")
PY
  info "Archive déchiffrée : sommes SHA-256 conformes"
  TEMPORAIRE="boussole-restauration-$(date -u +%Y%m%d%H%M%S)"
  python3 -c 'import secrets; print("POSTGRES_DB=pkp\nPOSTGRES_USER=pkp\nPOSTGRES_PASSWORD=" + secrets.token_urlsafe(24))' > "$TRAVAIL/pg.env"
  docker volume create "$TEMPORAIRE" >/dev/null || { erreur "Volume temporaire non créé"; return 1; }
  docker run -d --name "$TEMPORAIRE" --network none --env-file "$TRAVAIL/pg.env" \
    -v "$TEMPORAIRE:/var/lib/postgresql/data" postgres:16-alpine >/dev/null || { erreur "Base temporaire non démarrée"; return 1; }
  for _ in $(seq 60); do
    if docker exec "$TEMPORAIRE" pg_isready -U pkp -d pkp >/dev/null 2>&1; then pret=oui; break; fi
    sleep "$PAUSE"
  done
  [[ "$pret" == oui ]] || { erreur "Base temporaire non prête"; return 1; }
  docker exec -i "$TEMPORAIRE" pg_restore -U pkp -d pkp --no-owner --exit-on-error < "$d/db.dump" >/dev/null \
    || { erreur "pg_restore a échoué dans la base temporaire"; return 1; }
  rev="$(sql_temp "SELECT version_num FROM alembic_version" | tr -d '[:space:]')"
  apres="$(comptages sql_temp)" || { erreur "Comptages impossibles après restauration"; return 1; }
  python3 - "$d/manifeste.json" "$rev" "$apres" "$d/fichiers.tar.gz" "$d/env" <<'PY' || { erreur "Restauration isolée NON conforme"; return 1; }
import json, sys, tarfile
m, rev, apres = json.load(open(sys.argv[1])), sys.argv[2], json.loads(sys.argv[3])
ecarts = [] if rev == m["revision_alembic"] else [f"révision {rev} ≠ {m['revision_alembic']}"]
for t, n in m["comptages"].items():
    print(f"  {t:<12} sauvegardé {n!s:>8}   restauré {apres.get(t)!s:>8}")
    if apres.get(t) != n:
        ecarts.append(f"{t} : {apres.get(t)} ≠ {n}")
with tarfile.open(sys.argv[4]) as a:
    print(f"  fichiers     {sum(1 for x in a.getmembers() if x.isfile())} dans l'archive des PDF")
cles = [l.split("=", 1)[0] for l in open(sys.argv[5]) if "=" in l and not l.startswith("#")]
print(f"  .env         {len(cles)} variable(s) : {', '.join(sorted(cles))}")   # noms seulement, jamais les valeurs
print(f"Sauvegarde {m['nom']} ({m['site']}, {m['cree_le']}) — révision Alembic {rev}")
sys.exit("; ".join(ecarts) if ecarts else 0)
PY
  info "Restauration isolée conforme en $((SECONDS - debut)) s (mesure du RTO de la base) ; base et volume temporaires supprimés"
}

usage() { sed -n '4,25p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

main() {
  [[ $# -ge 1 ]] || usage 3
  case "$1" in
    -h|--help) usage 0 ;;
    --verifier) cmd_verifier ;;
    --etat) cmd_etat ;;
    --sauvegarder)
      local motif=quotidienne
      [[ $# -eq 1 || ( $# -eq 3 && "$2" == --motif ) ]] || usage 3
      [[ $# -eq 1 ]] || motif="$3"
      mkdir -p "$(dirname "$JOURNAL")"; JOURNAL_ACTIF=1; verrouiller; cmd_sauvegarder "$motif" ;;
    --restaurer-isole)
      [[ $# -eq 4 && "$3" == --identite ]] || usage 3
      cmd_restaurer_isole "$2" "$4" ;;
    *) usage 3 ;;
  esac
}
main "$@"
