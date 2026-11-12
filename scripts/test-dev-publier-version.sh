#!/usr/bin/env bash
# Test local de scripts/dev-publier-version.sh (mode « publier ») contre un faux serveur GCS (ticket #65).
# Aucun accès GCP : gcloud et docker sont simulés, le serveur refuse toute liste du bucket (403).
# Usage : bash scripts/test-dev-publier-version.sh
set -Eeuo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/dev-publier-version.sh"
T="$(mktemp -d)"
SERVEUR=""
trap '[[ -n "$SERVEUR" ]] && kill "$SERVEUR" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/depot"
echos=0; echecs=0

# --- Faux GCS : get (métadonnées / alt=media), insert avec ifGenerationMatch ; liste refusée -------------
cat > "$T/faux_gcs.py" <<'PY'
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
objets, generation = {}, [1000]
journal = open(sys.argv[2], "a")
course = sys.argv[3] if len(sys.argv) > 3 else ""   # SHA écrit par un « autre run » au 1er insert du pointeur
class H(BaseHTTPRequestHandler):
    course_faite = False
    def log_message(self, *a): pass
    def repondre(self, code, corps=b"{}"):
        self.send_response(code); self.send_header("Content-Length", str(len(corps))); self.end_headers(); self.wfile.write(corps)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        journal.write(f"GET {self.path}\n"); journal.flush()
        if u.path.rstrip("/").endswith("/o"):
            return self.repondre(403, b'{"error":"storage.objects.list refuse"}')
        nom = urllib.parse.unquote(u.path.split("/")[-1])
        if nom not in objets: return self.repondre(404, b'{"error":"Not Found"}')
        g, d = objets[nom]
        if q.get("alt") == ["media"]: return self.repondre(200, d)
        self.repondre(200, json.dumps({"generation": str(g)}).encode())
    def do_POST(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        journal.write(f"POST {self.path}\n"); journal.flush()
        nom, attendu = q["name"][0], int(q["ifGenerationMatch"][0])
        d = self.rfile.read(int(self.headers["Content-Length"]))
        if course and nom.endswith("desired.json") and not H.course_faite:
            H.course_faite = True; generation[0] += 1
            objets[nom] = (generation[0], json.dumps({"sha": course}).encode())
        if objets.get(nom, (0, b""))[0] != attendu: return self.repondre(412, b'{"error":"conditionNotMet"}')
        generation[0] += 1; objets[nom] = (generation[0], d)
        self.repondre(200, json.dumps({"generation": str(generation[0])}).encode())
s = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port))
s.serve_forever()
PY

printf '#!/bin/sh\n[ "$1 $2" = "auth print-access-token" ] && echo faux-jeton && exit 0\necho "gcloud inattendu : $*" >&2; exit 9\n' > "$T/bin/gcloud"
printf '#!/bin/sh\n[ "$1" = run ] && echo "abc123 (head)"\nexit 0\n' > "$T/bin/docker"
chmod +x "$T/bin/gcloud" "$T/bin/docker"

# --- Dépôt Git jetable : deux versions successives avec contenu/ et referentiels/ -----------------------
cd "$T/depot"
git init -q && git config user.email test@example.invalid && git config user.name test
mkdir contenu referentiels
echo 1 > contenu/a && echo 1 > referentiels/a && git add . && git commit -qm v1 && ANCIEN="$(git rev-parse HEAD)"
echo 2 > contenu/a && git commit -qam v2 && RECENT="$(git rev-parse HEAD)"

demarrer() {   # demarrer [sha_concurrent]
  [[ -n "$SERVEUR" ]] && kill "$SERVEUR" 2>/dev/null; rm -f "$T/port"; : > "$T/requetes.log"
  python3 "$T/faux_gcs.py" "$T/port" "$T/requetes.log" "${1:-}" & SERVEUR=$!
  for _ in $(seq 50); do [[ -s "$T/port" ]] && break; sleep 0.1; done
  PORT="$(cat "$T/port")"
}
publier() {   # publier <sha> [url_api] -> sortie dans $T/sortie, code dans $CODE
  CODE=0
  env -u GITHUB_ACTIONS -u GITHUB_STEP_SUMMARY PATH="$T/bin:$PATH" GCS_API="${2:-http://127.0.0.1:$PORT}" \
    BUCKET=b REGISTRY=r RUN_URL=u SHA="$1" \
    API_DIGEST="sha256:$(printf 'a%.0s' {1..64})" WEB_DIGEST="sha256:$(printf 'b%.0s' {1..64})" \
    bash "$SCRIPT" publier > "$T/sortie" 2>&1 || CODE=$?
}
verifier() {   # verifier <libellé> <code attendu> <motif attendu dans la sortie>
  if [[ "$CODE" == "$2" ]] && grep -q -- "$3" "$T/sortie"; then echo "OK    $1"; echos=$((echos+1))
  else echo "ECHEC $1 (code $CODE, attendu $2 ; motif « $3 »)"; sed 's/^/      /' "$T/sortie"; echecs=$((echecs+1)); fi
}

demarrer
publier "$ANCIEN";  verifier "première publication" 0 "Pointeur releases/desired.json -> $ANCIEN (génération précédente : 0)"
publier "$RECENT";  verifier "version plus récente" 0 "Pointeur releases/desired.json -> $RECENT"
publier "$RECENT";  verifier "relance identique" 0 "Pointeur déjà sur $RECENT : rien à faire"
publier "$ANCIEN";  verifier "exécution obsolète" 0 "pointeur NON modifié"
if grep -qE 'GET /storage/v1/b/[^/]+/o(\?|$)' "$T/requetes.log"; then
  echo "ECHEC aucune liste du bucket"; echecs=$((echecs+1)); else echo "OK    aucune liste du bucket"; echos=$((echos+1)); fi

demarrer "$ANCIEN"
publier "$RECENT";  verifier "écriture concurrente du pointeur (412)" 0 "Écriture concurrente détectée"

publier "$RECENT" "http://127.0.0.1:9"; verifier "serveur injoignable" 1 "impossible (HTTP 000)"

CODE=0; env GITHUB_ACTIONS=true PATH="$T/bin:$PATH" GCS_API="http://127.0.0.1:$PORT" BUCKET=b REGISTRY=r SHA="$RECENT" \
  bash "$SCRIPT" publier > "$T/sortie" 2>&1 || CODE=$?
verifier "GCS_API imposé dans GitHub Actions" 1 "GCS_API ne peut pas être redéfini"

echo "$echos réussi(s), $echecs échec(s)"
[[ $echecs -eq 0 ]]
