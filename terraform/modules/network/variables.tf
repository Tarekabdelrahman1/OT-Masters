variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "network_name" {
  description = "Name of the custom VPC."
  type        = string
}

variable "subnet_name" {
  description = "Name of the GKE subnet."
  type        = string
}

variable "node_ipv4_cidr" {
  description = "Primary IPv4 range used by GKE nodes."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the subnet secondary range used by GKE Pods."
  type        = string
}

variable "pod_ipv4_cidr" {
  description = "Secondary IPv4 range used by GKE Pods."
  type        = string
}

variable "services_range_name" {
  description = "Name of the subnet secondary range used by Kubernetes Services."
  type        = string
}

variable "service_ipv4_cidr" {
  description = "Secondary IPv4 range used by Kubernetes Services."
  type        = string
}

variable "flow_log_aggregation_interval" {
  description = "Aggregation interval for VPC Flow Logs."
  type        = string
  default     = "INTERVAL_5_SEC"

  validation {
    condition = contains([
      "INTERVAL_5_SEC",
      "INTERVAL_30_SEC",
      "INTERVAL_1_MIN",
      "INTERVAL_5_MIN",
      "INTERVAL_10_MIN",
      "INTERVAL_15_MIN"
    ], var.flow_log_aggregation_interval)
    error_message = "Use a supported VPC Flow Logs aggregation interval."
  }
}

variable "flow_log_sampling" {
  description = "Fraction of network flows to sample, from 0.0 to 1.0."
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling >= 0 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling must be between 0 and 1."
  }
}
