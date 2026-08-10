module "network" {
  source = "../modules/network"

  project_id = var.project_id
  region     = var.region

  network_name = "${var.environment}-vpc"
  subnet_name  = "${var.environment}-gke-subnet"

  node_ipv4_cidr = var.node_ipv4_cidr

  pods_range_name = "${var.environment}-pods"
  pod_ipv4_cidr   = var.pod_ipv4_cidr

  services_range_name = "${var.environment}-services"
  service_ipv4_cidr   = var.service_ipv4_cidr

  flow_log_sampling = var.flow_log_sampling

  depends_on = [
    google_project_service.required
  ]
}

module "gcp_iam" {
  source = "../modules/gcp-iam"

  project_id  = var.project_id
  environment = var.environment

  node_service_account_id = "${var.environment}-gke-node"

  depends_on = [
    google_project_service.required
  ]
}

module "gke" {
  source = "../modules/gke"

  project_id = var.project_id
  region     = var.region

  cluster_name   = var.cluster_name
  node_locations = var.node_locations

  network_id = module.network.network_id
  subnet_id  = module.network.subnet_id

  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name

  master_ipv4_cidr        = var.master_ipv4_cidr
  enable_private_endpoint = var.enable_private_endpoint

  master_authorized_networks = {
    admin-workstation = var.admin_cidr
  }

  node_service_account_email = module.gcp_iam.node_service_account_email

  release_channel     = var.release_channel
  machine_type        = var.machine_type
  node_disk_size_gb   = var.node_disk_size_gb
  node_pool_total_min = var.node_pool_total_min
  node_pool_total_max = var.node_pool_total_max
  deletion_protection = var.deletion_protection

  cluster_labels = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "devsecops-master"
  }

  node_labels = {
    environment = var.environment
    node-role   = "platform"
  }

  depends_on = [
    google_project_service.required,
    module.gcp_iam,
    module.network
  ]
}
