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
  audit|setup|test|auto|preflight|guarded) ;;
  deploy) echo "DEPLOY BLOQUE: ce script ne lance jamais terraform apply. Validation du plan, du budget et de l identite humaine requise avant une procedure distincte."; exit 2 ;;
  *) echo "Usage: bash scripts/boussole-dev.sh [guarded|preflight|auto|audit|setup|test|deploy]"; exit 2 ;;
esac
# Lecture seule: analyse du code Terraform, du workflow et des risques de cout.
preflight() {
  say "Audit pre-deploiement DEV - lecture seule"
  local tf workflow startup tmpdir verdict reasons
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${PREFLIGHT_TMPDIR:-}"; report' EXIT
  PREFLIGHT_TMPDIR="$tmpdir"
  for entry in "infrastructure/terraform/dev/main.tf:main.tf" ".github/workflows/gcp-dev-terraform.yml:workflow.yml" "infrastructure/terraform/dev/startup.sh:startup.sh"; do
    local remote="${entry%%:*}" localfile="${entry##*:}"
    if ! gh api -X GET "repos/$REPO/contents/$remote?ref=$BRANCH" --jq '.content' | tr -d '\n' | base64 -d > "$tmpdir/$localfile"; then
      bad "Lecture GitHub impossible: $remote"; return 1
    fi
  done
  if grep -Eq '^[[:space:]]*[^#[:space:]].*terraform[[:space:]]+apply' "$tmpdir/workflow.yml"; then bad "Workflow contient terraform apply"; else ok "Workflow sans terraform apply"; fi
  local vm_type disk_type disk_size
  vm_type="$(sed -n '/variable "machine_type"/,/^}/s/^[[:space:]]*default[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tmpdir/main.tf" | head -n 1)"
  disk_type="$(sed -n '/initialize_params {/,/^[[:space:]]*}/s/^[[:space:]]*type[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tmpdir/main.tf" | head -n 1)"
  disk_size="$(sed -n '/initialize_params {/,/^[[:space:]]*}/s/^[[:space:]]*size[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$tmpdir/main.tf" | head -n 1)"
  if [[ "$vm_type" == "e2-small" ]]; then ok "VM proposee: e2-small (cout a chiffrer)"; elif [[ -n "$vm_type" ]]; then warn "VM proposee: $vm_type (cout a chiffrer)"; else bad "Type VM non determine"; fi
  if [[ -n "$disk_type" && -n "$disk_size" ]]; then ok "Disque propose: $disk_size Go $disk_type (cout a chiffrer)"; else bad "Disque non determine"; fi
  if grep -q 'google_compute_router_nat' "$tmpdir/main.tf"; then warn "Cloud NAT: cout horaire et traitement des donnees a chiffrer"; fi
  if grep -q 'access_config' "$tmpdir/main.tf"; then bad "Configuration IP externe detectee"; else ok "Pas de bloc access_config explicite"; fi
  if grep -q 'enable-oslogin = "TRUE"' "$tmpdir/main.tf"; then ok "OS Login active"; else warn "OS Login non confirme"; fi
  if grep -q 'enable_secure_boot          = true' "$tmpdir/main.tf"; then ok "Secure Boot active"; else warn "Secure Boot non confirme"; fi
  if grep -q 'roles/iap.tunnelResourceAccessor' "$tmpdir/main.tf"; then ok "Acces IAP prevu"; else warn "Acces IAP non confirme"; fi
  if grep -q 'apt-get install' "$tmpdir/startup.sh"; then warn "Startup script installe des paquets au demarrage; reproductibilite a tester"; fi
  warn "Prix temps reel non verifies: aucun GO budget sans estimation chiffree (region europe-west9, VM, disque, NAT, reseau)"
  warn "Verification des ressources deja existantes et des quotas non realisee"
  warn "Plan Terraform precedent reussi, mais contenu et cout du plan non audites ici"
  verdict="NO-GO"
  printf '\n====== RAPPORT GO / NO-GO ======\n'
  printf 'Projet: %s | Branche: %s | Budget cible: 30 EUR/mois\n' "$PROJECT" "$BRANCH"
  printf 'Decision: %s\n' "$verdict"
  printf 'Motifs: cout mensuel non demontre; configuration VM + Cloud NAT a optimiser; plan detaille a examiner.\n'
  printf 'Actions: chiffrer les ressources; optimiser taille/duree VM et NAT; examiner plan; obtenir approbation humaine.\n'
  printf 'Aucun terraform apply execute.\n'
  printf '===============================\n'
  return 0
}
if [[ "$MODE" == preflight ]]; then
  for tool in gh python3; do need "$tool" || exit 1; done
  if ! gh auth status >/dev/null 2>&1; then bad "Authentification GitHub requise"; exit 1; fi
  preflight
  exit "$FAIL"
fi
guarded() {
  say "Controle unique budget 150 EUR / 3 mois - aucun APPLY"
  local tmp billing token endpoint code existing payload run
  tmp="$(mktemp -d)"
  trap 'rm -rf "${GUARD_TMP:-}"; report' EXIT
  GUARD_TMP="$tmp"
  for t in gh gcloud curl python3 base64; do need "$t" || return 1; done
  [[ "$(gcloud config get-value project 2>/dev/null)" == "$PROJECT" ]] || { bad "Mauvais projet GCP"; return 1; }
  gh auth status >/dev/null 2>&1 || { bad "gh non authentifie"; return 1; }
  gh api -X GET "repos/$REPO/contents/infrastructure/terraform/dev/main.tf?ref=$BRANCH" --jq .content | tr -d "\n" | base64 -d > "$tmp/main.tf" || return 1
  gh api -X GET "repos/$REPO/contents/.github/workflows/gcp-dev-terraform.yml?ref=$BRANCH" --jq .content | tr -d "\n" | base64 -d > "$tmp/workflow.yml" || return 1
  if grep -Eq "^[[:space:]]*[^#[:space:]].*terraform[[:space:]]+apply" "$tmp/workflow.yml"; then bad "APPLY detecte dans workflow"; return 1; fi
  grep -q 'default = "e2-medium"' "$tmp/main.tf" || { bad "VM e2-medium non confirmee"; return 1; }
  ok "Terraform e2-medium et workflow PLAN ONLY"
  billing="$(gcloud billing projects describe "$PROJECT" --format="value(billingAccountName)" 2>/dev/null || true)"
  [[ "$billing" == billingAccounts/* ]] || { bad "Facturation inaccessible"; return 1; }
  token="$(gcloud auth print-access-token)" || return 1
  endpoint="https://billingbudgets.googleapis.com/v1/$billing/budgets"
  code="$(curl -sS -o "$tmp/list.json" -w "%{http_code}" -G --data-urlencode pageSize=1000 -H "Authorization: Bearer $token" -H "x-goog-user-project: $PROJECT" "$endpoint")" || return 1
  [[ "$code" == 200 ]] || { bad "Lecture budgets HTTP $code"; return 1; }
  local number
  number="$(gcloud projects describe "$PROJECT" --format="value(projectNumber)")"
  existing="$(python3 - "$tmp/list.json" "$number" <<'PY'
import json,sys
b=json.load(open(sys.argv[1])).get("budgets",[])
a=[x["name"] for x in b if x.get("displayName") in ("Boussole DEV - 30 EUR","Boussole DEV - 50 EUR") and x.get("budgetFilter",{}).get("projects")==["projects/"+sys.argv[2]]]
print(a[0] if len(a)==1 else ("MULTIPLE" if len(a)>1 else ""))
PY
)"
  [[ "$existing" != MULTIPLE ]] || { bad "Budgets multiples: intervention manuelle"; return 1; }
  python3 - "$number" > "$tmp/payload.json" <<'PY'
import json,sys
print(json.dumps({"displayName":"Boussole DEV - 50 EUR","budgetFilter":{"projects":["projects/"+sys.argv[1]],"calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"EUR","units":"50"}},"thresholdRules":[{"thresholdPercent":v} for v in (0.5,0.8,1.0)]}))
PY
  if ask "Configurer budget 50 EUR/mois avec alertes 25/40/50 EUR (NON BLOQUANTES) ?"; then
    if [[ -n "$existing" ]]; then
      python3 - "$tmp/list.json" "$existing" > "$tmp/payload.json" <<'PY'
import json,sys
b=next(x for x in json.load(open(sys.argv[1]))["budgets"] if x["name"]==sys.argv[2])
b.update(displayName="Boussole DEV - 50 EUR",amount={"specifiedAmount":{"currencyCode":"EUR","units":"50"}},thresholdRules=[{"thresholdPercent":v} for v in (0.5,0.8,1.0)])
print(json.dumps(b))
PY
      endpoint="https://billingbudgets.googleapis.com/v1/$existing?updateMask=displayName,amount,thresholdRules"
      local method=PATCH
    else local method=POST; fi
    code="$(curl -sS -o "$tmp/result.json" -w "%{http_code}" -X "$method" -H "Authorization: Bearer $token" -H "x-goog-user-project: $PROJECT" -H "Content-Type: application/json" --data-binary @"$tmp/payload.json" "$endpoint")" || return 1
    [[ "$code" == 200 ]] || { bad "Modification budget HTTP $code: $(cat "$tmp/result.json")"; return 1; }
    python3 - "$tmp/result.json" <<'PY' || { bad "Reponse budget incorrecte"; return 1; }
import json,sys
b=json.load(open(sys.argv[1]));a=b.get("amount",{}).get("specifiedAmount",{})
assert a.get("currencyCode")=="EUR" and str(a.get("units"))=="50"
assert sorted(float(t["thresholdPercent"]) for t in b.get("thresholdRules",[]))==[0.5,0.8,1.0]
PY
    ok "Budget 50 EUR/mois et alertes API verifies"
  else warn "Budget inchange"; fi
  if ask "Declencher Terraform PLAN uniquement ?"; then
    gh workflow run gcp-dev-terraform.yml --repo "$REPO" --ref "$BRANCH" || return 1
    sleep 6
    run="$(gh run list --repo "$REPO" --workflow gcp-dev-terraform.yml --branch "$BRANCH" --limit 1 --json databaseId --jq ".[0].databaseId")"
    if gh run watch "$run" --repo "$REPO" --exit-status; then ok "PLAN reussi: $run"; else bad "PLAN echoue: $run"; fi
  fi
  warn "NO-GO APPLY: prix exact NAT/reseau et cout cumule 150 EUR non garantis"
  warn "Budget et alertes ne constituent pas un plafond de facturation; notifications a verifier"
  warn "Aucun terraform apply execute"
}
if [[ "$MODE" == guarded ]]; then guarded; exit "$FAIL"; fi
for tool in gcloud gh git python3 curl; do need "$tool" || exit 1; done
say "Verifications initiales"
ACTIVE="$(gcloud config get-value project 2>/dev/null || true)"
if [[ "$ACTIVE" == "$PROJECT" ]]; then ok "Projet GCP actif: $PROJECT"; else
  warn "Projet actif: $ACTIVE (attendu: $PROJECT)"
  if [[ "$MODE" == setup || "$MODE" == auto ]] && ask "Basculer sur $PROJECT ?"; then gcloud config set project "$PROJECT"; else bad "Selectionner le bon projet avant de continuer"; exit 1; fi
fi
if gh auth status >/dev/null 2>&1; then ok "GitHub CLI authentifie"; else bad "gh auth login necessaire"; exit 1; fi
if ! gh repo view "$REPO" --json viewerPermission --jq '.viewerPermission' >/dev/null 2>&1; then bad "Acces GitHub au depot absent"; exit 1; else ok "Acces GitHub au depot"; fi
if gcloud iam service-accounts describe "$PLAN_SA" --project="$PROJECT" >/dev/null 2>&1; then ok "Compte PLAN existe"; else
  warn "Compte PLAN absent"
  if [[ "$MODE" == setup || "$MODE" == auto ]] && ask "Creer le compte PLAN ?"; then
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
    if [[ "$MODE" == setup || "$MODE" == auto ]] && ask "Attribuer $role au compte PLAN ?"; then
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
  if [[ "$MODE" == setup || "$MODE" == auto ]] && ask "Accorder storage.objectAdmin sur ce bucket au PLAN (ecriture possible sur etat Terraform) ?"; then
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
  if [[ ( "$MODE" == setup || "$MODE" == auto ) && "$CONDITION" == *"assertion.ref=='refs/heads/$BRANCH'"* ]] && ask "Autoriser le depot GitHub a utiliser PLAN ?"; then
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
if [[ "$MODE" == test || "$MODE" == auto ]]; then
  say "Lancement du workflow PLAN uniquement"
  if ask "Lancer GitHub Actions terraform plan sur develop ?"; then
    gh workflow run gcp-dev-terraform.yml --repo "$REPO" --ref "$BRANCH"
    sleep 4
    RUN="$(gh run list --repo "$REPO" --workflow gcp-dev-terraform.yml --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')"
    if [[ -n "$RUN" ]]; then
      say "Attente du run $RUN"
      if gh run watch "$RUN" --repo "$REPO" --exit-status; then ok "Workflow PLAN reussi"; PLAN_OK=1; else bad "Workflow PLAN en echec"; PLAN_OK=0; fi
      echo "https://github.com/$REPO/actions/runs/$RUN"
    fi
  fi
fi
if [[ "$MODE" == auto && "${PLAN_OK:-0}" == 1 ]]; then
  say "Durcissement IAM apres test PLAN reussi"
  OLD_POLICY="$(gcloud iam service-accounts get-iam-policy "$OLD_SA" --project="$PROJECT" --format=json 2>/dev/null || echo '{}')"
  if printf '%s' "$OLD_POLICY" | python3 -c 'import json,sys; p=json.load(sys.stdin); m=sys.argv[1]; sys.exit(0 if any(b["role"]=="roles/iam.workloadIdentityUser" and m in b.get("members",[]) for b in p.get("bindings",[])) else 1)' "$PRINCIPAL"; then
    if ask "Retirer l ancien acces WIF GitHub du compte Terraform administrateur ?"; then
      if gcloud iam service-accounts remove-iam-policy-binding "$OLD_SA" --project="$PROJECT" --role=roles/iam.workloadIdentityUser --member="$PRINCIPAL" --quiet; then
        ok "Ancien acces WIF retire"
      else bad "Echec retrait ancien acces WIF"; fi
    else warn "Ancien acces WIF conserve a la demande de l utilisateur"; fi
  else ok "Ancien compte admin sans liaison WIF GitHub pour ce depot"; fi
fi

# Budget mensuel DEV : 30 EUR, alertes 50/80/100 %. Les alertes ne plafonnent pas les couts.
budget_dev() {
  say "Budget GCP DEV (30 EUR/mois)"
  for tool in curl python3; do need "$tool" || return 1; done
  local billing account token endpoint listing existing payload response check
  billing="$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)' 2>/dev/null || true)"
  if [[ ! "$billing" =~ ^billingAccounts/[A-Za-z0-9-]+$ ]]; then
    bad "Compte de facturation introuvable ou droits insuffisants"; return 1
  fi
  account="${billing#billingAccounts/}"
  token="$(gcloud auth print-access-token 2>/dev/null || true)"
  if [[ -z "$token" ]]; then bad "Authentification GCP manquante"; return 1; fi
  endpoint="https://billingbudgets.googleapis.com/v1/$billing/budgets"
  local http_code body_file
  body_file="$(mktemp)"
  http_code="$(curl --silent --show-error --output "$body_file" --write-out '%{http_code}' --get --data-urlencode 'pageSize=1000' -H "Authorization: Bearer $token" -H "x-goog-user-project: $PROJECT" "$endpoint")" || {
    rm -f "$body_file"; bad "Erreur reseau lors de la lecture des budgets"; return 1;
  }
  if [[ "$http_code" != 200 ]]; then
    local error_msg
    error_msg="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("error",{}).get("message","Erreur inconnue"))' "$body_file" 2>/dev/null || true)"
    rm -f "$body_file"
    warn "API Billing Budgets HTTP $http_code: $error_msg"
    if [[ "$http_code" == 403 && "$error_msg" == *"disabled"* || "$http_code" == 403 && "$error_msg" == *"has not been used"* ]]; then
      if [[ "$MODE" == auto || "$MODE" == setup ]] && ask "Activer billingbudgets.googleapis.com dans $PROJECT ?"; then
        if gcloud services enable billingbudgets.googleapis.com --project="$PROJECT"; then
          ok "API Billing Budgets activee; nouvelle tentative"
          http_code="$(curl --silent --show-error --output "$body_file" --write-out '%{http_code}' --get --data-urlencode 'pageSize=1000' -H "Authorization: Bearer $token" -H "x-goog-user-project: $PROJECT" "$endpoint")" || http_code=000
          if [[ "$http_code" != 200 ]]; then
            warn "Nouvelle tentative HTTP $http_code (propagation possible)"
            rm -f "$body_file"; return 1
          fi
        else bad "Activation API impossible"; return 1; fi
      else bad "API Billing Budgets inactive"; return 1; fi
    else
      bad "Acces aux budgets refuse ou API indisponible. Si 403 persiste avec x-goog-user-project, verifier serviceusage.services.use sur le projet quota et billing.budgets.list sur le compte de facturation; aucun droit ajoute automatiquement."
      return 1
    fi
  fi
  listing="$(cat "$body_file")"
  rm -f "$body_file"
  # Nom fixe + filtre projet pour eviter les doublons. Ne jamais modifier un budget preexistant automatiquement.
  existing="$(printf '%s' "$listing" | python3 -c 'import json,sys; d=json.load(sys.stdin); p=sys.argv[1]; print(next((x["name"] for x in d.get("budgets",[]) if x.get("displayName")=="Boussole DEV - 30 EUR" and ("projects/"+p) in x.get("budgetFilter",{}).get("projects",[])), ""))' "$NUMBER")"
  if [[ -n "$existing" ]]; then
    check="$(printf '%s' "$listing" | python3 -c 'import json,sys; d=json.load(sys.stdin); name=sys.argv[1]; b=next(x for x in d.get("budgets",[]) if x["name"]==name); a=b.get("amount",{}).get("specifiedAmount",{}); t=sorted(float(x["thresholdPercent"]) for x in b.get("thresholdRules",[])); print("ok" if a.get("currencyCode")=="EUR" and str(a.get("units"))=="30" and t==[0.5,0.8,1.0] and b.get("budgetFilter",{}).get("calendarPeriod")=="MONTH" else "mismatch")' "$existing")"
    if [[ "$check" == ok ]]; then ok "Budget DEV existant conforme: 30 EUR/mois, 50/80/100"; else bad "Budget DEV existant non conforme; correction manuelle necessaire: $existing"; fi
    return
  fi
  warn "Budget DEV absent (30 EUR/mois, alertes 15/24/30 EUR)"
  if [[ "$MODE" != auto && "$MODE" != setup ]]; then return; fi
  if ! ask "Creer le budget mensuel de 30 EUR sur le compte $account pour le projet $PROJECT (alertes, pas de plafond) ?"; then
    warn "Creation du budget non autorisee"; return
  fi
  payload="$(python3 -c 'import json,sys; p=sys.argv[1]; print(json.dumps({"displayName":"Boussole DEV - 30 EUR","budgetFilter":{"projects":["projects/"+p],"calendarPeriod":"MONTH"},"amount":{"specifiedAmount":{"currencyCode":"EUR","units":"30"}},"thresholdRules":[{"thresholdPercent":0.5},{"thresholdPercent":0.8},{"thresholdPercent":1.0}]}))' "$NUMBER")"
  response="$(curl --silent --show-error --fail -X POST -H "Authorization: Bearer $token" -H "x-goog-user-project: $PROJECT" -H 'Content-Type: application/json' --data "$payload" "$endpoint" 2>&1)" || {
    bad "Creation budget impossible: verifier API Billing Budgets et permission billing.budgets.create"; return 1;
  }
  if printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("name") and d.get("amount",{}).get("specifiedAmount",{}).get("currencyCode")=="EUR" else 1)'; then
    ok "Budget mensuel 30 EUR cree avec seuils 50/80/100"
  else bad "Reponse inattendue apres creation du budget"; fi
}

budget_dev

say "Tests avant deploiement"
if [[ "${PLAN_OK:-0}" == 1 ]]; then ok "GitHub Actions PLAN confirme"; else warn "Relancer le mode auto pour confirmer le PLAN avant deploiement"; fi
if [[ "$FAIL" == 0 ]]; then ok "Aucun echec detecte dans les controles executes"; else warn "Des controles ont echoue; aucun apply autorise"; fi

say "Controle des risques restants"
if [[ "${PLAN_OK:-0}" != 1 ]]; then warn "Retirer l ancien WIF seulement apres PLAN reussi"; fi
warn "Verifier les notifications du budget dans Cloud Billing; alertes non bloquantes"
warn "Aucun deploiement Terraform n est effectue par ce script"
