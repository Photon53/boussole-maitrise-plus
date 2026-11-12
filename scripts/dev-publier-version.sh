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
# Variables : SHA, BUCKET, REGISTRY (+ API_DIGEST, WEB_DIGEST, RUN_URL pour « publier »).
set -Eeuo pipefail

MODE="${1:?mode existant|publier}"
: "${SHA:?}" "${BUCKET:?}" "${REGISTRY:?}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::SHA invalide : $SHA"; exit 1; }
MANIFESTE="gs://$BUCKET/releases/$SHA.json"
POINTEUR="gs://$BUCKET/releases/desired.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
resume() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; printf '%s\n' "$@"; }

# Génération d'un objet, 0 s'il n'existe pas ; échec franc pour toute autre erreur (droits, réseau).
generation() {
  local sortie
  if sortie="$(gcloud storage objects describe "$1" --format='value(generation)' 2>&1)"; then echo "$sortie"; return; fi
  if grep -qiE '404|not found|No URLs matched' <<<"$sortie"; then echo 0; return; fi
  echo "::error::Lecture de $1 impossible : $sortie" >&2; return 1
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
if [[ "$(generation "$MANIFESTE")" != 0 ]]; then
  gcloud storage cp "$MANIFESTE" "$TMP/manifeste.json" --quiet
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
  if ! gcloud storage cp "$TMP/manifeste.json" "$MANIFESTE" --if-generation-match=0 --content-type=application/json --quiet 2>"$TMP/err"; then
    grep -qiE '412|precondition' "$TMP/err" || { cat "$TMP/err"; exit 1; }
    echo "Manifeste créé entre-temps par une autre exécution : il fait foi."
    gcloud storage cp "$MANIFESTE" "$TMP/manifeste.json" --quiet
  fi
fi
python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['sha']==sys.argv[2] and m['images']['api'] and m['images']['web']" "$TMP/manifeste.json" "$SHA" \
  || { echo "::error::Manifeste incohérent"; exit 1; }

# --- 2. Pointeur de version, écriture conditionnelle ---------------------------------------------------
for essai in 1 2 3; do
  gen="$(generation "$POINTEUR")"
  if [[ "$gen" != 0 ]]; then
    gcloud storage cp "$POINTEUR" "$TMP/desired.json" --quiet
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
  if gcloud storage cp "$TMP/nouveau.json" "$POINTEUR" --if-generation-match="$gen" --content-type=application/json --quiet 2>"$TMP/err"; then
    resume "Pointeur releases/desired.json -> $SHA (génération précédente : $gen)."; break
  fi
  grep -qiE '412|precondition' "$TMP/err" || { cat "$TMP/err"; exit 1; }
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
