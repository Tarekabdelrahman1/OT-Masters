variable "repository_name" {
  description = "Amazon ECR repository name."
  type        = string
}

variable "jenkins_iam_user_name" {
  description = "IAM user used by the CI flow until we replace static credentials with federation."
  type        = string
}

variable "jenkins_source_cidrs" {
  description = "CIDRs from which the Jenkins ECR identity is allowed to call AWS APIs. Use the GCP Cloud NAT public IP /32."
  type        = list(string)

  validation {
    condition     = length(var.jenkins_source_cidrs) > 0
    error_message = "At least one Jenkins source CIDR is required."
  }
}

variable "untagged_image_expiry_days" {
  description = "Delete untagged ECR images older than this number of days."
  type        = number
  default     = 7
}

variable "max_images" {
  description = "Maximum number of images retained in ECR."
  type        = number
  default     = 50
}

variable "manage_registry_scanning" {
  description = "Manage AWS ECR registry-level enhanced scanning configuration."
  type        = bool
  default     = true
}

variable "tags" {
  description = "AWS resource tags."
  type        = map(string)
  default     = {}
}
