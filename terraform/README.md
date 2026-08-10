# 1. Big Picture

Terraform is responsible only for the **cloud infrastructure layer**.

Terraform creates things such as:

- VPC network
- Subnet
- Pod and Service IP ranges
- Cloud Router
- Cloud NAT
- Static outbound IP
- GKE cluster
- GKE node pool
- GCP service accounts and IAM roles
- Amazon ECR repository
- AWS IAM permissions for Jenkins

Terraform is **not** responsible for the application deployment itself.

Later we will use:

- Helm for Kubernetes packages
- Argo CD for GitOps deployment
- Jenkins for CI
- Vault for secrets
- SonarQube for SAST
- Trivy for SCA/container scanning
- Gitleaks for secret scanning
- OPA Gatekeeper for admission policies
- Falco for runtime security
- DefectDojo for vulnerability management
- OWASP ZAP for DAST

The separation is intentional.

```text
Terraform
   |
   | creates infrastructure
   v
+---------------------------------------+
|              Cloud Platform           |
|                                       |
|  GCP                                  |
|  ├── VPC                              |
|  ├── Subnet                           |
|  ├── Cloud NAT                        |
|  ├── IAM                              |
|  └── GKE                              |
|                                       |
|  AWS                                  |
|  ├── ECR                              |
|  └── IAM                              |
+---------------------------------------+
                  |
                  | platform is ready
                  v
+---------------------------------------+
|             Kubernetes Layer          |
|                                       |
| Jenkins                               |
| Vault                                 |
| Argo CD                               |
| SonarQube                             |
| Gatekeeper                            |
| Falco                                 |
| DefectDojo                            |
| staging namespace                     |
| production namespace                  |
+---------------------------------------+
```

---

# 2. Terraform Repository Structure

The Terraform part of the repository is designed like this:

```text
terraform/
├── README.md
├── .gitignore
│
├── gcp/
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── versions.tf
│   ├── services.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── terraform.tfvars          # local only, DO NOT commit
│
├── aws/
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── versions.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── terraform.tfvars          # local only, DO NOT commit
│
└── modules/
    ├── network/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── gcp-iam/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── gke/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── aws-ecr/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

There are two important concepts here:

1. **Modules**
2. **Root environments**

---

# 3. What Is a Terraform Module?

A module is reusable Terraform code.

For example:

```text
modules/network
```

does not know whether it is being used for development, staging, production, or another project.

It only knows:

> "Give me a project ID, region, network name, subnet CIDRs, and I will create a secure network."

The root configuration:

```text
terraform/gcp
```

calls that module and gives it real values.

For example:

```hcl
module "network" {
  source = "../modules/network"

  project_id = var.project_id
  region     = var.region

  network_name = "${var.environment}-vpc"
}
```

Think about it like a programming function.

```text
Module = function
Variables = function arguments
Outputs = function return values
```

Example:

```text
network(
    project_id,
    region,
    CIDRs
)
        |
        v
returns:
    network_id
    subnet_id
    NAT_IP
```

This is why modules make Terraform much cleaner.

---

# 4. Why GCP and AWS Are Separate Root Configurations

We intentionally have:

```text
terraform/gcp/
terraform/aws/
```

instead of putting both providers into one huge Terraform state.

Why?

Because GCP and AWS have different responsibilities.

```text
GCP
├── Network
├── GKE
└── GCP IAM

AWS
├── ECR
└── AWS IAM
```

There is also a dependency between them.

The GCP stack creates a **static Cloud NAT public IP**.

That IP is then passed to the AWS stack.

```text
GKE / Jenkins
       |
       v
Cloud NAT
       |
       | fixed source IP
       v
    Internet
       |
       v
     AWS ECR
```

AWS IAM can therefore say:

> Jenkins may use this ECR permission only when the AWS API request comes from our GCP NAT IP.

So deployment order is:

```text
1. terraform/gcp
2. obtain Cloud NAT IP
3. terraform/aws
```

---

# 5. GCP Root Configuration

Directory:

```text
terraform/gcp/
```

This is the entry point for the GCP infrastructure.

When you run:

```bash
cd terraform/gcp
terraform init
terraform plan
terraform apply
```

Terraform reads every `.tf` file in this folder as one configuration.

Terraform does **not** execute `main.tf` before `variables.tf`.

All `.tf` files in the directory are loaded together.

The filenames are mainly for humans.

---

# 6. `gcp/versions.tf`

Example:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.42"
    }
  }
}
```

## Purpose

This defines:

- minimum Terraform version
- provider source
- allowed Google provider version

### `required_version`

```hcl
required_version = ">= 1.6.0"
```

means:

> Do not run this code using an old Terraform version below 1.6.

Why?

Because Terraform syntax and provider behavior evolve.

A minimum version makes the project reproducible.

### Provider source

```hcl
source = "hashicorp/google"
```

Terraform itself does not know how to create GCP resources.

The Google provider is a plugin that understands resources such as:

```text
google_compute_network
google_container_cluster
google_service_account
```

### Provider version

```hcl
version = "~> 7.42"
```

`~>` means we allow compatible versions within that release line instead of blindly taking any future major provider release.

The reason for pinning provider versions is reproducibility.

Without version control:

```text
Today       terraform init → provider A
6 months    terraform init → provider B
```

A provider behavior change could break the project.

---

# 7. `.terraform.lock.hcl`

After:

```bash
terraform init
```

Terraform creates:

```text
.terraform.lock.hcl
```

This file records the provider version Terraform actually selected.

Unlike `.terraform/`, the lock file should normally be committed to Git.

Example concept:

```text
versions.tf
    |
    | allowed range
    v
Google provider ~> 7.42
    |
terraform init
    |
    v
.terraform.lock.hcl
    |
    └── exact selected provider version
```

That helps different developers and CI systems use consistent providers.

---

# 8. `gcp/providers.tf`

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}
```

This tells Terraform:

> Use this GCP project and this default region.

Notice what is **not** here:

```hcl
credentials = "service-account.json"
```

We intentionally do not store service-account keys in Terraform code.

On the local Ubuntu VM we use:

```bash
gcloud auth application-default login
```

Terraform can then use Application Default Credentials.

Security principle:

```text
BAD

Git repository
└── service-account.json
        |
        └── long-lived credential


BETTER FOR LOCAL ADMINISTRATION

Your Ubuntu VM
└── gcloud ADC authentication
        |
        v
Terraform
        |
        v
GCP API
```

Later CI infrastructure can use workload identity/federation rather than static JSON keys.

---

# 9. `gcp/services.tf`

GCP APIs must be enabled before Terraform can create many resources.

The code defines:

```hcl
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
```

Then:

```hcl
resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}
```

## What `for_each` means

Instead of writing six almost identical resources:

```hcl
resource ...
resource ...
resource ...
```

Terraform loops over the set.

Conceptually:

```text
for each API:
    enable API
```

This creates resources similar to:

```text
google_project_service.required["compute.googleapis.com"]
google_project_service.required["container.googleapis.com"]
...
```

## Why each API exists

### Compute Engine API

```text
compute.googleapis.com
```

Needed for:

- VPC
- subnet
- routers
- NAT
- IP addresses
- GKE worker VM infrastructure

### Kubernetes Engine API

```text
container.googleapis.com
```

Needed for:

- GKE cluster
- GKE node pools

### IAM API

```text
iam.googleapis.com
```

Needed for identity and permission management.

### IAM Credentials API

```text
iamcredentials.googleapis.com
```

Useful for modern service-account and workload-identity flows.

### Logging API

```text
logging.googleapis.com
```

Used by Cloud Logging.

### Monitoring API

```text
monitoring.googleapis.com
```

Used by Cloud Monitoring.

---

# 10. Why `disable_on_destroy = false`

The code says:

```hcl
disable_on_destroy = false
```

This is an important safety decision.

Imagine another resource in the same project also uses:

```text
compute.googleapis.com
```

If destroying this Terraform stack disabled the Compute API, unrelated infrastructure might stop working.

So:

```text
terraform destroy
```

may destroy infrastructure managed by this stack, but it will not disable those shared project APIs.

---

# 11. `gcp/main.tf`

This file connects our modules.

The dependency flow is:

```text
required GCP APIs
       |
       +--------------------+
       |                    |
       v                    v
   Network               GCP IAM
       |                    |
       +---------+----------+
                 |
                 v
                GKE
```

This is important.

GKE needs:

- a network
- a subnet
- Pod IP range
- Service IP range
- node service account

Those objects must exist before the GKE cluster is created.

Terraform understands many dependencies automatically because outputs from one resource/module are passed into another.

---

# 12. Network Module Call

The GCP root calls:

```hcl
module "network" {
  source = "../modules/network"
  ...
}
```

`source` means:

```text
terraform/gcp/main.tf
        |
        └── use code from
             ../modules/network
```

The root passes:

```hcl
project_id = var.project_id
region     = var.region
```

Then names:

```hcl
network_name = "${var.environment}-vpc"
subnet_name  = "${var.environment}-gke-subnet"
```

If:

```hcl
environment = "devsecops"
```

Terraform creates names like:

```text
devsecops-vpc
devsecops-gke-subnet
```

This naming pattern gives resources a consistent project prefix.

---

# 13. Network Architecture

Our network looks like this:

```text
GCP Project
|
└── devsecops-vpc
    |
    └── devsecops-gke-subnet
        |
        ├── Primary range
        |      10.10.0.0/20
        |      GKE Nodes
        |
        ├── Secondary range
        |      10.20.0.0/16
        |      Kubernetes Pods
        |
        └── Secondary range
               10.30.0.0/20
               Kubernetes Services

Cloud Router
     |
Cloud NAT
     |
Static Public IP
     |
Internet / AWS ECR
```

---

# 14. `modules/network/main.tf`

## 14.1 Custom VPC

```hcl
resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}
```

### Why `auto_create_subnetworks = false`

If automatic subnet creation is enabled, GCP creates predefined subnets for you.

For a serious infrastructure project, we want explicit control.

So we use **custom mode VPC**.

```text
Auto mode
GCP chooses many defaults

Custom mode
We define exactly:
├── subnet
├── CIDR
├── secondary ranges
├── region
└── routing
```

This is better for:

- predictable networking
- security
- avoiding unexpected ranges
- multi-environment architecture

---

# 15. Primary Node CIDR

The subnet primary range is:

```hcl
node_ipv4_cidr = "10.10.0.0/20"
```

This is primarily for GKE node VM addresses.

Concept:

```text
GKE Node 1 → 10.10.x.x
GKE Node 2 → 10.10.x.x
GKE Node 3 → 10.10.x.x
```

The exact addresses are allocated by GCP.

---

# 16. Pod Secondary CIDR

```hcl
pod_ipv4_cidr = "10.20.0.0/16"
```

This range is used by Kubernetes Pods.

Example:

```text
Jenkins controller Pod
        10.20.x.x

Argo CD Pod
        10.20.x.x

Vault Pod
        10.20.x.x

Application Pod
        10.20.x.x
```

This is important because our GKE cluster is **VPC-native**.

Pods get addresses from VPC secondary IP ranges rather than an unrelated overlay network.

---

# 17. Service Secondary CIDR

```hcl
service_ipv4_cidr = "10.30.0.0/20"
```

This is used for Kubernetes Service virtual IPs.

Example:

```text
jenkins Service
argocd-server Service
vault Service
webapp Service
```

A Kubernetes Service is different from a Pod.

```text
Service
   |
   +----> Pod 1
   +----> Pod 2
   +----> Pod 3
```

The Service provides a stable virtual IP/name while Pods can be created and destroyed.

---

# 18. Why Separate Nodes, Pods, and Services

We intentionally use:

```text
10.10.0.0/20 → nodes
10.20.0.0/16 → pods
10.30.0.0/20 → services
```

instead of trying to put everything in one small subnet.

Benefits:

- easier capacity planning
- easier troubleshooting
- better visibility
- proper VPC-native GKE design
- easier future firewall/policy design
- avoids address exhaustion

---

# 19. Private Google Access

Inside the subnet:

```hcl
private_ip_google_access = true
```

Our GKE nodes will not have normal public external IP addresses.

Private Google Access allows private instances to access supported Google APIs/services without requiring public VM IPs.

Mental model:

```text
Private GKE Node
      |
      | no public VM IP
      |
      +---- Google APIs
      |
      +---- Cloud NAT ---- Internet
```

---

# 20. VPC Flow Logs

The subnet enables:

```hcl
log_config {
  aggregation_interval = var.flow_log_aggregation_interval
  flow_sampling        = var.flow_log_sampling
  metadata             = "INCLUDE_ALL_METADATA"
}
```

VPC Flow Logs give visibility into network flows.

Later this becomes useful for:

- incident investigation
- network troubleshooting
- detecting unexpected communication
- security analytics
- Google SecOps/SIEM ingestion

Example question during an incident:

> Why did this workload communicate with an external IP?

Flow logs can provide useful network evidence.

---

# 21. `flow_sampling = 0.5`

Default:

```hcl
flow_log_sampling = 0.5
```

That means we sample a portion of flows rather than capturing everything at maximum volume.

Why not always 1.0?

Logging has:

- storage cost
- ingestion cost
- analysis cost
- performance/volume considerations

For a lab, `0.5` is a useful balance.

Later we can tune it based on security requirements and budget.

---

# 22. Static NAT Public IP

We create:

```hcl
resource "google_compute_address" "nat" {
  ...
  address_type = "EXTERNAL"
}
```

This reserves a public IP for Cloud NAT.

Why static?

Because our architecture is cross-cloud.

```text
Jenkins in GKE
      |
      v
Cloud NAT
      |
      | always same public IP
      v
AWS
```

AWS can restrict Jenkins permissions to that source IP.

If Cloud NAT used a changing address, the AWS-side allow condition could break or become harder to secure.

---

# 23. `create_before_destroy`

The NAT IP resource has:

```hcl
lifecycle {
  create_before_destroy = true
}
```

Terraform lifecycle settings influence replacement behavior.

The goal is to reduce the chance of deleting the old object before Terraform has a replacement.

It is a safety/availability-oriented setting.

---

# 24. Cloud Router

```hcl
resource "google_compute_router" "this" {
  ...
}
```

Cloud NAT is associated with Cloud Router.

A simplified relationship:

```text
VPC
 |
Cloud Router
 |
Cloud NAT
 |
Static External IP
```

The router is not a Linux VM that we SSH into.

It is a managed GCP networking resource.

---

# 25. Cloud NAT

Private GKE nodes have no public IP.

But Jenkins may need to reach:

- GitHub
- AWS ECR
- package repositories
- security databases
- external APIs

So they still need controlled outbound internet connectivity.

Cloud NAT provides that.

```text
Private node
10.10.x.x
   |
   v
Cloud NAT
   |
   | source translated to fixed public IP
   v
Internet
```

Important:

Cloud NAT provides **outbound translation**.

It does not mean the node becomes directly reachable from the public internet.

---

# 26. `MANUAL_ONLY`

```hcl
nat_ip_allocate_option = "MANUAL_ONLY"
nat_ips = [google_compute_address.nat.self_link]
```

This tells Cloud NAT:

> Use our explicitly reserved static external IP.

This is required for our predictable cross-cloud egress design.

---

# 27. NAT Only the GKE Subnet

```hcl
source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
```

Then:

```hcl
subnetwork {
  name = google_compute_subnetwork.gke.id
}
```

We intentionally do not say:

> NAT every subnet in the region.

Instead:

> NAT this explicitly selected GKE subnet.

This follows a security principle:

**scope resources narrowly rather than granting broad default behavior.**

---

# 28. Cloud NAT Logging

```hcl
log_config {
  enable = true
  filter = "ERRORS_ONLY"
}
```

We initially log NAT errors.

This helps troubleshoot:

- exhausted NAT ports
- failed translations
- connectivity problems

We can increase logging later if security monitoring requires it.

---

# 29. Network Module Outputs

The network module returns values such as:

```hcl
output "network_id"
output "subnet_id"
output "pods_range_name"
output "services_range_name"
output "nat_ip_address"
```

Why outputs?

Because other modules need those values.

Example dependency:

```text
network module
   |
   | output network_id
   | output subnet_id
   | output pod range
   | output service range
   v
GKE module
```

Without outputs, the root configuration would have a harder time connecting reusable modules cleanly.

---

# 30. GCP IAM Module

Directory:

```text
modules/gcp-iam
```

This module creates the identity used by **GKE worker nodes**.

Important distinction:

```text
GKE Node Service Account
!=
Application Service Account
!=
Jenkins Service Account
!=
Vault Service Account
```

We do not want one giant identity with every permission.

That would violate least privilege.

---

# 31. Dedicated GKE Node Service Account

```hcl
resource "google_service_account" "gke_node" {
  account_id = var.node_service_account_id
}
```

This creates a dedicated service account such as:

```text
devsecops-gke-node@PROJECT_ID.iam.gserviceaccount.com
```

Why not use the default Compute Engine service account?

Because security-focused infrastructure should use explicit identities with explicit permissions.

---

# 32. GKE Node IAM Role

The module grants:

```hcl
role = "roles/container.defaultNodeServiceAccount"
```

This role is for the GKE node identity.

The design principle is:

```text
Node identity
    |
    └── permissions needed for node operations

Application identity
    |
    └── permissions needed by the application
```

We will later use Kubernetes service accounts and Workload Identity Federation for workload-specific permissions.

---

# 33. Why There Is No Artifact Registry Reader Role

The previous project used Google Artifact Registry.

This project intentionally stores application images in:

```text
Amazon ECR
```

Therefore giving the GKE node identity:

```text
roles/artifactregistry.reader
```

would be unrelated permission.

We removed it.

Least privilege means not granting permissions "just in case."

---

# 34. GKE Module Overview

Directory:

```text
modules/gke
```

This is the biggest module.

It creates:

```text
Regional GKE Standard cluster
        |
        ├── private nodes
        ├── restricted API access
        ├── VPC-native networking
        ├── Workload Identity Federation
        ├── Dataplane V2
        ├── Shielded Nodes
        ├── logging
        └── monitoring
                |
                v
        Managed node pool
                |
                ├── autoscaling
                ├── auto repair
                ├── auto upgrade
                ├── Secure Boot
                ├── COS_CONTAINERD
                ├── GKE Metadata Server
                └── kubelet hardening
```

---

# 35. Regional GKE Cluster

```hcl
location = var.region
```

Instead of:

```hcl
location = var.zone
```

This makes the cluster control plane regional.

Node locations are configured separately:

```hcl
node_locations = [
  "europe-west1-b",
  "europe-west1-c"
]
```

Mental model:

```text
Region: europe-west1

Control plane
    regional

Workers
├── europe-west1-b
└── europe-west1-c
```

This gives us better resilience than putting everything into one zone.

---

# 36. Why GKE Standard

This project focuses heavily on:

- Falco
- security policies
- runtime controls
- node behavior
- advanced Kubernetes administration

GKE Standard gives us more control than a highly abstracted cluster mode.

That makes it better for a master-level DevSecOps lab.

---

# 37. Remove the Default Node Pool

```hcl
remove_default_node_pool = true
initial_node_count       = 1
```

GKE needs an initial node count during cluster creation, but we immediately remove the default pool and manage our own node pool separately.

Why?

Because the custom node pool lets us explicitly configure:

- node service account
- disk
- machine type
- Secure Boot
- metadata settings
- autoscaling
- upgrade behavior
- kubelet hardening

This is cleaner than accepting default node-pool settings.

---

# 38. VPC-Native GKE

```hcl
networking_mode = "VPC_NATIVE"
```

Then:

```hcl
ip_allocation_policy {
  cluster_secondary_range_name  = var.pods_range_name
  services_secondary_range_name = var.services_range_name
}
```

This links GKE directly to the secondary subnet ranges created by the network module.

```text
Network module
 |
 ├── devsecops-pods
 └── devsecops-services
          |
          v
      GKE cluster
```

This is one good example of why Terraform outputs/modules matter.

---

# 39. Private Nodes

```hcl
private_cluster_config {
  enable_private_nodes = true
}
```

GKE worker nodes do not get external/public IP addresses.

Security benefit:

```text
Internet
   X
   |
GKE Node
```

The internet cannot directly address the worker VM through a normal public node IP.

Outbound connectivity still works through Cloud NAT.

---

# 40. Public vs Private GKE Control Plane Endpoint

Current lab configuration:

```hcl
enable_private_endpoint = false
```

This does **not** mean the worker nodes are public.

Workers remain private.

It means we temporarily keep a controlled public API endpoint for Kubernetes administration.

Why?

Your admin machine is a **local Ubuntu VM** outside GCP.

Without a VPN, bastion, or private connectivity path, a private-only Kubernetes API would be harder to reach.

So phase one is:

```text
Local Ubuntu VM
       |
       | public IP explicitly authorized
       v
GKE API endpoint

GKE Nodes
       |
       └── private only
```

Later hardening:

```hcl
enable_private_endpoint = true
```

after we create a secure private administrative path.

---

# 41. Master Authorized Networks

The root configuration passes:

```hcl
master_authorized_networks = {
  admin-workstation = var.admin_cidr
}
```

Example:

```hcl
admin_cidr = "203.0.113.10/32"
```

The `/32` means one exact IPv4 address.

So instead of:

```text
0.0.0.0/0
= everybody on the internet
```

we use:

```text
YOUR_PUBLIC_IP/32
= only your current public IP
```

This significantly reduces Kubernetes API exposure during the lab.

---

# 42. Which IP Goes in `admin_cidr`?

Do **not** use:

```text
192.168.1.20
10.0.2.15
172.16.x.x
```

Those are usually local/private addresses.

Use your public internet address:

```bash
curl -4 -fsSL https://ifconfig.me
echo
```

Then:

```hcl
admin_cidr = "X.X.X.X/32"
```

If your ISP changes your public IP, you may need to update this variable.

---

# 43. Disable GCP Public CIDR Bypass

The configuration includes:

```hcl
gcp_public_cidrs_access_enabled = false
```

The security idea is simple:

> Access should be based on explicitly configured authorized networks rather than broad implicit public source ranges.

---

# 44. Client Certificates Disabled

```hcl
master_auth {
  client_certificate_config {
    issue_client_certificate = false
  }
}
```

We do not want GKE issuing legacy client certificates as our normal authentication mechanism.

Modern identity-based authentication is preferred.

---

# 45. Workload Identity Federation for GKE

```hcl
workload_identity_config {
  workload_pool = "${var.project_id}.svc.id.goog"
}
```

This is one of the most important security settings in the project.

Without workload identity, a common bad pattern is:

```text
Kubernetes Pod
 |
 └── mounted service-account-key.json
```

That creates a long-lived cloud credential inside the workload.

Instead:

```text
Kubernetes Pod
       |
Kubernetes Service Account
       |
Workload Identity Federation
       |
Google IAM
       |
Google API
```

Later we can create separate identities for:

- Jenkins
- Vault
- application workloads
- security components

No need to put reusable GCP JSON private keys into Git or container images.

---

# 46. Dataplane V2

```hcl
datapath_provider = "ADVANCED_DATAPATH"
```

This enables the GKE advanced dataplane.

For our project this matters because we want strong Kubernetes networking/security controls, especially NetworkPolicy.

Later we can create rules such as:

```text
webapp
  |
  +--> may communicate with database
  |
  X--> may not communicate with Jenkins
  |
  X--> may not communicate with Vault unless explicitly required
```

This is part of defense in depth.

---

# 47. Shielded GKE Nodes

```hcl
enable_shielded_nodes = true
```

and in node configuration:

```hcl
shielded_instance_config {
  enable_secure_boot          = true
  enable_integrity_monitoring = true
}
```

These settings help protect the node boot process.

### Secure Boot

Only trusted boot components should load.

### Integrity Monitoring

Provides integrity-related signals for Shielded VM nodes.

This is a node-level hardening layer.

---

# 48. GKE Release Channel

```hcl
release_channel = "REGULAR"
```

A release channel controls how GKE versions/updates are delivered.

For this project:

```text
RAPID    → fastest/newest
REGULAR  → balanced
STABLE   → slower/more conservative
```

`REGULAR` is a reasonable learning/platform balance.

---

# 49. GKE Logging

We enable:

```hcl
logging_config {
  enable_components = [
    "SYSTEM_COMPONENTS",
    "APISERVER",
    "CONTROLLER_MANAGER",
    "SCHEDULER",
    "WORKLOADS"
  ]
}
```

This is extremely relevant because later we want security monitoring and SIEM integration.

### SYSTEM_COMPONENTS

System-level GKE logs.

### APISERVER

Kubernetes API server activity.

Important for security because Kubernetes API activity can show:

- resource changes
- access attempts
- operational events

### CONTROLLER_MANAGER

Kubernetes controller behavior.

### SCHEDULER

Scheduling behavior.

### WORKLOADS

Application/workload logs.

Later the logging architecture can feed:

```text
GKE
 |
Cloud Logging
 |
Google SecOps
```

---

# 50. Monitoring

Current configuration enables:

```hcl
monitoring_config {
  enable_components = [
    "SYSTEM_COMPONENTS"
  ]
}
```

This gives baseline GKE monitoring.

Managed Prometheus is currently:

```hcl
enabled = false
```

Why?

We are keeping the first infrastructure stage simpler.

We can enable more advanced observability later once the base cluster is stable.

---

# 51. Security Posture Configuration

The current cluster includes:

```hcl
security_posture_config {
  mode               = "BASIC"
  vulnerability_mode = "VULNERABILITY_DISABLED"
}
```

This is intentionally not the final security architecture.

Our primary security pipeline will include:

```text
Trivy
SonarQube
Gitleaks
Gatekeeper
Falco
DefectDojo
```

We can later evaluate additional GKE-native posture/vulnerability capabilities as another security layer.

The project should avoid enabling every paid or overlapping feature before understanding its purpose and cost.

---

# 52. Maintenance Window

```hcl
maintenance_policy {
  daily_maintenance_window {
    start_time = "03:00"
  }
}
```

This tells GKE when maintenance activity is preferred.

Why care?

Platform maintenance can affect workloads.

In production you should choose windows based on:

- traffic
- business hours
- support availability
- maintenance policy

For the lab, `03:00` is simply a predictable maintenance window.

---

# 53. GKE Node Pool Autoscaling

```hcl
autoscaling {
  total_min_node_count = 2
  total_max_node_count = 6
}
```

This is particularly useful because Jenkins will later use dynamic Kubernetes build agents.

Example:

```text
normal workload
2 nodes

many Jenkins builds
     |
     v
cluster needs more compute
     |
     v
3, 4, 5 ... nodes

load decreases
     |
     v
scale down
```

This is better than permanently paying for the maximum node count.

---

# 54. Auto Repair

```hcl
management {
  auto_repair = true
}
```

If a node becomes unhealthy, GKE can repair/replace it.

This improves platform resilience.

---

# 55. Auto Upgrade

```hcl
auto_upgrade = true
```

GKE can upgrade worker nodes according to cluster/version management policies.

Keeping Kubernetes infrastructure patched is also a security concern.

Old Kubernetes/node versions can contain known vulnerabilities.

---

# 56. Surge Upgrade Settings

```hcl
upgrade_settings {
  strategy        = "SURGE"
  max_surge       = 1
  max_unavailable = 0
}
```

This tries to perform upgrades while reducing workload disruption.

Concept:

```text
Old node(s)
     +
Temporary new node
     |
move workloads
     |
remove old node
```

`max_unavailable = 0` aims to avoid intentionally taking a node unavailable before replacement capacity is available.

---

# 57. Node Machine Type

Default:

```hcl
machine_type = "e2-standard-4"
```

This platform is not running only one tiny web application.

Eventually it may run:

```text
Jenkins
SonarQube
Vault
Argo CD
DefectDojo
Falco
Gatekeeper
staging app
production app
dynamic Jenkins agents
```

So extremely small nodes would quickly become a problem.

We can tune node pools later.

A future production design could use separate pools, for example:

```text
system node pool
CI node pool
security-tool node pool
application node pool
```

with taints/tolerations and different machine sizes.

---

# 58. COS_CONTAINERD

```hcl
image_type = "COS_CONTAINERD"
```

COS means Container-Optimized OS.

It is designed specifically for running containers and has a smaller purpose-built surface than a general-purpose server OS.

Container runtime:

```text
containerd
```

This is suitable for modern Kubernetes nodes.

---

# 59. Node Disk

```hcl
disk_type    = "pd-balanced"
disk_size_gb = 80
```

Jenkins/security tools can create significant temporary data.

Examples:

- container layers
- scanner databases
- workspace files
- build artifacts

80 GB gives the initial lab more room than a very small default disk.

But long-term build storage should not depend only on node boot disks.

---

# 60. Node Service Account

```hcl
service_account = var.node_service_account_email
```

This connects:

```text
gcp-iam module
      |
      | output service-account email
      v
gke module
      |
      v
GKE node pool
```

The node pool therefore does not use an accidental/default identity.

---

# 61. OAuth Scope vs IAM

The node config uses:

```hcl
oauth_scopes = [
  "https://www.googleapis.com/auth/cloud-platform"
]
```

This looks broad, but the important authorization boundary is the IAM permissions attached to the service account.

Think:

```text
OAuth scope
= API access capability envelope

IAM role
= what the identity is actually authorized to do
```

So we keep the service account itself least-privileged.

---

# 62. Disable Legacy Metadata Endpoints

```hcl
metadata = {
  "disable-legacy-endpoints" = "true"
}
```

This is node metadata hardening.

Legacy metadata access patterns are undesirable because metadata services can expose sensitive identity information if workloads can abuse them.

---

# 63. GKE Metadata Server

```hcl
workload_metadata_config {
  mode = "GKE_METADATA"
}
```

This supports the Workload Identity Federation design.

Instead of Pods freely inheriting node identity behavior, GKE can provide workload-aware identity handling.

This is important for separating:

```text
Node identity
```

from:

```text
Pod/workload identity
```

---

# 64. Disable Insecure Kubelet Read-Only Port

```hcl
kubelet_config {
  insecure_kubelet_readonly_port_enabled = "FALSE"
}
```

The kubelet runs on Kubernetes nodes.

We do not want an insecure legacy read-only endpoint exposed.

This is another node-level hardening measure.

---

# 65. Node Labels

Example:

```hcl
node_labels = {
  environment = var.environment
  node-role   = "platform"
}
```

Kubernetes labels provide metadata we can later use for:

- scheduling
- organization
- policies
- observability

Example:

```bash
kubectl get nodes --show-labels
```

Future:

```text
node-role=ci
node-role=security
node-role=application
```

---

# 66. Node Network Tags

```hcl
node_network_tags = [
  "gke-devsecops"
]
```

These are Compute Engine network tags.

They can later be referenced in VPC firewall rules.

Do not confuse them with Kubernetes labels.

```text
Kubernetes label
→ Kubernetes scheduling/policies

GCP network tag
→ VPC firewall/network targeting
```

---

# 67. Deletion Protection

Variable:

```hcl
deletion_protection = false
```

For the lab we keep it false because we will probably recreate the cluster multiple times.

Later, once the platform stabilizes:

```hcl
deletion_protection = true
```

This helps prevent accidental deletion.

Do not forget that a learning environment and a production environment have different priorities.

---

# 68. Why `depends_on` Exists in `gcp/main.tf`

Example:

```hcl
depends_on = [
  google_project_service.required
]
```

Terraform normally calculates dependencies from references.

But APIs need to be enabled before some resources are created.

The explicit `depends_on` makes our intention clear:

```text
enable GCP API
      |
      v
create infrastructure that requires API
```

For GKE we also depend on:

```text
GCP APIs
network module
GCP IAM module
```

---

# 69. GCP Root Variables

The root `variables.tf` contains the values that describe one deployed platform.

Important defaults:

```hcl
region = "europe-west1"

cluster_name = "devsecops-gke"

node_ipv4_cidr    = "10.10.0.0/20"
pod_ipv4_cidr     = "10.20.0.0/16"
service_ipv4_cidr = "10.30.0.0/20"

master_ipv4_cidr = "172.16.0.0/28"

machine_type = "e2-standard-4"

node_pool_total_min = 2
node_pool_total_max = 6
```

The purpose of variables is to avoid hardcoding environment-specific values throughout modules.

---

# 70. `terraform.tfvars.example`

This file is safe to commit because it contains examples/placeholders.

Create your real file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit:

```hcl
project_id = "YOUR_REAL_PROJECT_ID"
admin_cidr = "YOUR.PUBLIC.IP/32"
```

The real:

```text
terraform.tfvars
```

is ignored by Git.

Why?

Because variable files may eventually contain:

- project IDs
- account IDs
- IP addresses
- environment-specific information
- occasionally secrets if someone makes a mistake

Even though `project_id` itself is not a secret, keeping real environment variable files out of Git reduces the chance of later committing something sensitive.

---

# 71. GCP Outputs

After apply:

```bash
terraform output
```

we expose useful values such as:

```text
network_name
subnet_name
nat_public_ip
gke_cluster_name
gke_region
workload_identity_pool
gke_node_service_account
get_credentials_command
```

The most important cross-cloud output is:

```bash
terraform output -raw nat_public_ip
```

That value is required by the AWS configuration.

---

# 72. `get_credentials_command`

The GCP stack generates a helper command such as:

```bash
gcloud container clusters get-credentials devsecops-gke \
  --region europe-west1 \
  --project PROJECT_ID
```

This updates your local:

```text
~/.kube/config
```

so `kubectl` knows how to connect to the cluster.

Then:

```bash
kubectl get nodes
```

should communicate with GKE.

---

# 73. AWS Root Configuration

Directory:

```text
terraform/aws
```

This is intentionally separate from GCP.

It creates:

```text
Amazon ECR
AWS IAM user
IAM ECR policy
IAM policy attachment
optional ECR enhanced scanning config
```

The AWS stack should be applied **after GCP**, because we need the GCP NAT IP first.

---

# 74. `aws/providers.tf`

```hcl
provider "aws" {
  region = var.aws_region
}
```

Authentication is deliberately not hardcoded.

Bad:

```hcl
provider "aws" {
  access_key = "AKIA..."
  secret_key = "..."
}
```

Never do that.

Use the AWS CLI credential mechanism, SSO, or later federation.

Terraform can use the authenticated AWS environment/profile.

---

# 75. Amazon ECR Repository

The ECR module creates:

```hcl
resource "aws_ecr_repository" "this"
```

This repository stores application container images.

Pipeline flow later:

```text
Jenkins
 |
docker build
 |
Trivy scan
 |
Syft SBOM
 |
Cosign
 |
docker push
 |
Amazon ECR
```

Then GKE pulls the approved application image from ECR.

---

# 76. Immutable Image Tags

```hcl
image_tag_mutability = "IMMUTABLE"
```

This is important for software supply-chain security.

Bad behavior:

```text
webapp:v1
    |
later overwritten
    |
webapp:v1 now points to different content
```

Then nobody can trust what `v1` means.

Immutable tags prevent overwriting an existing image tag.

Even better, GitOps will eventually deploy by digest:

```text
image@sha256:abcdef...
```

A digest identifies exact image content.

---

# 77. Why We Avoid `latest`

Do not build the production process around:

```text
webapp:latest
```

`latest` is mutable and ambiguous.

Prefer:

```text
webapp:<git-commit-sha>
```

and eventually Helm values using:

```text
sha256 digest
```

Example:

```yaml
image:
  repository: 123456789012.dkr.ecr.eu-central-1.amazonaws.com/devsecops-webapp
  digest: sha256:...
```

This supports reproducibility and auditability.

---

# 78. ECR Encryption

```hcl
encryption_configuration {
  encryption_type = "AES256"
}
```

This enables ECR repository encryption at rest using the selected encryption mode.

Later, if required, we could evaluate customer-managed KMS keys.

For the lab, this gives us encryption without additional KMS complexity.

---

# 79. `force_delete = false`

```hcl
force_delete = false
```

Terraform should not silently remove a repository that still contains images.

This protects against accidental artifact destruction.

You should consciously handle stored images before destroying the repository.

---

# 80. ECR Lifecycle Policy

Container registries grow quickly.

Every Jenkins build can create an image.

Without cleanup:

```text
build 1
build 2
build 3
...
build 5000
```

Storage and clutter increase forever.

The lifecycle policy does two things.

### Rule 1 — remove old untagged images

```text
untagged > 7 days
→ expire
```

### Rule 2 — cap retained images

```text
keep newest ~50 images
```

This makes the lab manageable.

Production retention policy should be based on:

- rollback requirements
- audit requirements
- release frequency
- compliance
- storage cost

---

# 81. ECR Enhanced Scanning

The module optionally creates:

```hcl
aws_ecr_registry_scanning_configuration
```

with:

```hcl
scan_type = "ENHANCED"
```

and continuous scanning for the selected repository pattern.

Important architectural note:

**ECR scanning configuration is registry-level.**

So if your AWS account already has a central security team managing ECR registry scanning, Terraform should not fight that configuration.

That's why we have:

```hcl
manage_registry_scanning = true
```

and can change it to:

```hcl
manage_registry_scanning = false
```

when appropriate.

---

# 82. Why We Still Use Trivy if ECR Scans Images

Defense in depth.

Jenkins Trivy scan:

```text
before push/deployment
```

ECR scanning:

```text
registry-side / ongoing visibility
```

Later DefectDojo:

```text
central vulnerability management
```

So:

```text
Trivy
   |
ECR scanning
   |
DefectDojo
```

are complementary rather than necessarily duplicates.

---

# 83. Jenkins AWS IAM User

The current first version creates:

```hcl
resource "aws_iam_user" "jenkins"
```

This is a transitional design.

The final mature design should favor short-lived federated credentials.

However, for the learning project we can first understand:

- IAM users
- IAM policy
- least privilege
- Vault secret storage
- ECR authentication

Then harden the project by replacing static credentials with federation.

---

# 84. Critical Security Decision: No IAM Access Key in Terraform

The module deliberately does **not** create:

```hcl
resource "aws_iam_access_key" "jenkins"
```

Why?

Terraform stores resource information in state.

If Terraform creates a secret credential, sensitive material can end up in Terraform state.

Bad architecture:

```text
Terraform
 |
creates AWS secret key
 |
terraform.tfstate
 |
contains sensitive credential
```

We avoid that.

The IAM identity/policy can be infrastructure-as-code, while secret bootstrap is handled separately.

Later Vault/federation will improve this further.

---

# 85. Minimal ECR IAM Permissions

The Jenkins policy is not:

```text
AdministratorAccess
```

and not:

```text
AmazonEC2ContainerRegistryFullAccess
```

across the whole account.

Instead the policy grants only specific ECR actions needed for the CI image workflow.

Examples:

```text
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
ecr:PutImage
ecr:BatchGetImage
ecr:DescribeImages
ecr:GetDownloadUrlForLayer
```

Repository-specific operations are scoped to:

```text
only our devsecops-webapp repository ARN
```

This is least privilege.

---

# 86. Why `ecr:GetAuthorizationToken` Uses `*`

Some AWS actions cannot be meaningfully scoped to one repository ARN.

The authorization-token action therefore uses:

```hcl
resources = ["*"]
```

while actual repository operations are restricted to:

```hcl
aws_ecr_repository.this.arn
```

This is an important IAM lesson:

Least privilege does not always mean every statement can use a single resource ARN.

It means using the narrowest scope supported by that API/action.

---

# 87. Restrict Jenkins by GCP NAT Source IP

Both IAM statements include an IP condition.

Concept:

```text
IAM user credential
        +
request comes from GCP NAT IP
        |
        v
allowed
```

If the same credential is stolen and used from another random network:

```text
stolen credential
        +
attacker IP
        |
        X
      denied
```

This is not a replacement for secure credentials.

It is an additional security layer.

Defense in depth:

```text
Secret protection
+
least-privilege IAM
+
source-IP restriction
+
short-lived credentials later
```

---

# 88. How to Obtain the NAT IP

After GCP apply:

```bash
cd terraform/gcp

terraform output -raw nat_public_ip
echo
```

Suppose it returns:

```text
34.140.10.25
```

Then:

```bash
cd ../aws
cp terraform.tfvars.example terraform.tfvars
```

Configure:

```hcl
jenkins_source_cidrs = [
  "34.140.10.25/32"
]
```

Now AWS IAM knows our expected GCP egress address.

---

# 89. Important Cross-Cloud Authentication Problem

Our architecture intentionally uses:

```text
GKE on GCP
+
ECR on AWS
```

That means image pull authentication is more complex than using GCP Artifact Registry.

ECR credentials/tokens are temporary.

We should **not** create one permanent Kubernetes Docker secret and forget about it.

Later we will design this properly with:

- Vault and/or
- short-lived credentials and/or
- workload federation/credential rotation

This is actually a valuable multi-cloud DevSecOps challenge.

---

# 90. Terraform State

Terraform maintains state representing managed infrastructure.

Default local file:

```text
terraform.tfstate
```

State answers questions such as:

```text
Which GCP VPC did Terraform create?
What is its resource ID?
What is the current NAT IP?
Which ECR repository is managed?
```

Terraform compares:

```text
Configuration
     |
     v
Terraform State
     |
     v
Real Cloud APIs
```

and calculates changes.

---

# 91. Why State Is Sensitive

Terraform state may contain:

- resource IDs
- network details
- infrastructure metadata
- sometimes secrets depending on resources

Therefore:

```text
terraform.tfstate
```

must not be committed to a public Git repository.

Our `.gitignore` blocks it.

---

# 92. Current State vs Future Remote State

At the beginning of the project, we may use local state while learning.

Before we treat the platform as mature, we should migrate state to a secure remote backend.

For GCP, an example is:

```text
GCS bucket
├── versioning
├── restricted IAM
├── public access prevention
└── Terraform state
```

Why remote state?

- backup
- versioning
- shared administration
- less risk of losing your local VM
- CI/CD compatibility

We will add this deliberately in a separate step instead of hiding it inside the module code.

---

# 93. `.gitignore`

The Terraform `.gitignore` protects files such as:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
backend.hcl
```

But allows:

```text
*.tfvars.example
```

Why?

Example files document configuration.

Real tfvars represent actual environments.

---

# 94. What Should Be Committed to Git

Commit:

```text
main.tf
variables.tf
outputs.tf
providers.tf
versions.tf
services.tf
modules/
terraform.tfvars.example
.terraform.lock.hcl
README.md
.gitignore
```

Do not commit:

```text
terraform.tfstate
terraform.tfstate.backup
terraform.tfvars
*.tfplan
.terraform/
AWS keys
GCP service-account JSON
Vault tokens
private keys
```

---

# 95. Terraform Command Lifecycle

The normal workflow is:

```text
terraform init
      |
terraform fmt
      |
terraform validate
      |
terraform plan
      |
manual review
      |
terraform apply
      |
verification
```

Do not jump directly to `apply`.

---

# 96. `terraform init`

Run:

```bash
terraform init
```

It:

- initializes the working directory
- downloads providers
- initializes modules
- initializes backend configuration
- creates/updates the dependency lock file

Run it when:

- first cloning project
- adding/changing providers
- adding/changing modules
- changing backend config

---

# 97. `terraform fmt`

```bash
terraform fmt -recursive
```

Formats Terraform code consistently.

It is similar to a code formatter.

CI can later fail a pull request if Terraform is not properly formatted.

---

# 98. `terraform validate`

```bash
terraform validate
```

Checks whether configuration is structurally valid.

It does **not** prove:

- permissions are correct
- quotas are available
- CIDRs are available
- every cloud API operation will succeed

But it catches many configuration/syntax problems early.

---

# 99. `terraform plan`

```bash
terraform plan
```

This is one of the most important commands.

It shows what Terraform wants to do.

Example:

```text
Plan: 12 to add, 0 to change, 0 to destroy.
```

Before applying, read the plan.

Especially watch for:

```text
to destroy
must be replaced
```

Unexpected destruction is a stop signal.

---

# 100. Saved Plan Files

A safer workflow:

```bash
terraform plan -out=tfplan
```

Review:

```bash
terraform show tfplan
```

Then apply exactly that plan:

```bash
terraform apply tfplan
```

This reduces the chance that the plan you reviewed differs from the configuration applied immediately afterward.

Do not commit `tfplan`.

---

# 101. `terraform apply`

This creates or updates real infrastructure.

Use only after reviewing the plan.

```bash
terraform apply tfplan
```

Infrastructure changes can:

- cost money
- expose services
- delete resources
- change networking
- break workloads

Treat `apply` as a controlled change operation.

---

# 102. `terraform destroy`

```bash
terraform destroy
```

This can remove infrastructure.

Do not run casually.

Before using it:

```bash
terraform plan -destroy
```

Review what will disappear.

Remember:

- ECR uses `force_delete = false`
- GKE deletion protection may later be enabled
- state and dependent resources matter

---

# 103. Recommended Apply Order

For this project:

## Phase A — GCP

```bash
cd ~/devsecops/OT-Masters/terraform/gcp

terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=gcp.tfplan
terraform show gcp.tfplan
terraform apply gcp.tfplan
```

Then:

```bash
terraform output
```

Verify:

```bash
gcloud container clusters list
kubectl get nodes
```

## Phase B — obtain NAT IP

```bash
terraform output -raw nat_public_ip
echo
```

## Phase C — AWS

```bash
cd ../aws

cp terraform.tfvars.example terraform.tfvars
```

Put NAT IP into:

```hcl
jenkins_source_cidrs = [
  "NAT_IP/32"
]
```

Then:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=aws.tfplan
terraform show aws.tfplan
terraform apply aws.tfplan
```

---

# 104. Current Dependency Graph

At a high level:

```text
                         GCP APIs
                            |
            +---------------+---------------+
            |                               |
            v                               v
      Network Module                  GCP IAM Module
            |                               |
            |                               |
            +---------------+---------------+
                            |
                            v
                        GKE Module
                            |
                            v
                    Static NAT output
                            |
                            v
                       AWS ECR Stack
```

Inside network:

```text
VPC
 |
 +--> Subnet
 |
 +--> Cloud Router
         |
         +--> Static IP
         |
         └--> Cloud NAT
```

Inside GKE:

```text
Network + Subnet + IP ranges
            +
Node Service Account
            |
            v
       GKE Cluster
            |
            v
       Node Pool
```

---

# 105. Final Infrastructure Architecture

```text
                           LOCAL UBUNTU VM
                                  |
                  +---------------+---------------+
                  |                               |
              Terraform                       kubectl
                  |                               |
        +---------+---------+                     |
        |                   |                     |
        v                   v                     |
       GCP                 AWS                    |
        |                   |                     |
        |                  ECR                    |
        |                   ^                     |
        |                   |                     |
        |                   | image push/pull     |
        |                   |                     |
        |             fixed NAT source IP         |
        |                   ^                     |
        |                   |                     |
   devsecops-vpc            |                     |
        |                   |                     |
   GKE subnet               |                     |
   ├── node CIDR            |                     |
   ├── pod CIDR             |                     |
   └── svc CIDR             |                     |
        |                   |                     |
   Cloud Router             |                     |
        |                   |                     |
   Cloud NAT ---------------+                     |
        |                                         |
    Private GKE <---------------------------------+
        |
        +── private nodes
        +── Workload Identity
        +── Dataplane V2
        +── Shielded Nodes
        +── Secure Boot
        +── logging
        +── monitoring
        |
        +── Jenkins (later)
        +── Vault (later)
        +── Argo CD (later)
        +── SonarQube (later)
        +── DefectDojo (later)
        +── Gatekeeper (later)
        +── Falco (later)
        +── staging
        └── production
```

---

# 106. Why Jenkins Will Not Deploy Directly

Terraform prepares the platform, but later our CI/CD architecture follows this rule:

```text
Jenkins = CI
Argo CD = CD
Git = desired state
```

Jenkins will:

```text
checkout
test
Gitleaks
SonarQube
Trivy SCA
build image
Trivy image
generate SBOM
push ECR
update GitOps repo
```

Jenkins should **not** normally do:

```bash
kubectl apply
helm upgrade
```

for application deployment.

Instead:

```text
Jenkins
 |
updates image digest in Git
 |
GitOps repository
 |
Argo CD detects change
 |
Argo CD reconciles GKE
```

That preserves Git as the source of truth.

---

# 107. Security Layers We Are Building

The infrastructure already begins defense in depth.

```text
Layer 1 — Source
GitHub controls / branch protections

Layer 2 — CI
Gitleaks
SonarQube
Trivy

Layer 3 — Supply chain
ECR
immutable tags
SBOM
Cosign later

Layer 4 — Cloud identity
dedicated service accounts
least privilege

Layer 5 — Cluster identity
Workload Identity Federation

Layer 6 — Network
private nodes
Cloud NAT
VPC Flow Logs
Dataplane V2
NetworkPolicy later

Layer 7 — Admission
OPA Gatekeeper later

Layer 8 — Runtime
Falco later

Layer 9 — Vulnerability management
DefectDojo later

Layer 10 — Detection/SIEM
Cloud Logging
Google SecOps later
```

Security is not one scanner.

Security is a set of controls across the complete delivery lifecycle.

---

# 108. Things We Intentionally Have NOT Done Yet

This is important.

The Terraform is not "finished forever."

We are building incrementally.

Not yet completed:

```text
Remote GCS Terraform backend
Terraform state IAM hardening
separate prod infrastructure/project
private-only GKE API endpoint
VPN/private admin access
AWS ↔ GCP workload federation
dynamic ECR authentication
Binary Authorization / image verification
KMS customer-managed keys
multiple specialized node pools
organization policies
Cloud Armor
advanced audit/SIEM sinks
backup/disaster recovery
budget alerts
```

We will add features when we understand why they are needed.

That is better than pasting 2,000 lines of "secure Terraform" without understanding the architecture.

---

# 109. Lab Design vs Production Design

Some current choices are optimized for learning.

Example:

```hcl
enable_private_endpoint = false
deletion_protection     = false
```

Those settings are reasonable during iteration.

A more hardened production design might use:

```text
private control-plane administration
VPN / bastion / private access
deletion protection
multiple projects
separate production cluster
stricter organization policies
dedicated node pools
higher availability
backup/restore
KMS
formal change approval
```

We should understand the lab architecture first, then harden it deliberately.

---

# 110. Cost Awareness

This project can generate real cloud cost.

Major cost areas include:

```text
GKE worker nodes
regional GKE resources
persistent disks
network egress
Cloud Logging
VPC Flow Logs
NAT
AWS ECR storage
ECR enhanced scanning
security tools deployed to Kubernetes
SonarQube
DefectDojo
```

Security tooling is not free just because it runs in Kubernetes.

As part of DevSecOps engineering, always understand both:

```text
security impact
+
cost impact
```

---

# 111. Before Every Terraform Apply

Use this checklist:

```text
[ ] Correct GCP project?
[ ] Correct AWS account/profile?
[ ] Correct region?
[ ] Correct public admin IP?
[ ] terraform fmt passes?
[ ] terraform validate passes?
[ ] Reviewed terraform plan?
[ ] Unexpected destroys = zero?
[ ] Secrets not present in .tf files?
[ ] terraform.tfvars not staged in Git?
[ ] State file not staged in Git?
[ ] Understand estimated cloud cost?
```

Check Git:

```bash
git status
```

Check GCP:

```bash
gcloud config get-value project
gcloud auth list
```

Check AWS:

```bash
aws sts get-caller-identity
```

---

# 112. Useful Verification Commands

## GCP

```bash
gcloud compute networks list
```

```bash
gcloud compute networks subnets list
```

```bash
gcloud compute routers list
```

```bash
gcloud compute routers nats list \
  --router=devsecops-vpc-router \
  --region=europe-west1
```

```bash
gcloud container clusters list
```

## Kubernetes

```bash
kubectl cluster-info
```

```bash
kubectl get nodes -o wide
```

```bash
kubectl get pods -A
```

```bash
kubectl get ns
```

## Workload Identity

```bash
gcloud container clusters describe devsecops-gke \
  --region europe-west1 \
  --format="value(workloadIdentityConfig.workloadPool)"
```

Expected concept:

```text
PROJECT_ID.svc.id.goog
```

## AWS

```bash
aws sts get-caller-identity
```

```bash
aws ecr describe-repositories \
  --region eu-central-1 \
  --repository-names devsecops-webapp
```

---

# 113. Common Mistake — Wrong Admin IP

Symptom:

```text
kubectl cannot reach cluster
```

Check current public IP:

```bash
curl -4 -fsSL https://ifconfig.me
echo
```

Compare with:

```hcl
admin_cidr
```

If your ISP changed the address:

```bash
terraform plan
terraform apply
```

to update Master Authorized Networks.

---

# 114. Common Mistake — Wrong GCP Authentication

Terraform may report authentication errors.

Check:

```bash
gcloud auth list
```

Then:

```bash
gcloud auth application-default login
```

Remember:

```text
gcloud CLI login
```

and:

```text
Application Default Credentials
```

are related but not exactly the same credential flow.

---

# 115. Common Mistake — Wrong GCP Project

Always verify:

```bash
gcloud config get-value project
```

and compare it with:

```hcl
project_id
```

Terraform creating a cluster in the wrong project is an expensive mistake.

---

# 116. Common Mistake — Wrong AWS Account

Before AWS Terraform:

```bash
aws sts get-caller-identity
```

Read:

```text
Account
Arn
```

Do not assume your active AWS shell credentials are correct.

---

# 117. Common Mistake — Committing Secrets

Before push:

```bash
git status
```

and eventually:

```bash
gitleaks git .
```

Never commit:

```text
AWS access keys
GCP JSON keys
Vault tokens
private keys
passwords
terraform state
real secret tfvars
```

If a secret reaches Git history, deleting the line from the latest commit is not enough.

The credential should normally be rotated/revoked.

---

# 118. Common Mistake — Huge Terraform Changes

Do not modify:

```text
network
GKE
IAM
AWS
10 security systems
```

and then run one giant apply without understanding the plan.

Better:

```text
Step 1 network
review

Step 2 IAM
review

Step 3 GKE
review

Step 4 AWS ECR
review
```

This project is about learning DevSecOps architecture, not just reaching a green `apply`.

---

# 119. How to Read a Terraform Resource Address

You may see:

```text
module.network.google_compute_network.this
```

Break it down:

```text
module.network
    |
    module instance named "network"

google_compute_network
    |
    resource type

this
    |
    local Terraform resource name
```

Another example:

```text
module.gke.google_container_node_pool.primary
```

means:

```text
GKE module
  └── google_container_node_pool
      └── Terraform local name: primary
```

---

# 120. How Variables Flow Through the Project

Example: Pod CIDR.

You configure:

```hcl
# gcp/terraform.tfvars
pod_ipv4_cidr = "10.20.0.0/16"
```

Terraform loads:

```text
gcp/variables.tf
```

Then root module passes:

```hcl
module "network" {
  pod_ipv4_cidr = var.pod_ipv4_cidr
}
```

Network module receives:

```hcl
variable "pod_ipv4_cidr"
```

Then resource uses it:

```hcl
secondary_ip_range {
  ip_cidr_range = var.pod_ipv4_cidr
}
```

Flow:

```text
terraform.tfvars
      |
      v
root variable
      |
      v
module argument
      |
      v
module variable
      |
      v
GCP resource
```

Understanding this pattern makes Terraform modules much easier.

---

# 121. How Outputs Flow Between Modules

Example:

Network module creates:

```text
google_compute_network.this
```

and outputs:

```hcl
output "network_id" {
  value = google_compute_network.this.id
}
```

Root receives it:

```hcl
module.network.network_id
```

Then sends it to GKE:

```hcl
module "gke" {
  network_id = module.network.network_id
}
```

So:

```text
Network resource
    |
network module output
    |
root module
    |
GKE module input
    |
GKE cluster
```

Terraform automatically sees this dependency.

---

# 122. Terraform Does Not Care About File Order

These can exist:

```text
main.tf
variables.tf
outputs.tf
services.tf
```

Terraform loads them together.

It does not execute:

```text
main.tf first
variables.tf second
outputs.tf third
```

The separation exists to make the project readable.

---

# 123. Why We Use `main.tf`, `variables.tf`, and `outputs.tf`

Common convention:

```text
main.tf
→ resources / module logic

variables.tf
→ inputs

outputs.tf
→ returned values

providers.tf
→ provider configuration

versions.tf
→ Terraform/provider versions

services.tf
→ project API enablement

terraform.tfvars
→ actual environment values
```

This makes it easy for another engineer to understand the codebase.

---

# 124. Future Terraform Security Scanning

Terraform itself becomes part of the DevSecOps pipeline.

Later CI should scan IaC before merge.

Possible flow:

```text
Terraform PR
   |
terraform fmt -check
   |
terraform validate
   |
Trivy config .
   |
policy checks
   |
terraform plan
   |
manual approval
```

This is "security as code."

Infrastructure code is production code and should be tested/scanned like application code.

---

# 125. Future GitHub Protection

For Terraform changes, production practice should include:

```text
Pull Request
    |
Code review
    |
IaC security scan
    |
Terraform plan
    |
Approval
    |
Apply
```

Avoid allowing every developer to apply production Terraform directly from a laptop.

For our lab, local administration helps us learn the components first.

---

# 126. Mental Model to Remember

If you remember only one diagram, use this:

```text
terraform.tfvars
       |
       v
Root configuration
       |
       +-----------------------+
       |                       |
       v                       v
   GCP modules              AWS module
       |                       |
       v                       v
Network + IAM + GKE          ECR + IAM
       |
       v
Private Kubernetes platform
       |
       v
Jenkins / Argo CD / Vault / Security Tools
       |
       v
GitOps application delivery
```

And remember the responsibility separation:

```text
Terraform
= infrastructure

Jenkins
= build + test + security gates

ECR
= image registry

Git
= desired application state

Argo CD
= deployment/reconciliation

GKE
= runtime platform

Vault
= secret management

Gatekeeper
= admission policy

Falco
= runtime detection

DefectDojo
= vulnerability management

Google SecOps
= SIEM / security analytics
```

---

# 127. Recommended Next Learning Steps

Do not rush to Jenkins yet.

We should validate Terraform in this order:

### Step 1 — understand and validate Network

```text
VPC
Subnet
Pod CIDR
Service CIDR
Flow Logs
Static NAT IP
Cloud Router
Cloud NAT
```

### Step 2 — understand IAM

```text
GKE node service account
least privilege
```

### Step 3 — understand GKE

```text
regional cluster
private nodes
authorized control-plane access
VPC-native networking
Workload Identity
Dataplane V2
Shielded Nodes
node pool
```

### Step 4 — apply GCP

Verify every resource.

### Step 5 — create AWS ECR

Use GCP NAT output.

### Step 6 — remote Terraform state

Move local state to secured GCS.

### Step 7 — Kubernetes platform bootstrap

Then begin:

```text
Vault
Jenkins
SonarQube
Argo CD
```

---

# 128. Short Summary

Our Terraform architecture is deliberately designed around five principles.

## 1. Reusability

Infrastructure logic lives in modules.

```text
modules/network
modules/gcp-iam
modules/gke
modules/aws-ecr
```

## 2. Least Privilege

We create dedicated identities and avoid broad permissions.

## 3. Private-by-Default Compute

GKE worker nodes do not receive normal public IPs.

## 4. Observable Infrastructure

Flow logs, Kubernetes logs, and monitoring are enabled as foundations for later SIEM integration.

## 5. GitOps-Friendly Separation

Terraform creates the platform.

Terraform/Jenkins will not become application deployment controllers.

Argo CD will eventually own application reconciliation.

---

# 129. Final Rule

Before changing any Terraform resource, ask these questions:

```text
What problem is this resource solving?

Why is this permission required?

Why is this network path required?

Can the scope be smaller?

Does this expose anything publicly?

Will it create a secret?

Will the secret appear in Terraform state?

What will happen during destroy?

What is the cost?

How will we monitor it?

How will we verify it after apply?
```

If you can answer those questions, you are not just "using Terraform."

You are thinking like a Cloud / DevSecOps engineer.
