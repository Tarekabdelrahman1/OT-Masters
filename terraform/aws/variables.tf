variable "aws_region" {
  description = "AWS region containing ECR."
  type        = string
  default     = "eu-central-1"
}

variable "repository_name" {
  description = "ECR repository name."
  type        = string
  default     = "devsecops-webapp"
}

variable "jenkins_iam_user_name" {
  description = "Temporary IAM-user based Jenkins identity. We will later replace this with federation."
  type        = string
  default     = "jenkins-devsecops-ecr"
}

variable "jenkins_source_cidrs" {
  description = "Allowed source CIDRs for Jenkins AWS API calls. Use the GCP Cloud NAT IP /32."
  type        = list(string)
}

variable "untagged_image_expiry_days" {
  description = "Delete untagged images after this many days."
  type        = number
  default     = 7
}

variable "max_images" {
  description = "Maximum number of ECR images retained."
  type        = number
  default     = 50
}

variable "manage_registry_scanning" {
  description = "Manage ECR registry-level enhanced scanning. Disable if centrally managed elsewhere."
  type        = bool
  default     = true
}
