variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "environment" {
  description = "Environment/platform name."
  type        = string
}

variable "node_service_account_id" {
  description = "Account ID for the dedicated GKE node service account."
  type        = string
  default     = "devsecops-gke-node"

  validation {
    condition     = length(var.node_service_account_id) >= 6 && length(var.node_service_account_id) <= 30
    error_message = "Google service account IDs must be between 6 and 30 characters."
  }
}
