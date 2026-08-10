resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  node_locations = var.node_locations

  network    = var.network_id
  subnetwork = var.subnet_id

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks

      content {
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }

    gcp_public_cidrs_access_enabled = false
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  datapath_provider = "ADVANCED_DATAPATH"

  enable_shielded_nodes = true

  release_channel {
    channel = var.release_channel
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
      "WORKLOADS"
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS"
    ]

    managed_prometheus {
      enabled = false
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_DISABLED"
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  resource_labels = var.cluster_labels

  deletion_protection = var.deletion_protection
}

resource "google_container_node_pool" "primary" {
  project  = var.project_id
  name     = "${var.cluster_name}-primary"
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations = var.node_locations

  # For regional clusters this is per-zone at creation time.
  # With two node_locations, 1 creates two initial nodes.
  initial_node_count = 1

  autoscaling {
    total_min_node_count = var.node_pool_total_min
    total_max_node_count = var.node_pool_total_max
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.machine_type
    image_type   = "COS_CONTAINERD"
    disk_type    = "pd-balanced"
    disk_size_gb = var.node_disk_size_gb

    service_account = var.node_service_account_email

    # IAM roles remain the actual authorization boundary.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    kubelet_config {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }

    labels = var.node_labels
    tags   = var.node_network_tags
  }
}
