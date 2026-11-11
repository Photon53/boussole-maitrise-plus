#!/usr/bin/env bash
# Boussole Maîtrise+ — Terraform DEV depuis Cloud Shell, par le propriétaire (ticket #65).
#
#   bash scripts/terraform-dev-cloudshell.sh plan     # plan seul, enregistré pour revue (aucune modification)
#   bash scripts/terraform-dev-cloudshell.sh apply    # applique EXACTEMENT le dernier plan enregistré, après « APPLIQUER »
#
# Pourquoi ce script : le workflow GitHub « GCP DEV Terraform » est en PLAN seul (compte de lecture) et ne
# s'exécute que sur develop. Le plan d'une branche de PR et tout apply se font ici, avec l'identité du
# propriétaire, après revue. Projet DEV uniquement.
set -Eeuo pipefail

PROJECT="mer-boussole-dev"
BUCKET="mer-boussole-dev-tfstate"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
DOSSIER="$RACINE/infrastructure/terraform/dev"
TRAVAIL="$HOME/.boussole-terraform"
PLAN_FICHIER="$TRAVAIL/dev.tfplan"
MODE="${1:-plan}"

echec() { printf '\033[31m[ECHEC]\033[0m %s\n' "$*"; exit 1; }
case "$MODE" in plan|apply) ;; *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
command -v terraform >/dev/null || echec "terraform absent (préinstallé dans Cloud Shell)"
[[ "$(gcloud config get-value project 2>/dev/null)" == "$PROJECT" ]] || echec "Projet gcloud actif différent de $PROJECT (gcloud config set project $PROJECT)"
# Jeton gcloud frais (1 h) transmis à Terraform : dans Cloud Shell, Terraform interroge sinon le serveur de
# métadonnées, parfois indisponible (« invalid token JSON from metadata: EOF »).
GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token 2>/dev/null)" || echec "Aucun compte gcloud actif : gcloud auth login"
export GOOGLE_OAUTH_ACCESS_TOKEN
mkdir -p "$TRAVAIL" && chmod 700 "$TRAVAIL"

# Membres IAP/OS Login : même valeur que la variable GitHub GCP_DEV_ADMIN_MEMBERS_JSON.
if [[ -z "${TF_VAR_admin_members:-}" ]]; then
  compte="$(gcloud config get-value account 2>/dev/null)"
  export TF_VAR_admin_members="[\"user:$compte\"]"
  echo "admin_members = $TF_VAR_admin_members (surcharger avec TF_VAR_admin_members si besoin)"
fi
export TF_VAR_project_id="$PROJECT"

cd "$DOSSIER"
echo "Branche : $(git -C "$RACINE" rev-parse --abbrev-ref HEAD) @ $(git -C "$RACINE" rev-parse --short HEAD)"
terraform init -input=false -reconfigure -backend-config="bucket=$BUCKET" -backend-config="prefix=dev" >/dev/null
terraform fmt -check -recursive
terraform validate

if [[ "$MODE" == plan ]]; then
  terraform plan -input=false -lock-timeout=60s -out="$PLAN_FICHIER"
  terraform show -no-color "$PLAN_FICHIER" > "$TRAVAIL/dev.tfplan.txt"
  git -C "$RACINE" rev-parse HEAD > "$TRAVAIL/dev.tfplan.commit"
  printf '\nPlan enregistré : %s (texte : %s.txt). Aucune modification effectuée.\n' "$PLAN_FICHIER" "$PLAN_FICHIER"
  printf 'Après revue et approbation : bash %s apply\n' "$0"
  exit 0
fi

[[ -f "$PLAN_FICHIER" ]] || echec "Aucun plan enregistré : lancer d'abord « plan »"
[[ "$(cat "$TRAVAIL/dev.tfplan.commit")" == "$(git -C "$RACINE" rev-parse HEAD)" ]] || echec "Le code a changé depuis le plan : relancer « plan »"
terraform show "$PLAN_FICHIER" | tail -5
grep -qE 'must be replaced|will be destroyed' "$TRAVAIL/dev.tfplan.txt" && printf '\033[33m[ATTENTION]\033[0m Le plan contient des remplacements ou destructions : relire %s.txt\n' "$PLAN_FICHIER"
read -r -p "Appliquer ce plan sur $PROJECT ? Taper APPLIQUER : " r
[[ "$r" == "APPLIQUER" ]] || echec "Abandon, rien n'a été appliqué."
terraform apply -input=false -lock-timeout=60s "$PLAN_FICHIER"
rm -f "$PLAN_FICHIER"
terraform output
