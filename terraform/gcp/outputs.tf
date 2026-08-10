output "network_name" {
  value = module.network.network_name
}

output "subnet_name" {
  value = module.network.subnet_name
}

output "nat_public_ip" {
  description = "Put this IP /32 into the AWS ECR stack as jenkins_source_cidrs."
  value       = module.network.nat_ip_address
}

output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_region" {
  value = module.gke.cluster_location
}

output "workload_identity_pool" {
  value = module.gke.workload_identity_pool
}

output "gke_node_service_account" {
  value = module.gcp_iam.node_service_account_email
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${module.gke.cluster_location} --project ${var.project_id}"
}
