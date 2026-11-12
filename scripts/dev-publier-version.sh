#!/usr/bin/env bash
# Publication d'une version DEV (ticket #65, PR 2), appelé par .github/workflows/dev-deploy.yml.
#
#   dev-publier-version.sh existant   # écrit dans $GITHUB_OUTPUT : manifeste=oui|non, api_digest, web_digest déjà publiés
#   dev-publier-version.sh publier    # manifeste immuable releases/<sha>.json puis pointeur releases/desired.json
#
# Règles :
# - Les tags SHA ne sont jamais réécrits : une image déjà publiée pour ce SHA est réutilisée, pas reconstruite.
# - releases/<sha>.json est créé une seule fois (ifGenerationMatch=0) ; s'il existe déjà, il fait foi.
# - releases/desired.json est remplacé uniquement avec ifGenerationMatch=<génération lue>. Si la précondition
#   échoue (écriture concurrente), on relit et on refait le contrôle d'obsolescence : jamais d'écrasement forcé.
# - Une version plus ancienne que la version publiée (ascendance Git) ne remplace jamais le pointeur ;
#   un retour volontaire passe par la procédure de rollback sur la VM.
# - Historique réécrit (versions sans ascendance commune) : échec explicite, décision humaine.
# - Accès GCS objet par objet (API JSON : lecture, métadonnées, écriture conditionnelle), jamais de liste du
#   bucket : le compte de publication n'a pas storage.objects.list (condition IAM limitée aux objets releases/),
#   alors que « gcloud storage cp » liste la destination avant d'écrire.
# Variables : SHA, BUCKET, REGISTRY (+ API_DIGEST, WEB_DIGEST, RUN_URL pour « publier »).
set -Eeuo pipefail

MODE="${1:?mode existant|publier}"
: "${SHA:?}" "${BUCKET:?}" "${REGISTRY:?}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::SHA invalide : $SHA"; exit 1; }
MANIFESTE="gs://$BUCKET/releases/$SHA.json"
POINTEUR="gs://$BUCKET/releases/desired.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# GCS_API n'est substituable qu'en test local (faux serveur) : le jeton d'accès est envoyé à cette adresse.
GCS_API="${GCS_API:-https://storage.googleapis.com}"
if [[ -n "${GITHUB_ACTIONS:-}" && "$GCS_API" != "https://storage.googleapis.com" ]]; then
  echo "::error::GCS_API ne peut pas être redéfini dans GitHub Actions ($GCS_API)"; exit 1
fi
resume() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; printf '%s\n' "$@"; }

# --- Accès GCS par objet (API JSON) -----------------------------------------------------------------
# Les URL gs://<bucket>/<nom> sont converties en appels directs sur l'objet : get (métadonnées ou contenu)
# et insert avec ifGenerationMatch. Aucune de ces opérations ne demande storage.objects.list.
JETON="$(gcloud auth print-access-token)"
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$JETON"
nom_objet() { local u="${1#gs://}"; printf '%s' "${u#*/}"; }
encode() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# gcs_http <sortie> <méthode> <url> [args curl...] : écrit le corps dans <sortie>, affiche le code HTTP.
gcs_http() {
  local sortie="$1" methode="$2" url="$3"; shift 3
  curl -sS --connect-timeout 10 --max-time 60 --retry 3 --retry-connrefused --retry-max-time 120 -X "$methode" -o "$sortie" -w '%{http_code}' \
    -H "Authorization: Bearer $JETON" "$@" "$url"
}

# Génération d'un objet, 0 s'il n'existe pas ; échec franc pour toute autre erreur (droits, réseau).
generation() {
  local code
  code="$(gcs_http "$TMP/meta.json" GET "$GCS_API/storage/v1/b/$BUCKET/o/$(encode "$(nom_objet "$1")")?fields=generation")" || code=000
  case "$code" in
    200) python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["generation"])' "$TMP/meta.json" ;;
    404) echo 0 ;;
    *) echo "::error::Lecture de $1 impossible (HTTP $code) : $(cat "$TMP/meta.json" 2>/dev/null)" >&2; return 1 ;;
  esac
}

# Téléchargement d'un objet existant vers un fichier local.
telecharger() {
  local code
  code="$(gcs_http "$2" GET "$GCS_API/storage/v1/b/$BUCKET/o/$(encode "$(nom_objet "$1")")?alt=media")" || code=000
  [[ "$code" == 200 ]] || { echo "::error::Téléchargement de $1 impossible (HTTP $code) : $(cat "$2" 2>/dev/null)" >&2; return 1; }
}

# Écriture conditionnelle : 0 si écrit, 2 si la précondition de génération a échoué (412), 1 sinon.
televerser() {
  local fichier="$1" url="$2" generation_attendue="$3" code
  code="$(gcs_http "$TMP/reponse.json" POST \
    "$GCS_API/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$(encode "$(nom_objet "$url")")&ifGenerationMatch=$generation_attendue" \
    -H 'Content-Type: application/json' --data-binary "@$fichier")" || code=000
  case "$code" in
    200) return 0 ;;
    412) return 2 ;;
    *) echo "::error::Écriture de $url impossible (HTTP $code) : $(cat "$TMP/reponse.json" 2>/dev/null)" >&2; return 1 ;;
  esac
}

digest_existant() {
  gcloud artifacts docker images describe "$REGISTRY/$1:$SHA" --format='value(image_summary.digest)' 2>/dev/null || true
}

if [[ "$MODE" == existant ]]; then
  gen="$(generation "$MANIFESTE")"
  if [[ "$gen" != 0 ]]; then
    echo "manifeste=oui" >> "$GITHUB_OUTPUT"
    echo "Manifeste déjà publié pour $SHA : aucune reconstruction."
  else
    echo "manifeste=non" >> "$GITHUB_OUTPUT"
  fi
  for img in api web; do
    d="$(digest_existant "$img")"
    echo "${img}_digest=$d" >> "$GITHUB_OUTPUT"
    [[ -n "$d" ]] && echo "Image $img:$SHA déjà publiée ($d) : réutilisée, tag non réécrit."
  done
  exit 0
fi

[[ "$MODE" == publier ]] || { echo "Mode inconnu : $MODE"; exit 2; }

# --- 1. Manifeste immuable ------------------------------------------------------------------------
gen_manifeste="$(generation "$MANIFESTE")"
if [[ "$gen_manifeste" != 0 ]]; then
  telecharger "$MANIFESTE" "$TMP/manifeste.json"
  echo "Manifeste existant conservé (immuable)."
else
  : "${API_DIGEST:?}" "${WEB_DIGEST:?}" "${RUN_URL:?}"
  [[ "$API_DIGEST" =~ ^sha256:[0-9a-f]{64}$ && "$WEB_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "::error::Digests invalides"; exit 1; }
  API_REF="$REGISTRY/api@$API_DIGEST"
  WEB_REF="$REGISTRY/web@$WEB_DIGEST"

  # Révision Alembic attendue par le code de l'image (pas l'état de la base) : une seule tête exigée.
  docker pull -q "$API_REF" >/dev/null
  heads="$(docker run --rm --network none "$API_REF" alembic heads | awk 'NF {print $1}')"
  [[ -n "$heads" ]] || { echo "::error::alembic heads n'a rien renvoyé"; exit 1; }
  [[ "$(wc -l <<<"$heads")" -eq 1 ]] || { echo "::error::Plusieurs têtes Alembic : $heads"; exit 1; }

  # Empreintes Git du contenu importé au démarrage (import pédagogique) : base de la règle de rollback.
  contenu="$(git rev-parse "$SHA:contenu")"
  referentiels="$(git rev-parse "$SHA:referentiels")"

  SHA="$SHA" API_REF="$API_REF" WEB_REF="$WEB_REF" HEAD_ALEMBIC="$heads" CONTENU="$contenu" \
  REFERENTIELS="$referentiels" RUN_URL="$RUN_URL" python3 - > "$TMP/manifeste.json" <<'PY'
import json, os, datetime
print(json.dumps({
    "schema": 1,
    "sha": os.environ["SHA"],
    "publie_le": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "run": os.environ["RUN_URL"],
    "images": {"api": os.environ["API_REF"], "web": os.environ["WEB_REF"]},
    "purge": "api",
    "migration": {"alembic_head_attendue": os.environ["HEAD_ALEMBIC"]},
    "donnees": {
        "contenu_tree": os.environ["CONTENU"],
        "referentiels_tree": os.environ["REFERENTIELS"],
        "transformations_declarees": [],
    },
}, indent=2, ensure_ascii=False))
PY
  rc=0; televerser "$TMP/manifeste.json" "$MANIFESTE" 0 || rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "Manifeste créé entre-temps par une autre exécution : il fait foi."
    telecharger "$MANIFESTE" "$TMP/manifeste.json"
  elif [[ $rc -ne 0 ]]; then
    exit 1
  fi
fi
python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['sha']==sys.argv[2] and m['images']['api'] and m['images']['web']" "$TMP/manifeste.json" "$SHA" \
  || { echo "::error::Manifeste incohérent"; exit 1; }

# --- 2. Pointeur de version, écriture conditionnelle ---------------------------------------------------
for essai in 1 2 3; do
  gen="$(generation "$POINTEUR")"
  if [[ "$gen" != 0 ]]; then
    telecharger "$POINTEUR" "$TMP/desired.json"
    actuel="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['sha'])" "$TMP/desired.json")"
    if [[ "$actuel" == "$SHA" ]]; then resume "Pointeur déjà sur $SHA : rien à faire."; break; fi
    if ! git cat-file -e "$actuel^{commit}" 2>/dev/null; then
      echo "::error::La version publiée $actuel est absente de l'historique (branche réécrite ?). Décision humaine requise : voir docs/exploitation/pipeline-dev-pr2-publication.md"; exit 1
    fi
    if git merge-base --is-ancestor "$SHA" "$actuel"; then
      resume "Version $SHA plus ancienne que la version publiée $actuel : pointeur NON modifié (exécution obsolète)."; break
    fi
    git merge-base --is-ancestor "$actuel" "$SHA" \
      || { echo "::error::$SHA et $actuel n'ont pas d'ascendance directe : décision humaine requise."; exit 1; }
  fi
  SHA="$SHA" RUN_URL="${RUN_URL:-}" python3 - > "$TMP/nouveau.json" <<'PY'
import json, os, datetime
print(json.dumps({"schema": 1, "sha": os.environ["SHA"], "manifeste": f"releases/{os.environ['SHA']}.json",
                  "publie_le": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                  "run": os.environ["RUN_URL"]}, indent=2))
PY
  rc=0; televerser "$TMP/nouveau.json" "$POINTEUR" "$gen" || rc=$?
  if [[ $rc -eq 0 ]]; then
    resume "Pointeur releases/desired.json -> $SHA (génération précédente : $gen)."; break
  fi
  [[ $rc -eq 2 ]] || exit 1
  echo "Écriture concurrente détectée (essai $essai) : relecture et nouveau contrôle."
  [[ $essai -lt 3 ]] || { echo "::error::Pointeur non mis à jour après 3 essais concurrents"; exit 1; }
done

resume "" "### Version DEV publiée (non encore déployée)" "" "| | |" "|---|---|" \
  "| SHA | \`$SHA\` |" \
  "| API | \`$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['images']['api'])" "$TMP/manifeste.json")\` |" \
  "| Web | \`$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['images']['web'])" "$TMP/manifeste.json")\` |" \
  "| Alembic | \`$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['migration']['alembic_head_attendue'])" "$TMP/manifeste.json")\` |" \
  "| Manifeste | \`$MANIFESTE\` |" "" \
  "La VM applique la version au prochain passage de son timer (PR 3). La publication ne prouve pas le déploiement."
