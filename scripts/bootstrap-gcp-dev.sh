#!/usr/bin/env bash
set -euo pipefail

# Bootstrap for an EXISTING, manually created GCP DEV project.
DEV_PROJECT_ID="${DEV_PROJECT_ID:-mer-boussole-dev}"
GITHUB_REPO="${GITHUB_REPO:-Photon53/boussole-maitrise-plus}"
REGION="${REGION:-europe-west9}"
STATE_BUCKET="${STATE_BUCKET:-${DEV_PROJECT_ID}-tfstate}"
EXPECTED_PROJECT="mer-boussole-dev"
if [[ "$DEV_PROJECT_ID" != "$EXPECTED_PROJECT" ]]; then
  echo "Refusing to configure any project other than $EXPECTED_PROJECT" >&2; exit 1
fi
command -v gcloud >/dev/null || { echo "Install gcloud first"; exit 1; }
gcloud projects describe "$DEV_PROJECT_ID" >/dev/null || {
  echo "DEV project does not exist or is inaccessible"; exit 1;
}
BILLING_ENABLED="$(gcloud billing projects describe "$DEV_PROJECT_ID" --format='value(billingEnabled)')"
[[ "$BILLING_ENABLED" == "True" || "$BILLING_ENABLED" == "true" ]] || {
  echo "Billing must be enabled on DEV project"; exit 1;
}
echo "Project: $DEV_PROJECT_ID; repository: $GITHUB_REPO; bucket: $STATE_BUCKET"
read -r -p "Type mer-boussole-dev to authorize DEV-only bootstrap: " CONFIRM
[[ "$CONFIRM" == "$EXPECTED_PROJECT" ]] || exit 1

gcloud services enable --project="$DEV_PROJECT_ID" \
  compute.googleapis.com iam.googleapis.com iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  artifactregistry.googleapis.com iap.googleapis.com storage.googleapis.com \
  sts.googleapis.com

if gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  OWNER="$(gcloud storage buckets describe "gs://$STATE_BUCKET" --format='value(projectNumber)')"
  NUMBER="$(gcloud projects describe "$DEV_PROJECT_ID" --format='value(projectNumber)')"
  [[ "$OWNER" == "$NUMBER" ]] || { echo "Bucket exists in another project; refusing"; exit 1; }
else
  gcloud storage buckets create "gs://$STATE_BUCKET" \
    --project="$DEV_PROJECT_ID" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention
fi
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning

SA="boussole-dev-terraform@$DEV_PROJECT_ID.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SA" --project="$DEV_PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create boussole-dev-terraform \
    --project="$DEV_PROJECT_ID" --display-name="GitHub Terraform DEV"
fi

# These roles apply ONLY to the explicitly checked DEV project.
# Review and reduce IAM permissions after first successful provisioning.
for ROLE in roles/compute.admin roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser roles/artifactregistry.admin \
  roles/iap.admin roles/resourcemanager.projectIamAdmin; do
  gcloud projects add-iam-policy-binding "$DEV_PROJECT_ID" \
    --member="serviceAccount:$SA" --role="$ROLE" --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://$STATE_BUCKET" \
  --member="serviceAccount:$SA" --role=roles/storage.objectAdmin >/dev/null

POOL="github-dev"
if ! gcloud iam workload-identity-pools describe "$POOL" \
  --project="$DEV_PROJECT_ID" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$POOL" \
    --project="$DEV_PROJECT_ID" --location=global --display-name="GitHub DEV"
fi
PROJECT_NUMBER="$(gcloud projects describe "$DEV_PROJECT_ID" --format='value(projectNumber)')"
PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/providers/github"
# A pre-existing provider may be used by other workflows: refuse to overwrite it.
if gcloud iam workload-identity-pools providers describe github \
  --project="$DEV_PROJECT_ID" --location=global \
  --workload-identity-pool="$POOL" >/dev/null 2>&1; then
  echo "Existing OIDC provider found. Review its attribute condition manually."
  echo "It MUST restrict repository=$GITHUB_REPO and ref=refs/heads/develop."
  exit 1
fi
gcloud iam workload-identity-pools providers create-oidc github \
  --project="$DEV_PROJECT_ID" --location=global --workload-identity-pool="$POOL" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='$GITHUB_REPO' && assertion.ref=='refs/heads/develop'"
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --project="$DEV_PROJECT_ID" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/attribute.repository/$GITHUB_REPO"

cat <<EOF
Bootstrap complete. Configure GitHub Environment 'development' (restricted to develop):
GCP_DEV_PROJECT_ID=$DEV_PROJECT_ID
GCP_DEV_SERVICE_ACCOUNT=$SA
GCP_WIF_PROVIDER=$PROVIDER
TF_STATE_BUCKET=$STATE_BUCKET
GCP_DEV_ADMIN_MEMBERS_JSON=["user:YOUR_EMAIL"]
EOF
