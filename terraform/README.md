# DevSecOps Terraform Platform

This Terraform layout upgrades the earlier reusable modules into a security-first
GKE + AWS ECR platform.

## Layout

```text
terraform/
├── modules/
│   ├── network/
│   ├── gcp-iam/
│   ├── gke/
│   └── aws-ecr/
└── envs/
    ├── gcp-platform/
    └── aws-ecr/
```

## Important architecture choices

- GKE is regional.
- Worker nodes are private.
- During the lab, the public GKE control-plane endpoint is retained but restricted
  to your exact public IP using Master Authorized Networks.
- VPC-native GKE uses separate secondary subnet ranges for Pods and Services.
- GKE Dataplane V2 is enabled.
- Workload Identity Federation for GKE is enabled.
- Nodes use a dedicated service account with only
  `roles/container.defaultNodeServiceAccount`.
- Shielded GKE Nodes, Secure Boot, integrity monitoring, and the GKE metadata
  server are enabled.
- The insecure kubelet read-only port is disabled.
- VPC Flow Logs and Cloud NAT error logging are enabled.
- Cloud NAT uses one static public egress IP.
- ECR tags are immutable.
- Jenkins ECR permissions are scoped to one repository and the GCP NAT source IP.
- Terraform deliberately does NOT create an AWS IAM access key.

## Work step-by-step

Do NOT apply everything blindly.

Start with:

```bash
cd gcp
cp terraform.tfvars.example terraform.tfvars
# Edit project_id and admin_cidr.

terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Review the plan before `terraform apply`.

After GCP exists:

```bash
terraform output -raw nat_public_ip
```

Use that result in:

```text
aws/terraform.tfvars
```

as:

```hcl
jenkins_source_cidrs = [
  "X.X.X.X/32"
]
```
