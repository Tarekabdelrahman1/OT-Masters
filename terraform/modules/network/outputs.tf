output "network_id" {
  description = "VPC network resource ID."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "GKE subnet resource ID."
  value       = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  description = "GKE subnet name."
  value       = google_compute_subnetwork.gke.name
}

output "pods_range_name" {
  description = "GKE Pod secondary range name."
  value       = var.pods_range_name
}

output "services_range_name" {
  description = "Kubernetes Service secondary range name."
  value       = var.services_range_name
}

output "nat_ip_address" {
  description = "Static public egress IP used by Cloud NAT."
  value       = google_compute_address.nat.address
}

output "router_name" {
  description = "Cloud Router name."
  value       = google_compute_router.this.name
}

output "nat_name" {
  description = "Cloud NAT name."
  value       = google_compute_router_nat.this.name
}
