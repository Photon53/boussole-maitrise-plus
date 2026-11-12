#!/usr/bin/env bash
# Banc de scripts/controle-acces-sauvegardes.sh (ticket #65), sans accès GCP : faux gcloud piloté par scénario.
# Usage : bash scripts/tests/test-controle-acces-sauvegardes.sh
set -Euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ICI/../controle-acces-sauvegardes.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
printf '#!/bin/sh\nexec python3 %q "$@"\n' "$ICI/faux_gcloud_acces.py" > "$T/bin/gcloud"; chmod +x "$T/bin/gcloud"
reussis=0; echecs=0
P=mer-boussole-dev; NUM=948330391026; O="projects/_/buckets/$P-deploiement/objects"
CE="$NUM-compute@developer.gserviceaccount.com"; VM="boussole-dev-vm@$P.iam.gserviceaccount.com"

lancer() {   # lancer <scénario JSON> : sortie dans $T/sortie, code dans $CODE
  printf '%s' "$1" > "$T/scenario.json"; : > "$T/journal"
  CODE=0
  env PATH="$T/bin:$PATH" HOME="$T" FAUX_GCLOUD_SCENARIO="$T/scenario.json" FAUX_GCLOUD_JOURNAL="$T/journal" \
    bash "$SCRIPT" > "$T/sortie" 2>&1 || CODE=$?
}
verif() {   # verif <libellé> <code attendu> <motif attendu>
  if [[ "$CODE" == "$2" ]] && grep -qF -- "$3" "$T/sortie" && ! grep -qE "^services enable" "$T/journal"; then
    echo "OK    $1"; reussis=$((reussis + 1))
  else
    echo "ECHEC $1 (code $CODE, attendu $2 ; motif « $3 »)"; sed 's/^/      | /' "$T/sortie" | tail -25; echecs=$((echecs + 1))
  fi
}

lancer '{"bucket": "apres"}'
verif "Troubleshooter non activé : conforme selon les politiques SEULEMENT (code 3, pas une preuve)" 3 "NON CONFIRMÉ par Policy Troubleshooter"
verif "Exception D5 : tf-plan liste les objets (iam.securityReviewer), affichée comme acceptée" 3 "lister objets et métadonnées         D5        ACCORDÉ      —              OK exception D5 acceptée"
verif "Exception D5 : résumé explicite, lecture du contenu refusée" 3 "Exception D5 acceptée : boussole-dev-tf-plan peut lister les objets du bucket et leurs métadonnées"

lancer '{"bucket": "apres", "sans_liste_tf": true}'
verif "Droits réduits (option B) : liste refusée, exception D5 non utilisée, toujours conforme" 3 "exception D5 non utilisée (liste refusée)"

lancer '{"bucket": "apres", "tf_lecteur_projet": true}'
verif "tf-plan peut LIRE le contenu (rôle au niveau du projet) : non conforme, exception D5 invalide" 1 "Exception D5 INVALIDE"

lancer '{"bucket": "apres", "troubleshooter": true}'
verif "Troubleshooter activé et cohérent : conforme et confirmé (code 0)" 0 "confirmé par Policy Troubleshooter pour chaque contrôle"

lancer '{"bucket": "apres", "troubleshooter": true, "ts_style": "v1"}'
verif "Troubleshooter au format v1 (access : GRANTED / NOT_GRANTED) : conforme et confirmé" 0 "confirmé par Policy Troubleshooter pour chaque contrôle"

lancer '{"bucket": "apres", "troubleshooter": true, "ts_style": "sans_etat"}'
verif "Réponse Troubleshooter sans état d'accès : INCOMPATIBLE (format inattendu, clés reçues), jamais conforme" 1 "Troubleshooter INCOMPATIBLE : format inattendu : état d'accès absent (clés reçues : accessTuple, explainedPolicies)"
if [[ "$(wc -l < "$T/controle-acces-troubleshooter.jsonl")" -eq 16 ]]; then
  echo "OK    Réponses brutes de Troubleshooter conservées pour diagnostic (16)"; reussis=$((reussis + 1))
else echo "ECHEC journal de diagnostic Troubleshooter absent ou incomplet"; echecs=$((echecs + 1)); fi

lancer "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_contredit\": [\"$CE|storage.objects.get|$O/backups/temoin\"]}"
verif "Troubleshooter contredit l'analyse (Compute lit une sauvegarde) : non conforme" 1 "CONTRADICTION : Troubleshooter ACCORDÉ, analyse REFUSÉ"

lancer "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_erreur\": [\"$VM|storage.objects.get|$O/backups/temoin\"]}"
verif "Erreur de Troubleshooter sur un contrôle : ERREUR d'API, non conforme, jamais « conforme »" 1 "Troubleshooter ERREUR : erreur d'API (code 1)"

lancer "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_inconnu\": [\"$CE|storage.objects.delete|$O/backups/temoin\"]}"
verif "Troubleshooter indéterminé (UNKNOWN_CONDITIONAL) : non conforme" 1 "UNKNOWN_CONDITIONAL"

lancer '{"bucket": "apres", "ancetres": [{"type": "organization", "id": "111", "refus": [{"name": "policies/refus-test"}]}]}'
verif "Politique de refus de l'ORGANISATION : accès accordés rendus indéterminés" 1 "politique(s) de refus présente(s) (organisation 111)"

lancer '{"bucket": "apres", "ancetres": [{"type": "folder", "id": "222", "refus_illisible": true}, {"type": "organization", "id": "111"}]}'
verif "Politiques de refus du DOSSIER illisibles : lecture incomplète" 1 "[INCOMPLET] Politiques de refus (dossier 222)"

lancer "{\"bucket\": \"apres\", \"ancetres\": [{\"type\": \"folder\", \"id\": \"222\", \"autorisations\": [{\"role\": \"roles/storage.objectViewer\", \"members\": [\"serviceAccount:$CE\"]}]}]}"
verif "Autorisation héritée d'un DOSSIER parent : accès indu détecté" 1 "roles/storage.objectViewer (dossier 222)"

lancer '{"bucket": "avant"}'
verif "Ancienne politique (liaisons historiques) : 5 écarts (lectures et suppressions indues)" 1 "5 écarts"

lancer '{"bucket": "apres", "groupe_bucket": true}'
verif "Liaison à un groupe sur le bucket : indéterminé, jamais compté comme refus" 1 "appartenance non vérifiable"

lancer '{"bucket": "apres", "ancetres": [{"type": "organization", "id": "111"}]}'
verif "Organisation sans refus ni autorisation : politiques lues à tous les niveaux, conforme (code 3)" 3 "CONFORME SELON L'ANALYSE"
if grep -q "iam policies list --attachment-point=cloudresourcemanager.googleapis.com%2Forganizations%2F111" "$T/journal" \
   && grep -q "iam policies list --attachment-point=cloudresourcemanager.googleapis.com%2Fprojects%2F$P" "$T/journal"; then
  echo "OK    Politiques de refus lues pour le projet ET l'organisation"; reussis=$((reussis + 1))
else echo "ECHEC politiques de refus non lues à tous les niveaux"; cat "$T/journal"; echecs=$((echecs + 1)); fi

# --- Mode diagnostic : un seul appel ---------------------------------------------------------------------------
DIAG_CIBLE="$VM|storage.objects.get|$O/releases/desired.json"
diag() {   # diag <scénario JSON> : sortie dans $T/sortie, code dans $CODE
  printf '%s' "$1" > "$T/scenario.json"; : > "$T/journal"; rm -f "$T/diagnostic-troubleshooter.json"
  CODE=0
  env PATH="$T/bin:$PATH" HOME="$T" FAUX_GCLOUD_SCENARIO="$T/scenario.json" FAUX_GCLOUD_JOURNAL="$T/journal" \
    bash "$SCRIPT" --diagnostic-troubleshooter > "$T/sortie" 2>&1 || CODE=$?
}
un_appel() { [[ "$(grep -c '^policy-troubleshoot iam' "$T/journal")" == 1 ]]; }
rapport() { python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$T/diagnostic-troubleshooter.json" "$1"; }
verif_diag() {   # verif_diag <libellé> <code> <motif> [condition]
  if [[ "$CODE" == "$2" ]] && grep -qF -- "$3" "$T/sortie" && eval "${4:-true}" && ! grep -qE "^services enable" "$T/journal"; then
    echo "OK    $1"; reussis=$((reussis + 1))
  else
    echo "ECHEC $1 (code $CODE, attendu $2 ; motif « $3 »)"; sed 's/^/      | /' "$T/sortie" | tail -20; echecs=$((echecs + 1))
  fi
}

diag '{"bucket": "apres"}'
verif_diag "Diagnostic, API non activée : aucun appel, code 4" 4 "AUCUN appel effectué" '! grep -q "^policy-troubleshoot" "$T/journal" && [[ ! -e "$T/diagnostic-troubleshooter.json" ]]'

diag '{"bucket": "apres", "troubleshooter": true}'
verif_diag "Diagnostic v3 : un seul appel, réponse compatible, accès accordé (code 0)" 0 "Classement : ACCORDÉ — CAN_ACCESS" \
  'un_appel && [[ "$(rapport "r[\"code_sortie\"]")" == 0 && "$(rapport "r[\"classement\"]")" == ACCORDÉ ]]'
verif_diag "Diagnostic : rapport en mode 600 avec réponse JSON brute, erreurs, code et version de gcloud" 0 "" \
  '[[ "$(stat -c %a "$T/diagnostic-troubleshooter.json")" == 600 ]] && rapport "sorted(r)" | grep -q "reponse_json_brute" && rapport "r[\"version_gcloud\"]" | grep -q 999.0.0-faux && rapport "\"erreurs_brutes\" in r" | grep -q True'
verif_diag "Diagnostic : structure affichée sans adresse (clés, types, valeur d'état seulement)" 0 "overallAccessState : « CAN_ACCESS »" \
  '! grep -q "@" <(sed -n "/^Structure/,/^Rapport/p" "$T/sortie")'

diag '{"bucket": "apres", "troubleshooter": true, "ts_style": "v1"}'
verif_diag "Diagnostic v1 (access : GRANTED) : compatible (code 0)" 0 "Classement : ACCORDÉ — GRANTED" 'un_appel'

diag '{"bucket": "apres", "troubleshooter": true, "ts_style": "sans_etat"}'
verif_diag "Diagnostic : état absent = FORMAT INATTENDU (code 5), clés reçues listées" 5 "format inattendu : état d'accès absent (clés reçues : accessTuple, explainedPolicies)" 'un_appel'

diag '{"bucket": "apres", "troubleshooter": true, "ts_style": "texte"}'
verif_diag "Diagnostic : réponse non JSON = FORMAT INATTENDU (code 5)" 5 "format inattendu : réponse non JSON" 'un_appel'

diag '{"bucket": "apres", "troubleshooter": true, "ts_style": "valeur_inconnue"}'
verif_diag "Diagnostic : valeur d'état inconnue = FORMAT INATTENDU (code 5)" 5 "valeur d'état inconnue « NOUVEL_ETAT »" 'un_appel'

diag "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_erreur\": [\"$DIAG_CIBLE\"]}"
verif_diag "Diagnostic : appel en échec = ERREUR D'API (code 6), erreurs conservées" 6 "ERREUR D'API" \
  'un_appel && rapport "r[\"erreurs_brutes\"]" | grep -q INVALID_ARGUMENT && [[ "$(rapport "r[\"code_sortie\"]")" != 0 ]]'

diag "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_contredit\": [\"$DIAG_CIBLE\"]}"
verif_diag "Diagnostic : réponse compatible CANNOT_ACCESS = VÉRITABLE REFUS (code 7)" 7 "VÉRITABLE REFUS" 'un_appel'

diag "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_inconnu\": [\"$DIAG_CIBLE\"]}"
verif_diag "Diagnostic : UNKNOWN_CONDITIONAL = non concluant (code 8)" 8 "non concluante" 'un_appel'

diag '{"bucket": "apres", "troubleshooter": true, "ts_style": "fuite_jeton"}'
verif_diag "Diagnostic : jeton masqué dans l'affichage et le rapport" 0 "[JETON MASQUÉ]" \
  '! grep -q "ya29.JETON-SECRET" "$T/sortie" "$T/diagnostic-troubleshooter.json"'

lancer '{"bucket": "apres", "troubleshooter": true, "ts_style": "fuite_jeton"}'
verif "Contrôle complet : jeton masqué dans le journal de diagnostic" 0 "confirmé par Policy Troubleshooter" 
if grep -q "ya29.JETON-SECRET" "$T/controle-acces-troubleshooter.jsonl" "$T/sortie"; then
  echo "ECHEC jeton présent dans le journal du contrôle complet"; echecs=$((echecs + 1))
else echo "OK    Contrôle complet : aucun jeton dans le journal ni la sortie"; reussis=$((reussis + 1)); fi

echo "$reussis réussi(s), $echecs échec(s)"
[[ $echecs -eq 0 ]]
