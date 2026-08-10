resource "google_service_account" "gke_node" {
  project      = var.project_id
  account_id   = var.node_service_account_id
  display_name = "GKE node service account for ${var.environment}"
  description  = "Dedicated least-privilege identity for GKE node system tasks."
}

resource "google_project_iam_member" "gke_node_default_role" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}
