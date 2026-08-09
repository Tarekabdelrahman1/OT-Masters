# DevSecOps Project — Step 1: Infrastructure as Code

This bundle provisions:

- A custom GCP VPC and VPC-native GKE Standard regional cluster
- Private GKE nodes with controlled control-plane access
- Workload Identity Federation for GKE
- GKE Dataplane V2, Shielded Nodes, Secure Boot, private Google access
- Cloud Router + Cloud NAT with a fixed public egress IP (required for private nodes to reach AWS ECR)
- A least-privilege custom node service account
- An AWS ECR private repository with immutable tags, encryption, scan-on-push and lifecycle cleanup
- A Jenkins IAM user with a repository-scoped ECR push policy, optionally restricted to the GKE NAT public IP

No AWS access key is created by Terraform. We will create/store credentials safely in Vault in Step 2 so that secrets do not land in Terraform state.

## Directory layout

```text
infrastructure/
├── bootstrap/gcp-state/
├── gcp/
└── aws/
```

## Prerequisites

- Terraform >= 1.6
- gcloud CLI
- AWS CLI
- kubectl
- A GCP project with billing enabled
- An AWS account
- Administrative/bootstrap credentials for both clouds

Authenticate Terraform to GCP using Application Default Credentials:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <PROJECT_ID>
```

Authenticate Terraform to AWS using a local profile or another administrative bootstrap identity. Do not put AWS secrets in `.tfvars`:

```bash
export AWS_PROFILE=<ADMIN_PROFILE>
aws sts get-caller-identity
```

## 0. Bootstrap remote Terraform state

```bash
cd bootstrap/gcp-state
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw state_bucket_name
```

Copy the returned bucket name into `gcp/backend.hcl` and `aws/backend.hcl`.

## 1. Provision GCP/GKE first

```bash
cd ../../gcp
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
# edit both files
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Capture the stable GCP NAT address:

```bash
terraform output -raw nat_external_ip
```

That IP will become the allowed source CIDR for the Jenkins ECR IAM policy.

## 2. Provision AWS ECR and Jenkins IAM identity

```bash
cd ../aws
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
# set jenkins_source_cidrs to ["<GCP_NAT_IP>/32"]
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

## 3. Verify GKE

If the public GKE API endpoint is enabled, your current public IP must be present in `master_authorized_networks`.

```bash
gcloud container clusters get-credentials <CLUSTER_NAME> \
  --region <GCP_REGION> \
  --project <PROJECT_ID>

kubectl get nodes -o wide
```

If you set `enable_private_endpoint = true`, run kubectl from a network that can route to the private control-plane endpoint (for example VPN/bastion/connected VPC path).

## 4. Verify ECR

```bash
aws ecr describe-repositories \
  --region <AWS_REGION> \
  --repository-names <ECR_REPOSITORY_NAME>
```

Do not create the Jenkins AWS access key yet. Step 2 will deploy/configure Vault first, then we will create/store the credential without committing it to Git or Terraform state.
