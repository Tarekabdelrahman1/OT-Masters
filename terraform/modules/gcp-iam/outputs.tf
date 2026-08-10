output "node_service_account_email" {
  description = "Email of the dedicated GKE node service account."
  value       = google_service_account.gke_node.email
}

output "node_service_account_name" {
  description = "Full resource name of the GKE node service account."
  value       = google_service_account.gke_node.name
}
