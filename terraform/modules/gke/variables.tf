variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the regional GKE control plane."
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
}

variable "node_locations" {
  description = "Zones used for worker nodes in the regional cluster."
  type        = list(string)

  validation {
    condition     = length(var.node_locations) >= 2
    error_message = "Use at least two node locations for this lab's regional architecture."
  }
}

variable "network_id" {
  description = "VPC network resource ID."
  type        = string
}

variable "subnet_id" {
  description = "GKE subnet resource ID."
  type        = string
}

variable "pods_range_name" {
  description = "Existing secondary subnet range used for Pods."
  type        = string
}

variable "services_range_name" {
  description = "Existing secondary subnet range used for Services."
  type        = string
}

variable "master_ipv4_cidr" {
  description = "Private /28 CIDR used by the GKE control plane."
  type        = string
  default     = "172.16.0.0/28"
}

variable "enable_private_endpoint" {
  description = "Disable the public control-plane endpoint when true."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "Map of names to CIDRs permitted to use the public GKE control-plane endpoint."
  type        = map(string)
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, STABLE, or EXTENDED."
  }
}

variable "node_service_account_email" {
  description = "Dedicated GCP service account used by GKE nodes."
  type        = string
}

variable "machine_type" {
  description = "Machine type for the primary node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size for each GKE worker node."
  type        = number
  default     = 80
}

variable "node_pool_total_min" {
  description = "Minimum total number of worker nodes."
  type        = number
  default     = 2
}

variable "node_pool_total_max" {
  description = "Maximum total number of worker nodes."
  type        = number
  default     = 6
}

variable "cluster_labels" {
  description = "Resource labels for the GKE cluster."
  type        = map(string)
  default     = {}
}

variable "node_labels" {
  description = "Kubernetes labels added to GKE nodes."
  type        = map(string)
  default     = {}
}

variable "node_network_tags" {
  description = "Compute Engine network tags placed on GKE nodes."
  type        = list(string)
  default     = ["gke-devsecops"]
}

variable "deletion_protection" {
  description = "Protect the GKE cluster from accidental Terraform deletion."
  type        = bool
  default     = false
}
