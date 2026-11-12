#!/usr/bin/env bash
# Boussole Maîtrise+ — séparation des autorisations WIF par compte de service (tickets #63 et #65, PR 1).
# À lancer dans Cloud Shell par le propriétaire du projet DEV. Chaque modification demande « OUI ».
#
#   bash scripts/wif-dev-comptes-separes.sh audit     # lecture seule : état actuel et écarts
#   bash scripts/wif-dev-comptes-separes.sh etape1    # droits de lecture de tf-plan + nouveau fournisseur + liaison par rôle
#                                                      # (l'ancienne liaison « tout le dépôt » est CONSERVÉE)
#   -> lancer « GCP DEV Terraform » sur develop : le PLAN doit réussir
#   bash scripts/wif-dev-comptes-separes.sh etape2    # retire l'ancienne liaison attribute.repository de tf-plan
#   -> relancer « GCP DEV Terraform » : le PLAN doit toujours réussir
#   bash scripts/wif-dev-comptes-separes.sh verifier  # contrôle final, lecture seule
#
# Modèle cible :
#   Condition du fournisseur : dépôt n° 1449363568, refs/heads/develop, environnement « development »,
#   et l'un des deux workflows autorisés (Terraform en workflow_dispatch ; dev-deploy en push ou workflow_dispatch).
#   Attribut attribute.boussole_role calculé par le fournisseur : « tf-plan », « deployer » ou « aucun ».
#   boussole-dev-tf-plan  <- principalSet …/attribute.boussole_role/tf-plan   (ce script)
#   boussole-dev-deployer <- principalSet …/attribute.boussole_role/deployer  (Terraform, pipeline.tf)
#   => refus croisés : le workflow Terraform ne peut pas emprunter le déployeur, et réciproquement.
# Aucune ressource PROD n'est touchée. Aucune clé de compte de service n'est créée.
set -Eeuo pipefail

PROJECT="mer-boussole-dev"
POOL="github-dev"
PROVIDER="github"
REPO="Photon53/boussole-maitrise-plus"
REPO_ID="1449363568"
BRANCHE="refs/heads/develop"
ENVIRONNEMENT="development"
WF_TF="$REPO/.github/workflows/gcp-dev-terraform.yml@$BRANCHE"
WF_DEPLOY="$REPO/.github/workflows/dev-deploy.yml@$BRANCHE"
SA_PLAN="boussole-dev-tf-plan@$PROJECT.iam.gserviceaccount.com"
ROLES_LECTURE_PLAN=(roles/viewer roles/iam.securityReviewer)   # lecture seule : métadonnées et politiques IAM

MODE="${1:-audit}"
etape() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m[OK]\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m[ATTENTION]\033[0m %s\n' "$*"; }
echec() { printf '  \033[31m[ECHEC]\033[0m %s\n' "$*"; exit 1; }
confirmer() { local r; read -r -p "  $1 — taper OUI pour continuer : " r; [[ "$r" == "OUI" ]] || echec "Abandon, rien n'a été modifié à cette étape."; }

MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref,attribute.workflow_ref=assertion.workflow_ref,attribute.environment=assertion.environment,attribute.boussole_role=assertion.workflow_ref == '$WF_TF' ? 'tf-plan' : (assertion.workflow_ref == '$WF_DEPLOY' ? 'deployer' : 'aucun')"
CONDITION="assertion.repository_id == '$REPO_ID' && assertion.ref == '$BRANCHE' && assertion.environment == '$ENVIRONNEMENT' && ((assertion.workflow_ref == '$WF_TF' && assertion.event_name == 'workflow_dispatch') || (assertion.workflow_ref == '$WF_DEPLOY' && assertion.event_name in ['push', 'workflow_dispatch']))"

case "$MODE" in audit|etape1|etape2|verifier) ;; *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
command -v gcloud >/dev/null || echec "gcloud absent"
NUMERO="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || echec "Projet $PROJECT inaccessible"
POOL_NAME="projects/$NUMERO/locations/global/workloadIdentityPools/$POOL"
PRINCIPAL_ANCIEN="principalSet://iam.googleapis.com/$POOL_NAME/attribute.repository/$REPO"
PRINCIPAL_PLAN="principalSet://iam.googleapis.com/$POOL_NAME/attribute.boussole_role/tf-plan"

condition_actuelle() { gcloud iam workload-identity-pools providers describe "$PROVIDER" --project "$PROJECT" --location global --workload-identity-pool "$POOL" --format='value(attributeCondition)'; }
mapping_actuel()     { gcloud iam workload-identity-pools providers describe "$PROVIDER" --project "$PROJECT" --location global --workload-identity-pool "$POOL" --format='json(attributeMapping)'; }
liaisons_plan()      { gcloud iam service-accounts get-iam-policy "$SA_PLAN" --project "$PROJECT" --flatten='bindings[].members' --filter='bindings.role=roles/iam.workloadIdentityUser' --format='value(bindings.members)'; }
roles_plan()         { gcloud projects get-iam-policy "$PROJECT" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$SA_PLAN" --format='value(bindings.role)'; }

audit() {
  etape "État actuel (lecture seule)"
  echo "  Condition du fournisseur :"; condition_actuelle | sed 's/^/    /'
  echo "  Attributs :"; mapping_actuel | sed 's/^/    /'
  echo "  Liaisons workloadIdentityUser de tf-plan :"; liaisons_plan | sed 's/^/    /'
  echo "  Rôles projet de tf-plan :"; roles_plan | sed 's/^/    /'
  etape "Écarts avec la cible"
  [[ "$(condition_actuelle)" == "$CONDITION" ]] && ok "Condition conforme" || warn "Condition à remplacer (etape1)"
  mapping_actuel | grep -q 'boussole_role' && ok "Attribut boussole_role présent" || warn "Attribut boussole_role absent (etape1)"
  liaisons_plan | grep -qxF "$PRINCIPAL_PLAN" && ok "tf-plan lié par rôle" || warn "Liaison par rôle de tf-plan absente (etape1)"
  liaisons_plan | grep -qxF "$PRINCIPAL_ANCIEN" && warn "Ancienne liaison « tout le dépôt » encore présente (etape2)" || ok "Ancienne liaison retirée"
  for r in "${ROLES_LECTURE_PLAN[@]}"; do roles_plan | grep -qx "$r" && ok "tf-plan a $r" || warn "tf-plan n'a pas $r (etape1)"; done
}

etape1() {
  audit
  etape "Étape 1 : droits de lecture de tf-plan (nécessaires aux PLAN futurs : IAM du bucket et du dépôt AR)"
  for r in "${ROLES_LECTURE_PLAN[@]}"; do echo "  + $r"; done
  confirmer "Ajouter ces rôles en LECTURE SEULE à boussole-dev-tf-plan"
  for r in "${ROLES_LECTURE_PLAN[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA_PLAN" --role="$r" --condition=None --quiet >/dev/null
    ok "$r"
  done

  etape "Étape 1 : nouveau fournisseur WIF (attributs + condition)"
  echo "  Nouvelle condition :"; echo "    $CONDITION"
  confirmer "Remplacer la condition et les attributs du fournisseur $PROVIDER"
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" --project "$PROJECT" --location global \
    --workload-identity-pool "$POOL" --attribute-mapping="$MAPPING" --attribute-condition="$CONDITION" --quiet >/dev/null
  if [[ "$(condition_actuelle)" == "$CONDITION" ]]; then ok "Fournisseur mis à jour"
  else warn "Condition relue différente du texte attendu (normalisation possible) : vérifier ci-dessous"; condition_actuelle | sed 's/^/    /'; fi

  etape "Étape 1 : liaison de tf-plan par rôle (l'ancienne liaison est conservée pour ne pas couper le PLAN)"
  confirmer "Ajouter $PRINCIPAL_PLAN à boussole-dev-tf-plan"
  gcloud iam service-accounts add-iam-policy-binding "$SA_PLAN" --project "$PROJECT" \
    --role=roles/iam.workloadIdentityUser --member="$PRINCIPAL_PLAN" --quiet >/dev/null
  ok "Liaison ajoutée"
  printf '\nÉtape 1 terminée. Lancer maintenant « GCP DEV Terraform » sur develop : le PLAN doit réussir.\nEnsuite seulement : bash %s etape2\n' "$0"
}

etape2() {
  liaisons_plan | grep -qxF "$PRINCIPAL_PLAN" || echec "Étape 1 non faite (liaison par rôle absente)"
  [[ "$(condition_actuelle)" == "$CONDITION" ]] || echec "Étape 1 non faite (condition)"
  liaisons_plan | grep -qxF "$PRINCIPAL_ANCIEN" || { ok "Ancienne liaison déjà retirée"; return; }
  etape "Étape 2 : retrait de l'ancienne liaison « tout le dépôt » de tf-plan"
  warn "À faire seulement après un PLAN réussi depuis l'étape 1."
  confirmer "Retirer $PRINCIPAL_ANCIEN de boussole-dev-tf-plan"
  gcloud iam service-accounts remove-iam-policy-binding "$SA_PLAN" --project "$PROJECT" \
    --role=roles/iam.workloadIdentityUser --member="$PRINCIPAL_ANCIEN" --quiet >/dev/null
  ok "Ancienne liaison retirée. Relancer « GCP DEV Terraform » : le PLAN doit réussir."
}

verifier() {
  audit
  etape "Synthèse"
  [[ "$(condition_actuelle)" == "$CONDITION" ]] && liaisons_plan | grep -qxF "$PRINCIPAL_PLAN" && ! liaisons_plan | grep -qxF "$PRINCIPAL_ANCIEN" \
    && ok "Modèle cible en place pour tf-plan" || warn "Modèle cible incomplet"
  echo "  Preuves de refus à consigner (PR 4, #65) : workflow non autorisé, branche non autorisée, tentatives croisées tf-plan <-> deployer."
}

"$MODE"
