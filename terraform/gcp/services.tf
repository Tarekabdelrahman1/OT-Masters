locals {
  required_apis = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value

  # Avoid disabling APIs that might be used by other resources when this
  # Terraform stack is destroyed.
  disable_on_destroy = false
}
