#!/usr/bin/env bash
# Issue #8 — Sauvegardes automatisées et restauration testée (Claude)
# Banc de deploy/sauvegarde-prod.sh : faux docker et faux gcloud (aucune base, aucun bucket), vrai age et vrai tar.
# Aucun accès cloud ni root. Usage : bash deploy/sauvegarde/tests/test-sauvegarde-prod.sh
set -Euo pipefail
RACINE="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$RACINE/deploy/sauvegarde-prod.sh"
command -v age >/dev/null && command -v age-keygen >/dev/null || { echo "IGNORÉ : age et age-keygen requis"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/gcs" "$T/deploy" "$T/faux"
cp "$RACINE/deploy/sauvegarde/tests/faux_docker.py" "$T/bin/docker"; chmod +x "$T/bin/docker"
cat > "$T/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
# Faux gcloud : « storage cp [--no-clobber] <source> <destination> » vers ou depuis $FAUX_GCS.
echo "gcloud $*" >> "$FAUX_LOG"
[[ "$1 $2" == "storage cp" ]] || { echo "faux gcloud : appel inattendu $*" >&2; exit 9; }
shift 2; nc=0; [[ "$1" == --no-clobber ]] && { nc=1; shift; }
local_() { echo "$FAUX_GCS/${1#gs://}"; }
[[ -z "${FAUX_GCLOUD_KO:-}" ]] || { echo "ERROR: (gcloud.storage.cp) 403 accès refusé (simulé)" >&2; exit 1; }
if [[ "$2" == gs://* ]]; then d="$(local_ "$2")"; mkdir -p "$(dirname "$d")"; [[ $nc == 1 && -e "$d" ]] && exit 0; cp "$1" "$d"
else s="$(local_ "$1")"; [[ -f "$s" ]] || { echo "ERROR: objet absent" >&2; exit 1; }; cp "$s" "$2"; fi
EOF
chmod +x "$T/bin/gcloud"
age-keygen -o "$T/cle-privee.txt" 2>/dev/null; PUB="$(age-keygen -y "$T/cle-privee.txt")"
age-keygen -o "$T/autre-cle.txt" 2>/dev/null
printf 'services: {}\n' > "$T/deploy/docker-compose.yml"
printf 'PKP_SECRET_KEY=valeur-secrete-de-test-123\nPKP_DB_MOT_DE_PASSE=mdp-secret-de-test-456\nPKP_DOMAINE=exemple.fr\n' > "$T/deploy/.env"
ecrire_config() {
  cat > "$T/config" <<EOF
DEPLOY=$T/deploy
DESTINATION=${1:-gs://boussole-sauvegardes-test/production}
SITE=gcp
AGE_DESTINATAIRES="${2-$PUB}"
GARDER_LOCAL=2
AGE_MAX_HEURES=26
EOF
}
lancer() {   # lancer <arguments…> : sortie dans $T/sortie, code renvoyé
  env PATH="$T/bin:$PATH" BOUSSOLE_SAUVEGARDE_TEST=1 CONFIG="$T/config" ETAT="$T/etat" JOURNAL="$T/journal.log" \
    VERROU="$T/verrou" FAUX_ETAT="$T/faux" FAUX_LOG="$T/appels.log" FAUX_GCS="$T/gcs" "${ENV_SUP[@]}" \
    bash "$SCRIPT" "$@" > "$T/sortie" 2>&1
  echo $?
}
ENV_SUP=(); reussis=0; echecs=0
verif() {   # verif <libellé> <code attendu> <code obtenu> <condition bash>
  if [[ "$3" == "$2" ]] && eval "$4"; then echo "OK    $1"; reussis=$((reussis + 1))
  else echo "ECHEC $1 (code $3, attendu $2)"; sed 's/^/      /' "$T/sortie"; echecs=$((echecs + 1)); fi
}
objets() { find "$T/gcs" -type f -name '*.tar.age' | sort; }
derniere() { objets | tail -1; }

# --- Configuration -----------------------------------------------------------------------------------------
ecrire_config
verif "--verifier : configuration conforme" 0 "$(lancer --verifier)" 'grep -q "Configuration conforme" "$T/sortie"'
ecrire_config "gs://boussole-sauvegardes-test/production" "age1pasunecle"
verif "clé publique invalide : refus" 3 "$(lancer --sauvegarder)" 'grep -q "pas une clé publique age" "$T/sortie" && [[ -z "$(objets)" ]]'
ecrire_config "gs://boussole-sauvegardes-test/production" ""
verif "aucune clé publique : refus" 3 "$(lancer --sauvegarder)" 'grep -q "AGE_DESTINATAIRES vide" "$T/sortie"'
ecrire_config "/tmp/pas-un-bucket"
verif "destination hors GCS : refus" 3 "$(lancer --sauvegarder)" 'grep -q "DESTINATION invalide" "$T/sortie"'
ecrire_config
verif "motif inconnu : refus" 3 "$(lancer --sauvegarder --motif nimporte)" 'grep -q "Motif invalide" "$T/sortie"'
verif "--etat sans aucune sauvegarde : alerte" 1 "$(lancer --etat)" 'grep -q "aucune sauvegarde réussie" "$T/sortie"'

# --- Sauvegarde réussie --------------------------------------------------------------------------------------
verif "sauvegarde quotidienne chiffrée et copiée hors VM" 0 "$(lancer --sauvegarder)" \
  '[[ "$(objets | wc -l)" == 1 ]] && grep -q "copiée hors VM" "$T/sortie" && [[ "$(derniere)" == */production/gcp/*-quotidienne.tar.age ]]'
verif "l'objet est chiffré : aucun secret ni dump lisible" 0 0 \
  '! grep -qaE "valeur-secrete|mdp-secret|PGDMP" "$(derniere)" && head -c 40 "$(derniere)" | grep -qa "age-encryption.org"'
verif "envoi sans écrasement (--no-clobber)" 0 0 'grep -q "storage cp --no-clobber" "$T/appels.log"'
verif "aucun fichier en clair sur la VM après exécution" 0 0 \
  '[[ -z "$(find "$T/etat" -type f ! -name "*.tar.age" ! -name "*.json")" ]] && [[ -z "$(find "$T/etat" -name "travail.*")" ]]'
verif "journaux et état sans secret" 0 0 '! grep -rqE "valeur-secrete|mdp-secret" "$T/journal.log" "$T/etat"/*.json "$T/sortie"'
mkdir -p "$T/dechiffre"; age -d -i "$T/cle-privee.txt" "$(derniere)" | tar -C "$T/dechiffre" -xf -
verif "contenu : dump, PDF, .env et manifeste" 0 0 \
  '[[ -s "$T/dechiffre/db.dump" && -s "$T/dechiffre/fichiers.tar.gz" ]] && cmp -s "$T/dechiffre/env" "$T/deploy/.env" && tar -tzf "$T/dechiffre/fichiers.tar.gz" | grep -q ressource-1.pdf'
verif "manifeste : révision, comptages, sommes ; aucun prénom ni e-mail" 0 0 \
  'python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m[\"revision_alembic\"]==\"0038\" and m[\"comptages\"][\"eleve\"]==57 and set(m[\"fichiers\"])=={\"db.dump\",\"fichiers.tar.gz\",\"env\"}" "$T/dechiffre/manifeste.json" && ! grep -qE "@|valeur-secrete" "$T/dechiffre/manifeste.json"'
verif "--etat après succès : à jour" 0 "$(lancer --etat)" 'grep -q "Dernière sauvegarde réussie" "$T/sortie" && ! grep -q ALERTE "$T/sortie"'
verif "sauvegarde avant déploiement : motif dans le nom" 0 "$(lancer --sauvegarder --motif avant-deploiement)" \
  '[[ "$(derniere)" == *-avant-deploiement.tar.age || -n "$(objets | grep avant-deploiement)" ]]'
sleep 1; lancer --sauvegarder >/dev/null; sleep 1; lancer --sauvegarder >/dev/null
verif "rétention locale : GARDER_LOCAL archives chiffrées seulement" 0 0 '[[ "$(find "$T/etat/archives" -name "*.tar.age" | wc -l)" == 2 ]]'

# --- Échecs de sauvegarde ------------------------------------------------------------------------------------
n_avant="$(objets | wc -l)"
ENV_SUP=(FAUX_PG_DUMP_KO=1)
verif "pg_dump en échec : code 1, rien envoyé" 1 "$(lancer --sauvegarder)" '[[ "$(objets | wc -l)" == "$n_avant" ]] && grep -q "pg_dump a échoué" "$T/sortie"'
verif "--etat après un échec : alerte" 1 "$(lancer --etat)" 'grep -q "ALERTE : la dernière exécution a échoué" "$T/sortie"'
ENV_SUP=(FAUX_API_KO=1)
verif "service api arrêté : échec explicite" 1 "$(lancer --sauvegarder)" 'grep -q "Archive des fichiers (PDF) impossible" "$T/sortie"'
ENV_SUP=(FAUX_DB_KO=1)
verif "base injoignable : échec explicite" 1 "$(lancer --sauvegarder)" 'grep -q "Base de production injoignable" "$T/sortie"'
ENV_SUP=(FAUX_GCLOUD_KO=1)
verif "copie hors VM refusée : échec, état en échec" 1 "$(lancer --sauvegarder)" \
  'grep -q "Copie hors VM impossible" "$T/sortie" && grep -q "\"statut\": \"echec\"" "$T/etat/derniere.json"'
verif "échec : aucun fichier en clair laissé" 0 0 '[[ -z "$(find "$T/etat" -name "travail.*")" ]]'
ENV_SUP=()
exec 8>"$T/verrou"; flock 8
verif "verrou : deux exécutions simultanées refusées" 3 "$(lancer --sauvegarder)" 'grep -q "autre exécution" "$T/sortie"'
exec 8>&-
lancer --sauvegarder >/dev/null
python3 - "$T/etat/derniere-reussie.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); m["le"] = "2020-01-01T00:00:00Z"; json.dump(m, open(sys.argv[1], "w"))
PY
verif "--etat : sauvegarde trop ancienne signalée" 1 "$(lancer --etat)" 'grep -q "plus vieille que 26 h" "$T/sortie"'

# --- Restauration isolée -------------------------------------------------------------------------------------
OBJ="gs://$(derniere | sed "s|^$T/gcs/||")"
: > "$T/appels.log"
verif "restauration isolée depuis le bucket : conforme" 0 "$(lancer --restaurer-isole "$OBJ" --identite "$T/cle-privee.txt")" \
  'grep -q "Restauration isolée conforme" "$T/sortie" && grep -q "eleve.*57.*57" "$T/sortie"'
verif "base temporaire sans réseau ni port, puis supprimée" 0 0 \
  'grep -q "run -d --name boussole-restauration-.* --network none" "$T/appels.log" && grep -q "^rm -f boussole-restauration-" "$T/appels.log" && grep -q "^volume rm boussole-restauration-" "$T/appels.log"'
verif "restauration : aucune écriture dans la production" 0 0 '! grep -qE "^compose" "$T/appels.log"'
verif "restauration : noms des variables du .env, jamais les valeurs" 0 0 \
  'grep -q "PKP_SECRET_KEY" "$T/sortie" && ! grep -qE "valeur-secrete|mdp-secret" "$T/sortie"'
verif "restauration avec une autre clé : refus de déchiffrer" 1 "$(lancer --restaurer-isole "$OBJ" --identite "$T/autre-cle.txt")" \
  'grep -q "Déchiffrement impossible" "$T/sortie"'
ENV_SUP=(FAUX_RESTAURE_DIFF=1)
verif "comptages différents après restauration : non conforme" 1 "$(lancer --restaurer-isole "$OBJ" --identite "$T/cle-privee.txt")" \
  'grep -q "NON conforme" "$T/sortie"'
ENV_SUP=(FAUX_RESTORE_KO=1)
verif "pg_restore en échec : non conforme, nettoyage fait" 1 "$(lancer --restaurer-isole "$OBJ" --identite "$T/cle-privee.txt")" \
  'grep -q "pg_restore a échoué" "$T/sortie" && [[ ! -e "$T/faux/temporaire.json" ]]'
ENV_SUP=()
cp "$(derniere)" "$T/altere.tar.age"; printf 'x' >> "$T/altere.tar.age"
verif "archive altérée : refus (age authentifie le contenu)" 1 "$(lancer --restaurer-isole "$T/altere.tar.age" --identite "$T/cle-privee.txt")" \
  'grep -q "Déchiffrement impossible" "$T/sortie"'

echo "$reussis réussi(s), $echecs échec(s)"
[[ $echecs -eq 0 ]]
