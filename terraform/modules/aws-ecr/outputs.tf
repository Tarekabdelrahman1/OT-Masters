output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "ECR repository URL used by Docker/Helm."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "jenkins_iam_user_name" {
  description = "Jenkins ECR IAM user."
  value       = aws_iam_user.jenkins.name
}

output "jenkins_iam_policy_arn" {
  description = "Least-privilege ECR IAM policy attached to Jenkins."
  value       = aws_iam_policy.jenkins_ecr.arn
}
