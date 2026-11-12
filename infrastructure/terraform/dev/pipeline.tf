// Pipeline applicatif DEV (ticket #65, PR 1) : identité de publication, bucket des versions et
// des sauvegardes, droits Artifact Registry, nettoyage des images (simulation).
//
// - Le fournisseur WIF et le compte boussole-dev-tf-plan sont gérés hors Terraform, par
//   scripts/wif-dev-comptes-separes.sh (identités d'amorçage). Ce fichier suppose que le
//   fournisseur publie l'attribut attribute.boussole_role (« tf-plan » ou « deployer »).
// - Aucun accès PROD. Tout apply exige une approbation explicite (scripts/terraform-dev-cloudshell.sh).

variable "wif_pool_id" {
  type        = string
  default     = "github-dev"
  description = "Pool Workload Identity Federation GitHub du projet DEV"
}

variable "backup_retention_days" {
  type        = number
  default     = 60
  description = "Durée de conservation des sauvegardes PostgreSQL et fichiers (préfixe backups/)"
}

data "google_project" "dev" {}

locals {
  wif_pool_name    = "projects/${data.google_project.dev.number}/locations/global/workloadIdentityPools/${var.wif_pool_id}"
  deploiement_name = "${var.project_id}-deploiement"
  objets_releases  = "projects/_/buckets/${local.deploiement_name}/objects/releases/"
  objets_backups   = "projects/_/buckets/${local.deploiement_name}/objects/backups/"
}

// --- Identité de publication (GitHub Actions dev-deploy.yml) -----------------------------------

resource "google_service_account" "deployer" {
  account_id   = "boussole-dev-deployer"
  display_name = "Boussole DEV - publication des versions"
  description  = "Utilisable uniquement par .github/workflows/dev-deploy.yml sur develop (WIF attribute.boussole_role=deployer). Aucun rôle d'administration GCP."
}

// Seuls les jetons dont le fournisseur a calculé boussole_role=deployer peuvent emprunter ce compte.
// Le workflow Terraform (boussole_role=tf-plan) ne le peut pas, et réciproquement.
resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.boussole_role/deployer"
}

resource "google_artifact_registry_repository_iam_member" "deployer_writer" {
  location   = google_artifact_registry_repository.dev.location
  repository = google_artifact_registry_repository.dev.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_artifact_registry_repository_iam_member" "vm_reader" {
  location   = google_artifact_registry_repository.dev.location
  repository = google_artifact_registry_repository.dev.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.vm.email}"
}

// --- Bucket DEV : releases/ (manifestes + pointeur) et backups/ (sauvegardes de la VM) ----------

resource "google_storage_bucket" "deploiement" {
  name                        = local.deploiement_name
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  // Historique du pointeur releases/desired.json et protection contre l'écrasement accidentel.
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age            = var.backup_retention_days
      matches_prefix = ["backups/"]
    }
    action {
      type = "Delete"
    }
  }

  // Versions remplacées ou supprimées (anciens pointeurs, sauvegardes expirées) : purgées après 30 jours.
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environnement = "dev"
    usage         = "deploiement"
  }
}

// Les conditions IAM par préfixe ne s'appliquent pas à storage.objects.list (opération sur le bucket) :
// la liste est donc refusée à ces comptes ; les scripts lisent des noms d'objets connus.

// Publication : créer / lire / remplacer (précondition de génération) dans releases/ uniquement.
resource "google_storage_bucket_iam_member" "deployer_releases" {
  bucket = google_storage_bucket.deploiement.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.deployer.email}"
  condition {
    title       = "releases-seulement"
    description = "Manifestes immuables releases/<sha>.json et pointeur releases/desired.json"
    expression  = "resource.name.startsWith(\"${local.objets_releases}\")"
  }
}

// VM : lecture des versions et des sauvegardes (restauration), écriture des sauvegardes sans suppression.
resource "google_storage_bucket_iam_member" "vm_lecture" {
  bucket = google_storage_bucket.deploiement.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.vm.email}"
  condition {
    title       = "releases-et-backups-lecture"
    description = "Lecture du pointeur, des manifestes et des sauvegardes"
    expression  = "resource.name.startsWith(\"${local.objets_releases}\") || resource.name.startsWith(\"${local.objets_backups}\")"
  }
}

resource "google_storage_bucket_iam_member" "vm_sauvegardes" {
  bucket = google_storage_bucket.deploiement.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.vm.email}"
  condition {
    title       = "backups-ecriture"
    description = "Création des sauvegardes ; la rétention est gérée par le cycle de vie du bucket"
    expression  = "resource.name.startsWith(\"${local.objets_backups}\")"
  }
}

output "deployer_service_account" { value = google_service_account.deployer.email }
output "deploiement_bucket" { value = google_storage_bucket.deploiement.name }
output "deployer_wif_principal" { value = google_service_account_iam_member.deployer_wif.member }
