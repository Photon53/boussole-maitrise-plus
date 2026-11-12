#!/usr/bin/env bash
# Banc de test de deploy/vm/boussole-dev-sync (ticket #65, PR 3b), sans VM, sans Docker, sans accès GCP.
# Faux docker (faux_docker.py) et faux services HTTP (faux_services.py : GCS, métadonnées, application).
# Usage : bash deploy/vm/tests/test-boussole-dev-sync.sh
# shellcheck disable=SC2154  # SHA_*, API_*, WEB_* sont créées par publier() (eval)
set -Euo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
SYNC="$ICI/../boussole-dev-sync"
COMPOSE_SOURCE="$ICI/../../docker-compose.dev.yml"
T="$(mktemp -d)"
SERVEUR=""
trap '[[ -n "$SERVEUR" ]] && kill "$SERVEUR" 2>/dev/null; rm -rf "$T"' EXIT
REGISTRY="europe-west9-docker.pkg.dev/mer-boussole-dev/boussole-dev"
reussis=0; echecs=0; CODE=0

sha_de()    { printf '%s' "$1" | sha1sum | cut -c1-40; }
digest_de() { printf '%s' "$1" | sha256sum | cut -c1-64; }
etat_py()   { python3 - "$E/docker.json" "$@" <<'PY'
import json, sys
f = sys.argv[1]; e = json.load(open(f))
for instr in sys.argv[2:]:
    exec(instr)
json.dump(e, open(f, "w"), indent=1)
PY
}
lire_py()   { python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$E/docker.json" "$1"; }
jv()        { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1]))[sys.argv[2]])
except Exception: print("")' "$1" "$2"; }

initialiser() {   # environnement neuf : déploiement manuel en service (révision 0031), bucket vide
  [[ -n "$SERVEUR" ]] && kill "$SERVEUR" 2>/dev/null; SERVEUR=""
  [[ -f "$T/env/requetes.log" ]] && cat "$T/env/requetes.log" >> "$T/toutes-requetes.log"   # gardées pour le contrôle final
  E="$T/env"; rm -rf "$E"; mkdir -p "$E"/{etat,gcs,depot,deploy,compose}
  printf 'BUCKET=mer-boussole-dev-deploiement\nREGISTRY=%s\n' "$REGISTRY" > "$E/config"
  printf 'PKP_DOMAINE=:80\nPKP_SECRET_KEY=secret-de-test-ne-doit-pas-fuiter\nPKP_DB_MOT_DE_PASSE=mdp-de-test\n' > "$E/deploy/.env"
  cp "$COMPOSE_SOURCE" "$E/compose/docker-compose.dev.yml"
  echo "# compose manuel (simulé)" > "$E/deploy/docker-compose.dev-iap.yml"
  # Historique du dépôt de la VM : A en place à la construction des images (10/11 20:52), puis B (mise à jour
  # du code le 12/11, sans reconstruction). La provenance adoptée doit être A, pas le HEAD actuel B.
  git -C "$E/depot" init -q
  GIT_COMMITTER_DATE="2026-11-10T18:00:00Z" GIT_AUTHOR_DATE="2026-11-10T18:00:00Z" \
    git -C "$E/depot" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m "A : construit"
  COMMIT_A="$(git -C "$E/depot" rev-parse HEAD)"
  GIT_COMMITTER_DATE="2026-11-12T10:00:00Z" GIT_AUTHOR_DATE="2026-11-12T10:00:00Z" \
    git -C "$E/depot" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m "B : mis à jour"
  COMMIT_B="$(git -C "$E/depot" rev-parse HEAD)"
  cat > "$E/docker.json" <<EOF
{"images": {
  "img-manuel-api": {"tags": ["pkp-api:latest"], "digests": [], "cree": "2026-11-10T20:52:11.123456789Z", "meta": {"head": "0031", "revisions": ["0030", "0031"]}},
  "img-manuel-web": {"tags": ["boussole-web"], "digests": [], "meta": {}},
  "img-postgres": {"tags": ["postgres:16-alpine"], "digests": [], "meta": {}}},
 "registre": {},
 "conteneurs": {
  "db":    {"id": "m-db", "image": "img-postgres", "running": true, "compose": "$E/deploy/docker-compose.dev-iap.yml", "config_image": "postgres:16-alpine"},
  "api":   {"id": "m-api", "image": "img-manuel-api", "running": true, "compose": "$E/deploy/docker-compose.dev-iap.yml", "config_image": "pkp-api:latest"},
  "purge": {"id": "m-purge", "image": "img-manuel-api", "running": true, "compose": "$E/deploy/docker-compose.dev-iap.yml", "config_image": "pkp-api:latest"},
  "web":   {"id": "m-web", "image": "img-manuel-web", "running": true, "compose": "$E/deploy/docker-compose.dev-iap.yml", "config_image": "boussole-web"}},
 "db": {"revision": "0031", "empreinte": "E0"},
 "appels": []}
EOF
  printf '#!/bin/sh\nexec python3 %q "$@"\n' "$ICI/faux_docker.py" > "$E/docker"; chmod +x "$E/docker"
  : > "$E/requetes.log"
  python3 "$ICI/faux_services.py" "$E/port" "$E/gcs" "$E/requetes.log" "$E/docker.json" & SERVEUR=$!
  for _ in $(seq 50); do [[ -s "$E/port" ]] && break; sleep 0.1; done
  PORT="$(cat "$E/port")"
}

publier() {   # publier <nom> <meta JSON de l'image API> [sha imposé] : manifeste releases/<sha>.json, images au registre
  local nom="$1" metajson="$2" sha api web head transfo
  sha="${3:-$(sha_de "$nom")}"; api="$REGISTRY/api@sha256:$(digest_de "$nom-api")"; web="$REGISTRY/web@sha256:$(digest_de "$nom-web")"
  head="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["head"])' "$metajson")"
  transfo="$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]).get("transformations", [])))' "$metajson")"
  etat_py "e['registre']['$api'] = json.loads('''$metajson''')" "e['registre']['$web'] = {}"
  mkdir -p "$E/gcs/releases"
  cat > "$E/gcs/releases/$sha.json" <<EOF
{"schema": 1, "sha": "$sha", "images": {"api": "$api", "web": "$web"}, "purge": "api",
 "migration": {"alembic_head_attendue": "$head"},
 "donnees": {"contenu_tree": "contenu-$nom", "referentiels_tree": "ref", "transformations_declarees": $transfo}}
EOF
  eval "SHA_${nom}=$sha API_${nom}=$api WEB_${nom}=$web"
}
pointer() { local v="SHA_$1"; printf '{"schema": 1, "sha": "%s"}\n' "${!v}" > "$E/gcs/releases/desired.json"; }

sync() {   # sync <args…> : sortie dans $T/sortie, code dans $CODE
  CODE=0
  env -i PATH="$PATH" HOME="$T" BOUSSOLE_SYNC_TEST=1 CONFIG="$E/config" ETAT="$E/etat" JOURNAL="$E/journal.log" \
    VERROU="$E/verrou" COMPOSE_DEV="$E/compose/docker-compose.dev.yml" ENV_FILE="$E/deploy/.env" DEPOT="$E/depot" \
    GCS_API="http://127.0.0.1:$PORT" METADATA_URL="http://127.0.0.1:$PORT" APP_URL="http://127.0.0.1:$PORT" \
    DOCKER="$E/docker" DELAI_SANTE=3 PAUSE_SANTE=0.2 FAUX_DOCKER_ETAT="$E/docker.json" \
    setsid -w bash "$SYNC" "$@" > "$T/sortie" 2>&1 || CODE=$?   # groupe de processus propre (interruptions)
}
marquer() { MARQUE="$(lire_py 'len(e["appels"])')"; }
appels_depuis() { python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["appels"][int(sys.argv[2]):]))' "$E/docker.json" "$MARQUE"; }

ok()   { echo "OK    $1"; reussis=$((reussis + 1)); }
ko()   { echo "ECHEC $1"; sed 's/^/      | /' "$T/sortie" | tail -15; echecs=$((echecs + 1)); }
verif() {   # verif <libellé> <code attendu> [motif attendu dans la sortie] [condition shell supplémentaire]
  local lib="$1" code="$2" motif="${3:-}" cond="${4:-true}"
  if [[ "$CODE" == "$code" ]] && { [[ -z "$motif" ]] || grep -qF -- "$motif" "$T/sortie"; } && eval "$cond"; then ok "$lib"
  else ko "$lib (code $CODE, attendu $code ; motif « $motif » ; condition « $cond »)"; fi
}

META_0031='{"head": "0031", "revisions": ["0030", "0031"]}'

# ===================================================================================================================
echo "== Reprise du déploiement manuel, simulation, premier déploiement"
initialiser
publier v1 "$META_0031"; pointer v1

sync --appliquer
verif "--appliquer refusé sans adoption préalable" 3 "lancer d'abord --adopter"

marquer; sync --adopter
verif "--adopter : déploiement manuel repris" 0 "Aucun conteneur modifié" \
  '[[ "$(jv "$E/etat/active.json" source)" == manuel && "$(jv "$E/etat/active.json" alembic)" == 0031 ]]'
verif "--adopter : aucun conteneur arrêté ni recréé" 0 "" '! appels_depuis | grep -qE "^(stop|compose)"'
verif "--adopter : images manuelles protégées par un tag" 0 "" '[[ "$(lire_py "len(e[\"images\"][\"img-manuel-api\"][\"tags\"])")" == 2 ]]'
verif "--adopter : aucun secret dans l'état" 0 "" '! grep -rqE "secret-de-test|mdp-de-test" "$E/etat"'
sync --adopter
verif "--adopter refusé une seconde fois" 3 "adoption inutile"

marquer; sync --simulation
verif "--simulation : décrit le déploiement" 0 "Simulation terminée : aucun service arrêté"
verif "--simulation : aucun arrêt, aucun démarrage, aucune migration" 0 "" \
  '! appels_depuis | grep -qE "^stop|compose .* up |alembic upgrade|importer$"'
verif "--simulation : version active inchangée" 0 "" '[[ "$(jv "$E/etat/active.json" source)" == manuel && ! -f "$E/etat/rejetee.json" ]]'

marquer; sync --appliquer
verif "--appliquer : v1 déployée et contrôlée" 0 "ACTIVE" \
  '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v1" && "$(jv "$E/etat/precedente.json" source)" == manuel ]]'
verif "v1 : api et purge sur le digest du manifeste" 0 "" \
  '[[ "$(lire_py "e[\"images\"][e[\"conteneurs\"][\"api\"][\"image\"]][\"digests\"][0]")" == "$API_v1" && "$(lire_py "e[\"conteneurs\"][\"purge\"][\"image\"] == e[\"conteneurs\"][\"api\"][\"image\"]")" == True ]]'
verif "v1 : sauvegarde copiée hors VM (db, fichiers, meta)" 0 "Sauvegarde vérifiée" \
  '[[ $(find "$E/gcs/backups" -type f | wc -l) -eq 3 ]]'
verif "v1 : maintenance avant sauvegarde, sauvegarde avant migration" 0 "" \
  'appels_depuis | grep -nE "^stop|pg_dump|alembic upgrade" | awk -F: "{print \$2}" | tr "\n" " " | grep -qE "^stop .*stop .*stop .*exec .*pg_dump.* compose .*alembic upgrade"'

marquer; sync --appliquer
verif "Version déjà active : rien à faire" 0 "déjà active" '! appels_depuis | grep -qE "^(stop|pull)"'

exec 8>"$E/verrou"; flock 8
marquer; sync --appliquer
verif "Verrou : une seconde synchronisation ne s'exécute pas" 0 "déjà en cours" '[[ -z "$(appels_depuis)" ]]'
flock -u 8; exec 8>&-

marquer; sync --restaurer-isole derniere
verif "Restauration isolée de la dernière sauvegarde : conforme" 0 "Restauration isolée de" \
  'grep -q "Empreinte du contenu importé : identique" "$T/sortie" && [[ "$(lire_py "len(e.get(\"restaurations\", {})) + len(e.get(\"volumes_temporaires\", []))")" == 0 ]]'
verif "Restauration isolée : base et services actifs non touchés" 0 "" \
  '! appels_depuis | grep -qE "^(stop|compose)|exec -i m-db|volume rm boussole_(db|fichiers)"'
nom_sauvegarde="$(jv "$E/etat/active.json" sauvegarde)"
printf 'X' >> "$E/gcs/backups/$nom_sauvegarde/db.dump"
marquer; sync --restaurer-isole "$nom_sauvegarde"
verif "Sauvegarde altérée : restauration refusée avant toute création" 3 "non conformes" '! appels_depuis | grep -qE "^(volume|run)"'

# ===================================================================================================================
echo "== Version cassée compatible : retour automatique, puis pas de nouvel essai"
publier v2 '{"head": "0031", "revisions": ["0030", "0031"], "cassee": true}'; pointer v2
sync --appliquer
verif "v2 cassée : retour automatique à v1" 1 "Version précédente" \
  '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v1" && "$(jv "$E/etat/rejetee.json" sha)" == "$SHA_v2" ]]'
verif "v2 cassée : v1 de nouveau en service" 1 "" \
  '[[ "$(lire_py "e[\"images\"][e[\"conteneurs\"][\"api\"][\"image\"]][\"digests\"][0]")" == "$API_v1" ]] && curl -fsS "http://127.0.0.1:$PORT/api/health" | grep -q ok'
marquer; sync --appliquer
verif "v2 rejetée : ignorée au passage suivant" 0 "rejetée précédemment" '! appels_depuis | grep -qE "^(stop|pull)"'

# ===================================================================================================================
echo "== Échec de la sauvegarde : aucune migration"
publier v3 '{"head": "0032", "revisions": ["0030", "0031", "0032"]}'; pointer v3
etat_py "e['dump_ko'] = True"
marquer; sync --appliquer
verif "Sauvegarde impossible : pas de migration, v1 redémarrée" 1 "aucune migration" \
  '[[ "$(lire_py "e[\"db\"][\"revision\"]")" == 0031 && "$(jv "$E/etat/active.json" sha)" == "$SHA_v1" ]] && ! appels_depuis | grep -q "alembic upgrade"'
etat_py "e['dump_ko'] = False"

# ===================================================================================================================
echo "== Migration réussie puis version cassée : retour interdit, intervention requise"
publier v4 '{"head": "0032", "revisions": ["0030", "0031", "0032"], "cassee": true}'; pointer v4
sync --appliquer
verif "v4 : révision changée, retour automatique interdit" 2 "Retour automatique INTERDIT" \
  '[[ -f "$E/etat/intervention-requise.json" && "$(jv "$E/etat/intervention-requise.json" revision_apres)" == 0032 ]]'
verif "v4 : services applicatifs et purge arrêtés" 2 "" \
  '[[ "$(lire_py "[e[\"conteneurs\"][s][\"running\"] for s in (\"api\",\"purge\",\"web\")]")" == "[False, False, False]" ]]'
marquer; sync --appliquer
verif "Intervention requise : aucune action automatique ensuite" 2 "Intervention requise" '[[ -z "$(appels_depuis | grep -vE "^(ps|inspect)")" ]]'

# ===================================================================================================================
echo "== Import qui modifie les données puis version cassée : retour interdit"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v5 '{"head": "0031", "revisions": ["0030", "0031"], "cassee": true, "import_modifie": "E5"}'; pointer v5
sync --appliquer
verif "v5 : données importées modifiées, retour interdit" 2 "données importées modifiées" '[[ -f "$E/etat/intervention-requise.json" ]]'

echo "== Transformation déclarée puis version cassée : retour interdit"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v6 '{"head": "0031", "revisions": ["0030", "0031"], "cassee": true, "transformations": ["recalcul des scores"]}'; pointer v6
sync --appliquer
verif "v6 : transformation déclarée, retour interdit" 2 "transformations déclarées : 1" '[[ -f "$E/etat/intervention-requise.json" ]]'

echo "== Échec de migration avec révision intermédiaire : retour interdit"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v7 '{"head": "0033", "revisions": ["0030", "0031", "0032", "0033"], "migration_ko": true, "rev_partielle": "0032"}'; pointer v7
sync --appliquer
verif "v7 : migration partielle, intervention requise" 2 "migration Alembic en échec" '[[ "$(jv "$E/etat/intervention-requise.json" revision_apres)" == 0032 ]]'

# ===================================================================================================================
echo "== Version incompatible avec la base : refusée sans interruption"
initialiser
publier v1 "$META_0031"; publier v8 '{"head": "0032", "revisions": ["0030", "0031", "0032"]}'; pointer v8
sync --adopter; sync --appliquer
verif "v8 déployée (migration 0031 -> 0032)" 0 "ACTIVE" '[[ "$(lire_py "e[\"db\"][\"revision\"]")" == 0032 ]]'
marquer; sync --version "$SHA_v1"
verif "--version v1 refusée : base en 0032 inconnue de v1" 1 "incompatible avec la base" '! appels_depuis | grep -q "^stop" && [[ ! -f "$E/etat/figee" ]]'

# ===================================================================================================================
echo "== Retour figé, maintien par le timer, reprise du suivi"
initialiser
publier v1 "$META_0031"; publier v9 '{"head": "0031", "revisions": ["0030", "0031"], "import_modifie": "E9"}'; pointer v1
sync --adopter; sync --appliquer; pointer v9; sync --appliquer
verif "v9 déployée après v1" 0 "ACTIVE" '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v9" ]]'
marquer; sync --version "$SHA_v1"
verif "--version v1 : déployée et figée, sans rejouer l'import" 0 "VM figée" \
  '[[ "$(cat "$E/etat/figee")" == "$SHA_v1" && "$(jv "$E/etat/active.json" sha)" == "$SHA_v1" ]] && ! appels_depuis | grep -qE "app.contenu importer$"'
verif "--version v1 : contenu de la base conservé" 0 "" '[[ "$(lire_py "e[\"db\"][\"empreinte\"]")" == E9 ]]'
marquer; sync --appliquer
verif "Timer : version figée maintenue malgré la version publiée v9" 0 "déjà active" '! appels_depuis | grep -qE "^(stop|pull)"'
sync --suivre; sync --appliquer
verif "--suivre puis --appliquer : retour à la version publiée v9" 0 "ACTIVE" '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v9" && ! -f "$E/etat/figee" ]]'

# ===================================================================================================================
echo "== Retour au déploiement manuel"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
sync --retour-manuel
verif "--retour-manuel : images manuelles rétablies et figées" 0 "Déploiement manuel rétabli" \
  '[[ "$(jv "$E/etat/active.json" source)" == manuel && "$(cat "$E/etat/figee")" == manuel && "$(lire_py "e[\"conteneurs\"][\"api\"][\"image\"]")" == img-manuel-api ]]'
marquer; sync --appliquer
verif "Retour manuel figé : le timer ne redéploie pas" 0 "Retour manuel figé" '! appels_depuis | grep -qE "^(stop|pull)"'
initialiser
publier v8 '{"head": "0032", "revisions": ["0030", "0031", "0032"]}'; pointer v8
sync --adopter; sync --appliquer; sync --retour-manuel
verif "--retour-manuel refusé si la révision a changé" 3 "retour impossible sans restauration"

# ===================================================================================================================
echo "== Revue 1 — provenance de l'adoption"
initialiser
sync --adopter
verif "Provenance : commit en place à la construction des images (A), pas le HEAD actuel (B)" 0 "construites le" \
  '[[ "$(jv "$E/etat/active.json" sha)" == "$COMMIT_A" && "$(jv "$E/etat/active.json" commit_depot_actuel)" == "$COMMIT_B" ]]'
initialiser
sync --adopter "$COMMIT_B"
verif "Provenance : commit déclaré (B) contredit par le reflog (A) : adoption refusée" 3 "Provenance incohérente" '[[ ! -f "$E/etat/active.json" ]]'
sync --adopter "$COMMIT_A"
verif "Provenance : commit déclaré confirmé par le reflog : adoption acceptée" 0 "Aucun conteneur modifié"
publier vA "$META_0031" "$COMMIT_A"; pointer vA
sync --appliquer
verif "Version publiée de même SHA que le déploiement manuel : déployée quand même (images différentes)" 0 "ACTIVE" \
  '[[ "$(jv "$E/etat/active.json" source)" == synchro && "$(lire_py "e[\"images\"][e[\"conteneurs\"][\"api\"][\"image\"]][\"digests\"][0]")" == "$API_vA" ]]'
initialiser
etat_py "e['conteneurs']['purge']['image'] = 'img-postgres'"
sync --adopter
verif "Adoption refusée si api et purge n'ont pas la même image" 3 "même image"

# ===================================================================================================================
echo "== Revue 3 — aucune écriture pendant les contrôles"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter
marquer; sync --appliquer
ordre() { appels_depuis | grep -nE "up -d --no-deps api$|run -d --rm --name boussole-controle-web|up -d --no-deps web purge$" | cut -d: -f1 | tr '\n' ' '; }
verif "Ordre : API seule, puis front de contrôle sans port, puis seulement web publié et purge" 0 "Contrôles avant ouverture réussis" \
  '[[ "$(appels_depuis | grep -E "up -d --no-deps api$|run -d --rm --name boussole-controle-web|up -d --no-deps web purge$" | sed -E "s/.*(api|controle-web|web purge).*/\1/" | tr "\n" " ")" == "api controle-web web purge " ]]'
verif "Front de contrôle supprimé après les contrôles" 0 "" '[[ "$(lire_py "len(e.get(\"controles\", {}))")" == 0 ]]'
publier v2 '{"head": "0031", "revisions": ["0030", "0031"], "cassee": true}'; pointer v2
marquer; sync --appliquer
verif "Version cassée : ni purge ni web publié démarrés avec la version candidate" 1 "contrôles avant ouverture en échec" \
  '! appels_depuis | grep -q "images-candidat.env .*up -d --no-deps web purge"'

# ===================================================================================================================
echo "== Revue 2 — conditions du retour automatique"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
python3 - "$E/etat/active.json" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f)); d["alembic"] = "0030"; json.dump(d, open(f, "w"))
PY
publier v2 '{"head": "0031", "revisions": ["0030", "0031"], "cassee": true}'; pointer v2
sync --appliquer
verif "Retour interdit si la version précédente n'attend pas la révision réelle" 2 "attend la révision 0030" '[[ -f "$E/etat/intervention-requise.json" ]]'

initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v3 '{"head": "0031", "revisions": ["0030", "0031"], "echec_publie": true}'; pointer v3
marquer; sync --appliquer
verif "Échec après l'ouverture : retour interdit (écritures possibles), services arrêtés" 2 "après l'ouverture du service" \
  '[[ "$(lire_py "[e[\"conteneurs\"][s][\"running\"] for s in (\"api\",\"purge\",\"web\")]")" == "[False, False, False]" ]] && ! appels_depuis | grep -q "images-relance.env"'

initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v4 '{"head": "0031", "revisions": ["0030", "0031"], "transformations": ["recalcul"]}'; pointer v4
etat_py "e['dump_ko'] = True"
sync --appliquer
verif "Transformation déclarée mais échec avant migration : retour permis" 1 "Version précédente" '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v1" ]]'

# ===================================================================================================================
echo "== Revue 4 — retour manuel sans effets implicites"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
marquer; sync --retour-manuel
verif "Retour manuel : Compose DEV (Uvicorn seul), sans migration, sans import, sans tag" 0 "Déploiement manuel rétabli" \
  'appels_depuis | grep -q "docker-compose.dev.yml up -d --no-deps api$" && ! appels_depuis | grep -qE "^tag |dev-iap.yml|alembic upgrade|app.contenu importer"'
verif "Retour manuel : images adoptées (identifiants) en service, VM figée « manuel » et annoncée" 0 "figée « manuel »" \
  '[[ "$(lire_py "e[\"conteneurs\"][\"api\"][\"image\"]")" == img-manuel-api && "$(cat "$E/etat/figee")" == manuel ]]'
initialiser
publier v9 '{"head": "0031", "revisions": ["0030", "0031"], "import_modifie": "E9"}'; pointer v9
sync --adopter; sync --appliquer
marquer; sync --retour-manuel
verif "Retour manuel refusé si les données importées ont changé (aucun arrêt)" 3 "Données importées différentes" '! appels_depuis | grep -q "^stop"'
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
tag_api="$(jv "$E/etat/adoption/etat-manuel.json" image_locale_api)"   # le tag d'adoption est déplacé sur une autre image
etat_py "e['images']['img-manuel-api']['tags'].remove('$tag_api')" "e['images']['img-postgres']['tags'].append('$tag_api')"
marquer; sync --retour-manuel
verif "Retour manuel refusé si le tag d'adoption ne désigne plus l'image adoptée" 3 "ne désigne plus l'image adoptée" '! appels_depuis | grep -q "^stop"'

# ===================================================================================================================
echo "== Revue 5 — reprise après interruption"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v5 '{"head": "0032", "revisions": ["0030", "0031", "0032"]}'; pointer v5
etat_py "e['tuer_si'] = 'app.contenu importer'"
sync --appliquer
verif "Interruption brutale pendant l'import (après migration 0032)" 137 "" '[[ -f "$E/etat/en-cours.json" && "$(jv "$E/etat/en-cours.json" etape)" == import ]]'
marquer; sync --appliquer
verif "Reprise : cycle interrompu détecté, révision changée : intervention, aucun nouveau déploiement" 2 "cycle interrompu à l'étape import" \
  '[[ -f "$E/etat/intervention-requise.json" && ! -f "$E/etat/en-cours.json" ]] && ! appels_depuis | grep -qE "^pull|alembic upgrade|images-relance.env"'

initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v6 "$META_0031"; pointer v6
etat_py "e['tuer_si'] = 'alembic upgrade'"
sync --appliquer
verif "Interruption brutale au lancement de la migration (rien d'appliqué)" 137 "" '[[ "$(jv "$E/etat/en-cours.json" etape)" == migration ]]'
sync --appliquer
verif "Reprise : base et données inchangées, version précédente rétablie, version rejetée" 1 "Version précédente" \
  '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v1" && "$(jv "$E/etat/rejetee.json" sha)" == "$SHA_v6" && ! -f "$E/etat/en-cours.json" ]] && curl -fsS "http://127.0.0.1:$PORT/api/health" | grep -q ok'

initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter; sync --appliquer
publier v7 "$META_0031"; pointer v7
etat_py "e['tuer_si'] = 'pull -q'"
sync --appliquer
verif "Interruption pendant le préchargement : aucune maintenance commencée" 137 "" '[[ ! -f "$E/etat/en-cours.json" ]]'
sync --appliquer
verif "Reprise après interruption avant maintenance : déploiement normal" 0 "ACTIVE" '[[ "$(jv "$E/etat/active.json" sha)" == "$SHA_v7" ]]'

# ===================================================================================================================
echo "== Manifeste invalide, sécurité, journal"
initialiser
publier v1 "$META_0031"; pointer v1
sync --adopter
python3 - "$E/gcs/releases/$SHA_v1.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); m["images"]["api"] = "docker.io/autre/api@sha256:" + "0" * 64
json.dump(m, open(sys.argv[1], "w"))
PY
marquer; sync --appliquer
verif "Image hors du registre DEV refusée avant tout arrêt" 1 "hors du registre DEV" '! appels_depuis | grep -qE "^(stop|pull)"'
cat "$E/requetes.log" >> "$T/toutes-requetes.log"
CODE=0; verif "Tous scénarios : aucune requête de liste du bucket" 0 "" \
  '[[ -s "$T/toutes-requetes.log" ]] && ! grep -qE "^GET /storage/v1/b/[^/]+/o(\?| )" "$T/toutes-requetes.log"'
CODE=0; verif "Tous scénarios : toutes les requêtes GCS portent le jeton" 0 "" \
  '! grep -E "^(GET|POST) /(upload/)?storage" "$T/toutes-requetes.log" | grep -q "auth=non"'
CODE=0; verif "Ni jeton ni secret dans le journal" 0 "" '! grep -rqE "faux-jeton|secret-de-test|mdp-de-test" "$E/journal.log" "$E/etat"'
if [[ $EUID -ne 0 ]]; then
  CODE=0; env -i PATH="$PATH" bash "$SYNC" --etat > "$T/sortie" 2>&1 || CODE=$?
  verif "Hors banc de test : exécution refusée sans root" 3 "À lancer en root"
else
  echo "(test « refus sans root » ignoré : banc lancé en root)"
fi

echo
echo "$reussis réussi(s), $echecs échec(s)"
[[ $echecs -eq 0 ]]
