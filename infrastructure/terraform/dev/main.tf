terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
  backend "gcs" {}
}
provider "google" {
  project = var.project_id
  region  = var.region
}
variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west9"
}
variable "zone" {
  type    = string
  default = "europe-west9-a"
}
// Profil DEV economique. L arret programme et les couts doivent etre valides avant apply.
variable "machine_type" {
  type    = string
  default = "e2-medium"
}
variable "admin_members" {
  type        = list(string)
  description = "IAM principals allowed to connect via IAP; e.g. user:someone@example.com"
}
resource "google_compute_network" "dev" {
  name                    = "boussole-dev-vpc"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "dev" {
  name                     = "boussole-dev-subnet"
  ip_cidr_range            = "10.80.0.0/24"
  region                   = var.region
  network                  = google_compute_network.dev.id
  private_ip_google_access = true
}
resource "google_compute_router" "dev" {
  name    = "boussole-dev-router"
  network = google_compute_network.dev.id
  region  = var.region
}
resource "google_compute_router_nat" "dev" {
  name                               = "boussole-dev-nat"
  router                             = google_compute_router.dev.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
resource "google_compute_firewall" "iap_ssh" {
  name          = "boussole-dev-iap-ssh"
  network       = google_compute_network.dev.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["boussole-dev"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
resource "google_service_account" "vm" {
  account_id   = "boussole-dev-vm"
  display_name = "Boussole DEV VM"
}
resource "google_compute_instance" "dev" {
  name         = "boussole-dev"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["boussole-dev"]
  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      size  = 30
      type  = "pd-standard"
    }
  }
  network_interface { subnetwork = google_compute_subnetwork.dev.id }
  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }
  metadata                = { enable-oslogin = "TRUE" }
  metadata_startup_script = file("${path.module}/startup.sh")
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}
resource "google_project_iam_member" "iap" {
  for_each = toset(var.admin_members)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}
resource "google_project_iam_member" "oslogin" {
  for_each = toset(var.admin_members)
  project  = var.project_id
  role     = "roles/compute.osLogin"
  member   = each.value
}
resource "google_artifact_registry_repository" "dev" {
  location      = var.region
  repository_id = "boussole-dev"
  format        = "DOCKER"
  description   = "Development images only"

  // Ticket #65 : simulation d'abord (aucune suppression réelle tant que dry_run = true).
  // Seules les images SANS tag sont candidates ; les tags SHA (versions active, précédente,
  // figée) ne sont jamais supprimés par ces règles. Le retrait des anciens tags SHA sera un
  // mécanisme explicite et documenté (PR 4), après démonstration.
  cleanup_policy_dry_run = true
  cleanup_policies {
    id     = "supprimer-sans-tag-7j"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }
  cleanup_policies {
    id     = "garder-20-dernieres"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }
}
output "vm_name" { value = google_compute_instance.dev.name }
output "registry" { value = google_artifact_registry_repository.dev.id }
output "connect_command" { value = "gcloud compute ssh boussole-dev --zone=${var.zone} --tunnel-through-iap --project=${var.project_id}" }
