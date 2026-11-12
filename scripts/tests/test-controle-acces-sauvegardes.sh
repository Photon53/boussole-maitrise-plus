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
  env PATH="$T/bin:$PATH" FAUX_GCLOUD_SCENARIO="$T/scenario.json" FAUX_GCLOUD_JOURNAL="$T/journal" \
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

lancer "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_contredit\": [\"$CE|storage.objects.get|$O/backups/temoin\"]}"
verif "Troubleshooter contredit l'analyse (Compute lit une sauvegarde) : non conforme" 1 "CONTRADICTION ou erreur Troubleshooter : CAN_ACCESS"

lancer "{\"bucket\": \"apres\", \"troubleshooter\": true, \"ts_erreur\": [\"$VM|storage.objects.get|$O/backups/temoin\"]}"
verif "Erreur de Troubleshooter sur un contrôle : non conforme, jamais « conforme »" 1 "INVALID_ARGUMENT"

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

echo "$reussis réussi(s), $echecs échec(s)"
[[ $echecs -eq 0 ]]
