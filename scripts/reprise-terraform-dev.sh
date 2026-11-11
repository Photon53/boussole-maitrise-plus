#!/usr/bin/env bash
# Boussole Maîtrise+ — reprise après un apply Terraform DEV interrompu (ticket #65, PR 1).
# Cloud Shell, propriétaire du projet. Usage :  bash scripts/reprise-terraform-dev.sh
#
# Enchaîne, en s'arrêtant à la moindre anomalie :
#   1. identifiants gcloud + identifiants Terraform (ADC), connexion interactive si nécessaire ;
#   2. retrait du verrou d'état laissé par l'apply interrompu (seulement s'il s'agit bien d'un apply) ;
#   3. renvoi de errored.tfstate vers le bucket d'état (copie conservée dans ~/.boussole-terraform) ;
#   4. nouveau plan : il doit être « 3 to add, 0 to change, 0 to destroy » (liaisons IAM déjà présentes dans GCP) ;
#   5. apply de ce plan après « APPLIQUER » ;
#   6. contrôle WIF final.
# Relançable : chaque étape déjà faite est détectée et sautée.
set -Eeuo pipefail

PROJECT="mer-boussole-dev"
BUCKET="mer-boussole-dev-tfstate"
VERROU="gs://$BUCKET/dev/default.tflock"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
DOSSIER="$RACINE/infrastructure/terraform/dev"
TRAVAIL="$HOME/.boussole-terraform"
PLAN_ATTENDU="Plan: 3 to add, 0 to change, 0 to destroy."

etape() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m[OK]\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m[ATTENTION]\033[0m %s\n' "$*"; }
echec() { printf '  \033[31m[ECHEC]\033[0m %s\n' "$*"; exit 1; }
mkdir -p "$TRAVAIL" && chmod 700 "$TRAVAIL"

# --- 1. Identifiants --------------------------------------------------------------------------------
etape "1. Identifiants"
gcloud config set project "$PROJECT" >/dev/null 2>&1
if ! gcloud auth print-access-token >/dev/null 2>&1; then
  warn "Aucun compte gcloud actif : connexion (ouvrir le lien, choisir ton compte, coller le code)."
  gcloud auth login --update-adc
fi
gcloud auth print-access-token >/dev/null 2>&1 || echec "Connexion gcloud impossible"
ok "gcloud : $(gcloud config get-value account 2>/dev/null)"
# Terraform utilise les identifiants par défaut (ADC), distincts de ceux de gcloud.
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  warn "Identifiants Terraform (ADC) absents : connexion."
  gcloud auth application-default login
fi
gcloud auth application-default print-access-token >/dev/null 2>&1 || echec "Identifiants Terraform (ADC) indisponibles"
gcloud auth application-default set-quota-project "$PROJECT" >/dev/null 2>&1 || true
ok "Identifiants Terraform (ADC) disponibles"

cd "$DOSSIER"
terraform init -input=false -reconfigure -backend-config="bucket=$BUCKET" -backend-config="prefix=dev" >/dev/null
ok "Terraform initialisé sur gs://$BUCKET/dev"

# --- 2. Verrou ------------------------------------------------------------------------------------------
etape "2. Verrou d'état"
if gcloud storage cat "$VERROU" > "$TRAVAIL/verrou.json" 2>/dev/null; then
  read -r ID OPERATION CREE < <(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['ID'], d['Operation'], d['Created'])" "$TRAVAIL/verrou.json")
  echo "  Verrou présent : ID=$ID, opération=$OPERATION, créé le $CREE"
  [[ "$OPERATION" == "OperationTypeApply" ]] || echec "Verrou inattendu ($OPERATION) : quelqu'un d'autre utilise peut-être Terraform. Ne rien forcer."
  [[ -f errored.tfstate ]] || echec "Verrou d'apply présent mais errored.tfstate introuvable dans $DOSSIER : ne rien forcer, me contacter."
  terraform force-unlock -force "$ID"
  ok "Verrou retiré"
else
  ok "Aucun verrou"
fi

# --- 3. État ----------------------------------------------------------------------------------------------
etape "3. État Terraform"
if [[ -f errored.tfstate ]]; then
  copie="$TRAVAIL/errored-$(date +%Y%m%d-%H%M%S).tfstate"
  cp errored.tfstate "$copie" && chmod 600 "$copie"
  terraform state push errored.tfstate
  rm errored.tfstate
  ok "État renvoyé dans le bucket (copie de secours : $copie)"
else
  ok "Pas de errored.tfstate : état déjà à jour"
fi
for r in google_service_account.deployer google_storage_bucket.deploiement; do
  terraform state list | grep -qx "$r" || echec "$r absent de l'état après reprise"
done
ok "Compte et bucket présents dans l'état"

# --- 4. Plan ------------------------------------------------------------------------------------------------
etape "4. Nouveau plan (aucune modification)"
bash "$RACINE/scripts/terraform-dev-cloudshell.sh" plan
resume="$(grep -E '^(Plan:|No changes)' "$TRAVAIL/dev.tfplan.txt" | head -1 || true)"
echo "  Résumé : ${resume:-introuvable}"
if [[ "$resume" == No\ changes* ]]; then
  ok "Rien à appliquer"
else
  [[ "$resume" == "$PLAN_ATTENDU" ]] || echec "Plan différent de « $PLAN_ATTENDU » : n'applique pas, envoie-moi $TRAVAIL/dev.tfplan.txt"
  for r in deployer_writer deployer_releases deployer_wif; do
    grep -q "\.$r will be created" "$TRAVAIL/dev.tfplan.txt" || echec "Ressource attendue absente du plan : $r"
  done
  ok "Plan conforme : uniquement les 3 liaisons IAM du déployeur (déjà présentes dans GCP, ajout idempotent)"

  # --- 5. Apply ---------------------------------------------------------------------------------------------
  etape "5. Apply du plan relu"
  bash "$RACINE/scripts/terraform-dev-cloudshell.sh" apply
fi

# --- 6. Contrôles -------------------------------------------------------------------------------------------
etape "6. Contrôles"
gcloud storage ls "$VERROU" >/dev/null 2>&1 && echec "Verrou toujours présent après l'apply" || ok "Aucun verrou restant"
terraform output
bash "$RACINE/scripts/wif-dev-comptes-separes.sh" verifier
printf '\nReprise terminée. Variables à créer dans l environnement GitHub « development » :\n'
printf '  GCP_DEV_DEPLOYER_SA        = %s\n' "$(terraform output -raw deployer_service_account)"
printf '  GCP_DEV_DEPLOIEMENT_BUCKET = %s\n' "$(terraform output -raw deploiement_bucket)"
