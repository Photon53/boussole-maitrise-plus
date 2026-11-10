#!/usr/bin/env bash
set -euo pipefail
: "${DEV_PROJECT_ID:?Set DEV_PROJECT_ID (new unique project id)}"
: "${BILLING_ACCOUNT_ID:?Set BILLING_ACCOUNT_ID}"
: "${GITHUB_REPO:=Photon53/boussole-maitrise-plus}"
: "${REGION:=europe-west9}"
: "${STATE_BUCKET:=${DEV_PROJECT_ID}-tfstate}"
echo "TARGET NEW DEV PROJECT: $DEV_PROJECT_ID"
echo "BILLING ACCOUNT: $BILLING_ACCOUNT_ID"
echo "REPOSITORY: $GITHUB_REPO"
read -r -p "Type the DEV project ID to authorize creation: " CONFIRM
test "$CONFIRM" = "$DEV_PROJECT_ID" || { echo "Confirmation mismatch"; exit 1; }
if gcloud projects describe "$DEV_PROJECT_ID" >/dev/null 2>&1; then
  echo "Project already exists: refusing bootstrap to prevent accidental changes" >&2
  exit 1
fi
gcloud projects create "$DEV_PROJECT_ID" --name="Boussole Maitrise DEV"
gcloud billing projects link "$DEV_PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
gcloud services enable --project="$DEV_PROJECT_ID" \
  compute.googleapis.com iam.googleapis.com iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  artifactregistry.googleapis.com iap.googleapis.com storage.googleapis.com \
  sts.googleapis.com
gcloud storage buckets create "gs://$STATE_BUCKET" \
  --project="$DEV_PROJECT_ID" --location="$REGION" --uniform-bucket-level-access \
  --public-access-prevention
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
gcloud iam service-accounts create boussole-dev-terraform \
  --project="$DEV_PROJECT_ID" --display-name="GitHub Terraform DEV"
SA="boussole-dev-terraform@$DEV_PROJECT_ID.iam.gserviceaccount.com"
# Bootstrap-only privileges scoped to the NEW DEV project.
for ROLE in roles/compute.admin roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser roles/artifactregistry.admin roles/iap.admin \
  roles/resourcemanager.projectIamAdmin; do
  gcloud projects add-iam-policy-binding "$DEV_PROJECT_ID" \
    --member="serviceAccount:$SA" --role="$ROLE" --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://$STATE_BUCKET" \
  --member="serviceAccount:$SA" --role="roles/storage.objectAdmin" >/dev/null
gcloud iam workload-identity-pools create github-dev \
  --project="$DEV_PROJECT_ID" --location=global --display-name="GitHub DEV"
PROJECT_NUMBER="$(gcloud projects describe "$DEV_PROJECT_ID" --format='value(projectNumber)')"
gcloud iam workload-identity-pools providers create-oidc github \
  --project="$DEV_PROJECT_ID" --location=global \
  --workload-identity-pool=github-dev \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='$GITHUB_REPO' && assertion.ref=='refs/heads/infra/gcp-dev-bootstrap'"
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --project="$DEV_PROJECT_ID" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-dev/attribute.repository/$GITHUB_REPO"
echo "Set GitHub Environment 'development' variables:"
echo "GCP_DEV_PROJECT_ID=$DEV_PROJECT_ID"
echo "GCP_DEV_SERVICE_ACCOUNT=$SA"
echo "GCP_WIF_PROVIDER=projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-dev/providers/github"
echo "TF_STATE_BUCKET=$STATE_BUCKET"
echo "Then require reviewers on the development environment before apply."
