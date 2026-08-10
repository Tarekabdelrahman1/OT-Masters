output "repository_url" {
  value = module.ecr.repository_url
}

output "repository_arn" {
  value = module.ecr.repository_arn
}

output "jenkins_iam_user_name" {
  value = module.ecr.jenkins_iam_user_name
}

output "jenkins_iam_policy_arn" {
  value = module.ecr.jenkins_iam_policy_arn
}
