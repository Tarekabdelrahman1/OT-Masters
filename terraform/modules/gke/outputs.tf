output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "GKE cluster region."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "GKE API endpoint."
  value       = google_container_cluster.this.endpoint
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool used by the cluster."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_pool_name" {
  description = "Primary GKE node pool name."
  value       = google_container_node_pool.primary.name
}
