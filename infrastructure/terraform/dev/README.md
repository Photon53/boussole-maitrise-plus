# GCP DEV bootstrap (no production changes)

This is an infrastructure-only starting point, NOT an application deployment.
It creates a private Ubuntu VM (no public IP), Cloud NAT, IAP SSH access,
Artifact Registry and a dedicated service account in a NEW GCP project.

## Preconditions
- A billing account and permissions to create/link a NEW GCP project.
- gcloud authenticated with a bootstrap administrator.
- GitHub Actions Environment `development` with required reviewers.
- Environment variables: GCP_DEV_PROJECT_ID, GCP_DEV_SERVICE_ACCOUNT,
  GCP_WIF_PROVIDER, TF_STATE_BUCKET, GCP_DEV_ADMIN_MEMBERS_JSON
  (JSON array, e.g. ["user:admin@example.com"]).
- The OIDC provider only trusts branch infra/gcp-dev-bootstrap.
- Use a unique state bucket name; it must not already exist.
- Budget alerts and organization policies must be configured separately.
- This initial workflow does not build/deploy the application or initialize PostgreSQL.
- Terraform service account has bootstrap-level roles within DEV; tighten
  permissions after initial provisioning.
- No public HTTP/HTTPS ingress is opened; use IAP for administration.
- Before merging this branch, redesign the OIDC ref condition and workflow
  branch guard together. Never broaden it to production.

## One-time setup
```bash
export DEV_PROJECT_ID="your-new-project-id"
export BILLING_ACCOUNT_ID="XXXXXX-XXXXXX-XXXXXX"
bash scripts/bootstrap-gcp-dev.sh
```
Then set GitHub environment variables and trigger workflow from the feature branch.
Start with `plan`, inspect output, then `apply` after approval.

## Follow-up work
Pin GitHub Actions to audited commit SHAs; add policy checks, separate
deployment identity, secure HTTPS access, application Docker build and smoke
tests, automated backups and restoration drill, budgets, monitoring.
Do not store student or production data in DEV.
