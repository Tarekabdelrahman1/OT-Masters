module "ecr" {
  source = "../modules/aws-ecr"

  repository_name       = var.repository_name
  jenkins_iam_user_name = var.jenkins_iam_user_name
  jenkins_source_cidrs  = var.jenkins_source_cidrs

  untagged_image_expiry_days = var.untagged_image_expiry_days
  max_images                 = var.max_images
  manage_registry_scanning   = var.manage_registry_scanning

  tags = {
    Environment = "devsecops-lab"
    ManagedBy   = "terraform"
    Project     = "devsecops-master"
  }
}
