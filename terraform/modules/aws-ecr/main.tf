resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Retain only the newest ${var.max_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IMPORTANT:
# ECR scanning configuration is registry-level, not repository-level.
# Enabling this resource modifies the scanning configuration for this AWS
# registry/region. Keep manage_registry_scanning=false if this AWS account
# already has centrally-managed ECR scanning.
resource "aws_ecr_registry_scanning_configuration" "this" {
  count = var.manage_registry_scanning ? 1 : 0

  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"

    repository_filter {
      filter      = var.repository_name
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_iam_user" "jenkins" {
  name = var.jenkins_iam_user_name

  tags = merge(var.tags, {
    Purpose = "Jenkins-ECR-CI"
  })
}

data "aws_iam_policy_document" "jenkins_ecr" {
  statement {
    sid    = "GetECRAuthorizationToken"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.jenkins_source_cidrs
    }
  }

  statement {
    sid    = "PushAndInspectOnlyThisRepository"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      aws_ecr_repository.this.arn
    ]

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.jenkins_source_cidrs
    }
  }
}

resource "aws_iam_policy" "jenkins_ecr" {
  name        = "${var.jenkins_iam_user_name}-policy"
  description = "Least-privilege Jenkins access to push only to ${var.repository_name}."
  policy      = data.aws_iam_policy_document.jenkins_ecr.json

  tags = var.tags
}

resource "aws_iam_user_policy_attachment" "jenkins_ecr" {
  user       = aws_iam_user.jenkins.name
  policy_arn = aws_iam_policy.jenkins_ecr.arn
}

# Deliberately no aws_iam_access_key resource here.
# We do not want a long-lived AWS secret written into Terraform state.
