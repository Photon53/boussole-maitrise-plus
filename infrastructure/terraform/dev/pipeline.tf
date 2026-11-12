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

variable "tf_plan_service_account" {
  type        = string
  default     = ""
  description = "Compte du workflow Terraform PLAN (créé hors Terraform) ; vide = boussole-dev-tf-plan@<projet>"
}

data "google_project" "dev" {}

locals {
  wif_pool_name    = "projects/${data.google_project.dev.number}/locations/global/workloadIdentityPools/${var.wif_pool_id}"
  deploiement_name = "${var.project_id}-deploiement"
  objets_releases  = "projects/_/buckets/${local.deploiement_name}/objects/releases/"
  objets_backups   = "projects/_/buckets/${local.deploiement_name}/objects/backups/"
  tf_plan_email    = var.tf_plan_service_account != "" ? var.tf_plan_service_account : "boussole-dev-tf-plan@${var.project_id}.iam.gserviceaccount.com"
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

// --- Politique IAM du bucket : faisant autorité (ticket #65, PR 3a) -----------------------------
//
// La politique ci-dessous REMPLACE toute la politique du bucket. Elle retire les liaisons historiques
// créées par défaut (projectViewer -> legacyBucketReader / legacyObjectReader ; projectEditor ->
// legacyBucketOwner / legacyObjectOwner ; projectOwner -> legacyObjectOwner) : sans cela, tout compte ayant
// roles/viewer ou roles/editor sur le projet (boussole-dev-tf-plan, compte Compute par défaut) pourrait lire
// les sauvegardes de backups/. Seule projectOwner -> legacyBucketOwner est conservée (décision du 12/11). Tout ajout de droit sur ce bucket passe désormais par ce bloc : une liaison
// créée ailleurs (console, gcloud, autre ressource Terraform) serait retirée au prochain apply.
//
// storage.objects.list porte sur le bucket : la condition par préfixe d'objet ne s'y applique pas, la
// liste est donc refusée à ces comptes ; les scripts accèdent aux objets par leur nom exact.
data "google_iam_policy" "deploiement" {
  // Propriétaires du projet : gestion du bucket et de sa politique (storage.buckets.get, update,
  // getIamPolicy, setIamPolicy), que roles/owner ne contient pas. Indispensable aux plans et apply Terraform
  // du propriétaire et au retour arrière. Ce rôle ne permet pas de lire le contenu des objets
  // (pas de storage.objects.get) ; il permet de les lister, créer et supprimer.
  binding {
    role    = "roles/storage.legacyBucketOwner"
    members = ["projectOwner:${var.project_id}"]
  }

  // PLAN Terraform : lecture des métadonnées du bucket (storage.buckets.get), qu'il tenait jusqu'ici de la
  // liaison historique projectViewer -> legacyBucketReader. Aucun accès aux objets ; la lecture de la
  // politique IAM (storage.buckets.getIamPolicy) vient de roles/iam.securityReviewer sur le projet.
  binding {
    role    = "roles/storage.bucketViewer"
    members = ["serviceAccount:${local.tf_plan_email}"]
  }

  // Publication : créer / lire / remplacer (précondition de génération) dans releases/ uniquement.
  binding {
    role    = "roles/storage.objectUser"
    members = ["serviceAccount:${google_service_account.deployer.email}"]
    condition {
      title       = "releases-seulement"
      description = "Manifestes immuables releases/<sha>.json et pointeur releases/desired.json"
      expression  = "resource.name.startsWith(\"${local.objets_releases}\")"
    }
  }

  // VM : lecture des versions et des sauvegardes (restauration).
  binding {
    role    = "roles/storage.objectViewer"
    members = ["serviceAccount:${google_service_account.vm.email}"]
    condition {
      title       = "releases-et-backups-lecture"
      description = "Lecture du pointeur, des manifestes et des sauvegardes"
      expression  = "resource.name.startsWith(\"${local.objets_releases}\") || resource.name.startsWith(\"${local.objets_backups}\")"
    }
  }

  // VM : écriture des sauvegardes sans suppression ni remplacement.
  binding {
    role    = "roles/storage.objectCreator"
    members = ["serviceAccount:${google_service_account.vm.email}"]
    condition {
      title       = "backups-ecriture"
      description = "Création des sauvegardes ; la rétention est gérée par le cycle de vie du bucket"
      expression  = "resource.name.startsWith(\"${local.objets_backups}\")"
    }
  }
}

resource "google_storage_bucket_iam_policy" "deploiement" {
  bucket      = google_storage_bucket.deploiement.name
  policy_data = data.google_iam_policy.deploiement.policy_data
}

// Les trois liaisons étaient gérées une à une jusqu'à la PR 3a. Elles sortent de l'état SANS être
// détruites : sinon Terraform pourrait retirer ces droits après la pose de la politique ci-dessus.
// La politique faisant autorité les reprend à l'identique.
removed {
  from = google_storage_bucket_iam_member.deployer_releases
  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket_iam_member.vm_lecture
  lifecycle {
    destroy = false
  }
}

removed {
  from = google_storage_bucket_iam_member.vm_sauvegardes
  lifecycle {
    destroy = false
  }
}

output "deployer_service_account" { value = google_service_account.deployer.email }
output "deploiement_bucket" { value = google_storage_bucket.deploiement.name }
output "deployer_wif_principal" { value = google_service_account_iam_member.deployer_wif.member }
