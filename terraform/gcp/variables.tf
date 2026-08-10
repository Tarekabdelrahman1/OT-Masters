variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Prefix used for the shared DevSecOps platform."
  type        = string
  default     = "devsecops"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "devsecops-gke"
}

variable "node_locations" {
  description = "Zones used by worker nodes."
  type        = list(string)
  default = [
    "europe-west1-b",
    "europe-west1-c"
  ]
}

variable "admin_cidr" {
  description = "Public IPv4 CIDR of your local admin workstation/router, e.g. 203.0.113.10/32."
  type        = string
}

variable "node_ipv4_cidr" {
  description = "Primary subnet CIDR for GKE nodes."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pod_ipv4_cidr" {
  description = "Secondary subnet CIDR for GKE Pods."
  type        = string
  default     = "10.20.0.0/16"
}

variable "service_ipv4_cidr" {
  description = "Secondary subnet CIDR for Kubernetes Services."
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_ipv4_cidr" {
  description = "Private /28 CIDR for the GKE control plane."
  type        = string
  default     = "172.16.0.0/28"
}

variable "flow_log_sampling" {
  description = "VPC Flow Log sample rate."
  type        = number
  default     = 0.5
}

variable "enable_private_endpoint" {
  description = "When true, disable the public GKE control-plane endpoint."
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"
}

variable "machine_type" {
  description = "GKE node machine type."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "GKE node boot disk size."
  type        = number
  default     = 80
}

variable "node_pool_total_min" {
  description = "Minimum total number of GKE worker nodes."
  type        = number
  default     = 2
}

variable "node_pool_total_max" {
  description = "Maximum total number of GKE worker nodes."
  type        = number
  default     = 6
}

variable "deletion_protection" {
  description = "Protect GKE from accidental Terraform deletion."
  type        = bool
  default     = false
}
