resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  project       = var.project_id
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.node_ipv4_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = var.pods_range_name
    ip_cidr_range = var.pod_ipv4_cidr
  }

  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.service_ipv4_cidr
  }

  log_config {
    aggregation_interval = var.flow_log_aggregation_interval
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_address" "nat" {
  project      = var.project_id
  name         = "${var.network_name}-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project = var.project_id
  name    = "${var.network_name}-nat"
  router  = google_compute_router.this.name
  region  = var.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.nat.self_link]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
