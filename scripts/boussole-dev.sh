#!/usr/bin/env bash
# Boussole Maitrise+ — assistant de preparation DEV (aucun terraform apply)
set -Eeuo pipefail
PROJECT="mer-boussole-dev"
REPO="Photon53/boussole-maitrise-plus"
BRANCH="develop"
BUCKET="mer-boussole-dev-tfstate"
PLAN_SA="boussole-dev-tf-plan@${PROJECT}.iam.gserviceaccount.com"
OLD_SA="boussole-dev-terraform@${PROJECT}.iam.gserviceaccount.com"
PROVIDER="github"
POOL="github-dev"
MODE="${1:-audit}"
FAIL=0
REPORT=()
say(){ printf '\n==> %s\n' "$*"; }
ok(){ printf '  [OK] %s\n' "$*"; REPORT+=("OK: $*"); }
warn(){ printf '  [ATTENTION] %s\n' "$*"; REPORT+=("ATTENTION: $*"); }
bad(){ printf '  [ECHEC] %s\n' "$*"; REPORT+=("ECHEC: $*"); FAIL=1; }
ask(){ local answer; read -r -p "$1 [oui/N] " answer; [[ "$answer" == "oui" ]]; }
need(){ command -v "$1" >/dev/null 2>&1 || { bad "Commande absente: $1"; return 1; }; }
report(){ printf '\n====== RAPPORT BOUSSOLE DEV ======\n'; printf '%s\n' "${REPORT[@]}"; printf '=================================\n'; }
trap 'report' EXIT
case "$MODE" in
  audit|setup|test) ;;
  deploy) echo "DEPLOY BLOQUE: ce script ne lance jamais terraform apply. Validation du plan, du budget et de l identite humaine requise avant une procedure distincte."; exit 2 ;;
  *) echo "Usage: bash scripts/boussole-dev.sh [audit|setup|test|deploy]"; exit 2 ;;
esac
for tool in gcloud gh git; do need "$tool" || exit 1; done
say "Verifications initiales"
ACTIVE="$(gcloud config get-value project 2>/dev/null || true)"
if [[ "$ACTIVE" == "$PROJECT" ]]; then ok "Projet GCP actif: $PROJECT"; else
  warn "Projet actif: $ACTIVE (attendu: $PROJECT)"
  if [[ "$MODE" == setup ]] && ask "Basculer sur $PROJECT ?"; then gcloud config set project "$PROJECT"; else bad "Selectionner le bon projet avant de continuer"; exit 1; fi
fi
if gh auth status >/dev/null 2>&1; then ok "GitHub CLI authentifie"; else bad "gh auth login necessaire"; exit 1; fi
if ! gh repo view "$REPO" --json viewerPermission --jq '.viewerPermission' >/dev/null 2>&1; then bad "Acces GitHub au depot absent"; exit 1; else ok "Acces GitHub au depot"; fi
if gcloud iam service-accounts describe "$PLAN_SA" --project="$PROJECT" >/dev/null 2>&1; then ok "Compte PLAN existe"; else
  warn "Compte PLAN absent"
  if [[ "$MODE" == setup ]] && ask "Creer le compte PLAN ?"; then
    gcloud iam service-accounts create boussole-dev-tf-plan --project="$PROJECT" --display-name="Boussole DEV Terraform Plan"
  else bad "Compte PLAN requis"; fi
fi
say "Permissions GCP"
POLICY="$(gcloud projects get-iam-policy "$PROJECT" --format=json)"
for role in roles/compute.viewer roles/artifactregistry.reader roles/iam.serviceAccountViewer; do
  if printf '%s' "$POLICY" | python3 -c 'import json,sys; p=json.load(sys.stdin); sa=sys.argv[1]; role=sys.argv[2]; sys.exit(0 if any(b["role"]==role and "serviceAccount:"+sa in b.get("members",[]) for b in p.get("bindings",[])) else 1)' "$PLAN_SA" "$role"; then
    ok "$role attribue au PLAN"
  else
    warn "$role absent"
    if [[ "$MODE" == setup ]] && ask "Attribuer $role au compte PLAN ?"; then
      gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$PLAN_SA" --role="$role" --quiet
    fi
  fi
done
if gcloud storage buckets describe "gs://$BUCKET" --format="value(name)" >/dev/null 2>&1; then ok "Bucket Terraform accessible"; else bad "Bucket Terraform inaccessible"; fi
BP="$(gcloud storage buckets get-iam-policy "gs://$BUCKET" --format=json 2>/dev/null || echo '{}')"
if printf '%s' "$BP" | python3 -c 'import json,sys; p=json.load(sys.stdin); sa=sys.argv[1]; sys.exit(0 if any(b["role"]=="roles/storage.objectAdmin" and "serviceAccount:"+sa in b.get("members",[]) for b in p.get("bindings",[])) else 1)' "$PLAN_SA"; then
  ok "Acces backend GCS du PLAN"
else
  warn "Acces backend GCS absent"
  if [[ "$MODE" == setup ]] && ask "Accorder storage.objectAdmin sur ce bucket au PLAN (ecriture possible sur etat Terraform) ?"; then
    gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$PLAN_SA" --role="roles/storage.objectAdmin"
  fi
fi
say "Workload Identity Federation"
CONDITION="$(gcloud iam workload-identity-pools providers describe "$PROVIDER" --project="$PROJECT" --location=global --workload-identity-pool="$POOL" --format='value(attributeCondition)' 2>/dev/null || true)"
if [[ "$CONDITION" == *"assertion.repository=='$REPO'"* && "$CONDITION" == *"assertion.ref=='refs/heads/$BRANCH'"* ]]; then ok "WIF limite au depot et a develop"; else bad "WIF non conforme ou absent"; fi
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
PRINCIPAL="principalSet://iam.googleapis.com/projects/$NUMBER/locations/global/workloadIdentityPools/$POOL/attribute.repository/$REPO"
SA_POLICY="$(gcloud iam service-accounts get-iam-policy "$PLAN_SA" --project="$PROJECT" --format=json 2>/dev/null || echo '{}')"
if printf '%s' "$SA_POLICY" | python3 -c 'import json,sys; p=json.load(sys.stdin); m=sys.argv[1]; sys.exit(0 if any(b["role"]=="roles/iam.workloadIdentityUser" and m in b.get("members",[]) for b in p.get("bindings",[])) else 1)' "$PRINCIPAL"; then ok "GitHub autorise a utiliser PLAN"; else
  warn "Liaison WIF du PLAN absente"
  if [[ "$MODE" == setup && "$CONDITION" == *"assertion.ref=='refs/heads/$BRANCH'"* ]] && ask "Autoriser le depot GitHub a utiliser PLAN ?"; then
    gcloud iam service-accounts add-iam-policy-binding "$PLAN_SA" --project="$PROJECT" --role=roles/iam.workloadIdentityUser --member="$PRINCIPAL"
  fi
fi
say "Workflow GitHub"
TMP="$(mktemp)"; trap 'rm -f "$TMP"; report' EXIT
if gh api "repos/$REPO/contents/.github/workflows/gcp-dev-terraform.yml?ref=$BRANCH" --jq '.content' | tr -d '\n' | base64 -d > "$TMP"; then
  if grep -q 'terraform apply' "$TMP"; then bad "Le workflow contient terraform apply"; else ok "Aucune commande terraform apply"; fi
  if grep -q "service_account: $PLAN_SA" "$TMP"; then ok "Workflow configure pour PLAN"; else bad "Workflow n utilise pas le compte PLAN"; fi
else bad "Impossible de lire le workflow"; fi
ENVJSON="$(gh api "repos/$REPO/environments/development-apply" 2>/dev/null || echo '{}')"
if printf '%s' "$ENVJSON" | python3 -c 'import json,sys; p=json.load(sys.stdin); sys.exit(0 if p.get("can_admins_bypass") is False and p.get("deployment_branch_policy",{}).get("custom_branch_policies") is True else 1)'; then ok "Environnement apply restreint (sans approbation native)"; else warn "Verifier environnement development-apply"; fi
if [[ "$MODE" == test ]]; then
  say "Lancement du workflow PLAN uniquement"
  if ask "Lancer GitHub Actions terraform plan sur develop ?"; then
    gh workflow run gcp-dev-terraform.yml --repo "$REPO" --ref "$BRANCH"
    sleep 4
    RUN="$(gh run list --repo "$REPO" --workflow gcp-dev-terraform.yml --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')"
    if [[ -n "$RUN" ]]; then
      say "Attente du run $RUN"
      if gh run watch "$RUN" --repo "$REPO" --exit-status; then ok "Workflow PLAN reussi"; else bad "Workflow PLAN en echec"; fi
      echo "https://github.com/$REPO/actions/runs/$RUN"
    fi
  fi
fi
say "Controle des risques restants"
warn "Verifier et retirer la liaison WIF de l ancien compte admin seulement APRES un PLAN reussi"
warn "Budget GCP et alertes 50/80/100 a confirmer dans Cloud Billing"
warn "Aucun deploiement Terraform n est effectue par ce script"
