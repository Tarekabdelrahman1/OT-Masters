# Jenkins on GKE — Installation, Architecture, Helm, UI, and Jenkinsfile Documentation

> Project: **OT-Masters / FitGear DevSecOps**
>
> GCP Project: `devops-project-503113`
>
> GKE Cluster: `devsecops-gke`
>
> Region: `europe-west1`
>
> Jenkins Helm Release: `jenkins`
>
> Namespace: `jenkins`
>
> Helm Chart: `jenkins/jenkins` chart `5.9.54`
>
> Jenkins App Version reported by Helm: `2.568.2`
>
> AWS ECR Registry: `365811604437.dkr.ecr.eu-central-1.amazonaws.com`
>
> ECR Repository: `devsecops-webapp`

---

# 1. Architecture Decision

We had two possible Jenkins locations:

```text
Option A
Admin VM
└── Jenkins

Option B
GKE
├── Jenkins Controller Pod
└── Dynamic Jenkins Agent Pods
```

We selected **Option B**.

The admin VM remains an administration workstation:

```text
devsecops-vm
|
+-- terraform
+-- gcloud
+-- kubectl
+-- helm
+-- aws cli
+-- troubleshooting tools
```

The Jenkins design is:

```text
GitHub
  |
  v
Jenkins Controller in GKE
  |
  v
Dynamic Jenkins Agent Pods
  |
  +--> security scans
  +--> build
  +--> ECR push
  +--> GitOps update
```

Why this design:

- separates the management VM from CI workloads;
- supports ephemeral Kubernetes agents;
- allows build workloads to scale independently;
- keeps the controller focused on orchestration;
- lets GKE-originated AWS traffic leave through the known GCP Cloud NAT path.

---

# 2. Controller vs Agent

## Controller

The controller handles:

```text
UI
jobs
Pipeline orchestration
credentials metadata
plugins
build scheduling
Kubernetes agent provisioning
build history
```

It should not be our normal build machine.

That is why we set:

```yaml
controller:
  numExecutors: 0
```

Meaning:

```text
Controller
   |
   +--> orchestrates
   +--> schedules
   |
   X--> normal build execution
```

## Agent

The agent is where CI commands should run.

Examples:

```text
git
gitleaks
sonar-scanner
trivy
image build
aws cli
cosign
kustomize
```

The long-term model is:

```text
Build #101
   |
   +--> temporary Agent Pod
            |
            +--> run CI
            |
            X deleted after build
```

---

# 3. GKE State Before Jenkins

Before Jenkins installation, the worker node pool was restored by Terraform.

Terraform reported:

```text
Resources: 1 added, 1 changed, 0 destroyed.
```

Then GKE showed two Ready private worker nodes.

Important properties:

```text
Node internal IPs:
10.10.0.9
10.10.0.10

External worker-node IP:
none

OS:
Container-Optimized OS

Runtime:
containerd
```

Current known GCP Cloud NAT IP:

```text
35.205.238.62
```

This matters because the AWS ECR IAM design is intended to restrict Jenkins ECR access to traffic coming through that NAT IP.

---

# 4. Why the Node Pool Was Restored with Terraform

At one point the cluster existed but the Terraform-managed node pool did not.

A manual resize failed because there was no node pool to resize.

The correct recovery path was Terraform.

Mental model:

```text
Terraform configuration
        |
        | desired state
        v
GCP actual state
        |
        | difference / drift
        v
terraform plan
        |
        v
terraform apply
        |
        v
desired node pool restored
```

We intentionally avoided manually creating a replacement node pool with `gcloud`, because Terraform is the infrastructure source of truth.

---

# 5. Jenkins Namespace

We created a dedicated namespace:

```bash
kubectl create namespace jenkins
```

Architecture:

```text
GKE
|
+-- jenkins
|    +-- controller
|    +-- agents
|    +-- Jenkins Services
|    +-- PVC
|    +-- RBAC
|
+-- staging
|    +-- FitGear workloads
|
+-- production
|
+-- later
     +-- argocd
     +-- vault
     +-- security
```

A dedicated namespace helps with:

- organization;
- RBAC;
- NetworkPolicy;
- troubleshooting;
- quotas and limits later;
- lifecycle management.

---

# 6. Storage Classes

The cluster reported:

```text
dynamic-rwo              pd.csi.storage.gke.io
premium-rwo              pd.csi.storage.gke.io
standard                 kubernetes.io/gce-pd
standard-rwo (default)   pd.csi.storage.gke.io
```

We selected:

```text
standard-rwo
```

The storage path is:

```text
Jenkins
  |
  v
PersistentVolumeClaim
  |
  v
StorageClass: standard-rwo
  |
  v
GKE Persistent Disk CSI
  |
  v
Google Persistent Disk
```

---

# 7. Why Jenkins Needs Persistence

A Pod filesystem is disposable.

Without persistent storage:

```text
Jenkins Pod
   |
   | configuration/data
   |
Pod recreated
   |
   v
data risk
```

With persistence:

```text
jenkins-0
   |
   v
/var/jenkins_home
   |
   v
PVC: jenkins
   |
   v
Persistent Disk
```

This allows the Jenkins controller to retain state across Pod recreation.

---

# 8. Helm Basics

Helm is a package manager for Kubernetes.

A Helm **chart** contains reusable Kubernetes templates.

The Jenkins chart can generate resources such as:

```text
ServiceAccount
Secret
ConfigMap
RBAC
Service
PersistentVolumeClaim
StatefulSet
Jenkins Configuration as Code configuration
```

Instead of manually maintaining every generated manifest, we provide project-specific overrides in:

```text
jenkins-values.yaml
```

Concept:

```text
Jenkins chart defaults
       +
jenkins-values.yaml
       |
       v
rendered Kubernetes resources
```

---

# 9. Jenkins Helm Repository

We added the official Jenkins repository:

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
```

Then:

```bash
helm search repo jenkins/jenkins
```

returned:

```text
jenkins/jenkins
Chart version: 5.9.54
App version:   2.568.2
```

The chart version and application version are different:

```text
Chart version
=
version of Kubernetes/Helm packaging

App version
=
Jenkins application version associated with the chart
```

---

# 10. Our `jenkins-values.yaml`

Current values:

```yaml
controller:
  serviceType: ClusterIP

  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "2Gi"

  numExecutors: 0

  healthProbes: true

persistence:
  enabled: true
  storageClass: standard-rwo
  accessMode: ReadWriteOnce
  size: 20Gi

agent:
  enabled: true

  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "1"
      memory: "1Gi"
```

---

# 11. `controller.serviceType: ClusterIP`

```yaml
serviceType: ClusterIP
```

We deliberately avoided a public `LoadBalancer`.

Current Service:

```text
jenkins
TYPE: ClusterIP
CLUSTER-IP: 10.30.12.89
PORT: 8080
```

Meaning:

```text
Internet
   |
   X
   |
Jenkins
```

but inside Kubernetes:

```text
client
  |
  v
jenkins Service:8080
  |
  v
jenkins-0
```

For initial UI access we use port forwarding rather than public exposure.

---

# 12. Controller Resource Requests

```yaml
requests:
  cpu: "500m"
  memory: "1Gi"
```

A request is used by Kubernetes when scheduling the Pod.

Here:

```text
500m CPU = 0.5 CPU core
1Gi RAM  = 1 GiB requested memory
```

If a node cannot satisfy requests, Kubernetes will not schedule the Pod there.

---

# 13. Controller Resource Limits

```yaml
limits:
  cpu: "2"
  memory: "2Gi"
```

These are resource ceilings for the container.

Initial model:

```text
request:
500m CPU
1Gi RAM

limit:
2 CPU
2Gi RAM
```

We should tune them based on measured Jenkins usage later.

---

# 14. `numExecutors: 0`

```yaml
numExecutors: 0
```

This is an important design choice.

The controller should do:

```text
UI
orchestration
scheduling
configuration
```

and agents should do:

```text
build
scan
test
push
```

---

# 15. `healthProbes: true`

This enables Kubernetes health probes generated by the chart.

They help Kubernetes understand whether the controller:

```text
started
is alive
is ready
```

---

# 16. Persistence

```yaml
persistence:
  enabled: true
```

enables persistent Jenkins home storage.

We explicitly selected:

```yaml
storageClass: standard-rwo
accessMode: ReadWriteOnce
size: 20Gi
```

Our rendered PVC proved the configuration:

```yaml
accessModes:
  - "ReadWriteOnce"

resources:
  requests:
    storage: "20Gi"

storageClassName: "standard-rwo"
```

After installation:

```text
PVC:          jenkins
STATUS:       Bound
CAPACITY:     20Gi
ACCESS MODE:  RWO
STORAGECLASS: standard-rwo
```

---

# 17. Agent Configuration

```yaml
agent:
  enabled: true
```

enables the chart's default Kubernetes agent configuration.

Initial resources:

```yaml
requests:
  cpu: "250m"
  memory: "512Mi"

limits:
  cpu: "1"
  memory: "1Gi"
```

These are only starting values.

Our final CI/security agent may require more resources.

---

# 18. Why We Used `helm template`

Before installation we ran:

```bash
helm template jenkins jenkins/jenkins   --namespace jenkins   -f jenkins-values.yaml   > rendered-jenkins.yaml
```

This rendered the chart locally.

Important distinction:

```text
helm template
=
preview only

helm install / upgrade
=
changes Kubernetes
```

This is similar in spirit to reviewing a Terraform plan before apply.

---

# 19. What We Reviewed in the Render

The generated YAML contained resources including:

```text
ServiceAccount
Secret
ConfigMap
RBAC
PersistentVolumeClaim
Services
StatefulSet
```

We reviewed the PVC and verified:

```text
20Gi
ReadWriteOnce
standard-rwo
```

We reviewed Services and verified both were `ClusterIP`.

Controller Service:

```text
jenkins
port 8080
ClusterIP
```

Agent listener Service:

```text
jenkins-agent
port 50000
ClusterIP
```

No public external Jenkins IP was created.

---

# 20. Why We Deleted `rendered-jenkins.yaml`

The rendered output included a generated Kubernetes Secret containing the admin credential encoded as Base64.

Remember:

```text
Base64 != encryption
```

Therefore we deleted:

```bash
rm -f rendered-jenkins.yaml
```

and added:

```text
platform/jenkins/rendered-jenkins.yaml
```

to `.gitignore`.

Do not commit rendered Secret material.

---

# 21. Installing Jenkins

We ran:

```bash
helm upgrade --install jenkins jenkins/jenkins   --namespace jenkins   --create-namespace   -f jenkins-values.yaml   --wait   --timeout 10m
```

Breakdown:

## `upgrade --install`

```text
release missing  -> install
release existing -> upgrade
```

## First `jenkins`

```text
Helm release name
```

## `jenkins/jenkins`

```text
repository alias / chart name
```

## `--namespace jenkins`

install namespaced resources in the `jenkins` namespace.

## `--create-namespace`

create namespace if required.

## `-f jenkins-values.yaml`

use our project-specific chart overrides.

## `--wait`

wait for important resources to become ready before declaring success.

## `--timeout 10m`

allow up to ten minutes for the operation.

---

# 22. Helm Result

Helm reported:

```text
NAME: jenkins
NAMESPACE: jenkins
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

Meaning:

```text
Release name: jenkins
Release state: successfully deployed
Revision: first installed version
```

When we later upgrade values, Helm release revisions increase.

Useful:

```bash
helm history jenkins -n jenkins
```

---

# 23. Current Jenkins Kubernetes State

Helm release:

```text
jenkins
STATUS: deployed
CHART: jenkins-5.9.54
APP VERSION: 2.568.2
```

Controller Pod:

```text
jenkins-0
READY: 2/2
STATUS: Running
RESTARTS: 0
```

PVC:

```text
jenkins
Bound
20Gi
RWO
standard-rwo
```

Services:

```text
jenkins
ClusterIP
10.30.12.89
8080/TCP

jenkins-agent
ClusterIP
10.30.2.215
50000/TCP
```

This is a healthy starting point.

---

# 24. Why the Pod Is `jenkins-0`

The Helm chart uses a StatefulSet for the Jenkins controller.

StatefulSet Pod naming is stable:

```text
StatefulSet: jenkins
      |
      v
Pod: jenkins-0
```

That model works well with persistent state.

---

# 25. What `2/2 Running` Means

```text
READY 2/2
```

means two containers in the Pod are Ready.

Inspect exact container names:

```bash
kubectl get pod jenkins-0   -n jenkins   -o jsonpath='{.spec.containers[*].name}'

echo
```

Useful rule:

```text
inspect actual Pod containers
instead of guessing names during troubleshooting
```

---

# 26. Jenkins UI — Get Admin Password

The Helm installation created an admin account.

Username:

```text
admin
```

Retrieve password:

```bash
kubectl exec   --namespace jenkins   -it svc/jenkins   -c jenkins   -- /bin/cat /run/secrets/additional/chart-admin-password

echo
```

Alternative:

```bash
kubectl get secret jenkins   -n jenkins   -o jsonpath='{.data.jenkins-admin-password}' | base64 --decode

echo
```

Do not commit or paste this password into repository files.

---

# 27. Jenkins UI — Port Forward

On the **devsecops VM**:

```bash
kubectl -n jenkins   port-forward svc/jenkins 8080:8080
```

Keep this terminal running.

Path:

```text
devsecops-vm:127.0.0.1:8080
        |
        v
kubectl port-forward
        |
        v
jenkins Service
        |
        v
Jenkins controller
```

---

# 28. Important: Browser Is Usually on Your Laptop

If `kubectl port-forward` runs on the remote VM, the VM's `localhost` is not your laptop's `localhost`.

Use an SSH local tunnel.

## Terminal 1 — devsecops VM

```bash
kubectl -n jenkins   port-forward svc/jenkins 8080:8080
```

## Terminal 2 — local workstation

```bash
ssh   -L 8080:127.0.0.1:8080   <VM_USER>@<DEVSECOPS_VM_PUBLIC_IP>
```

Then open locally:

```text
http://127.0.0.1:8080
```

Traffic:

```text
Laptop Browser
       |
       v
SSH local forwarding
       |
       v
devsecops-vm localhost:8080
       |
       v
kubectl port-forward
       |
       v
Jenkins ClusterIP Service
       |
       v
jenkins-0
```

This allows us to keep Jenkins private.

---

# 29. First Login

Open:

```text
http://127.0.0.1:8080
```

Login:

```text
Username: admin
Password: value retrieved from Kubernetes
```

Do not expose Jenkins publicly yet.

---

# 30. What to Inspect in the UI

First inspect:

```text
Manage Jenkins
|
+-- Plugins
+-- Credentials
+-- Clouds
+-- Nodes
+-- System
+-- Security
```

Do not configure every integration immediately.

We will build one capability at a time.

---

# 31. Default Helm Plugin Baseline

The current official Jenkins Helm chart defines a default plugin baseline including:

```text
Kubernetes plugin
Pipeline/workflow aggregator
Git plugin
Configuration as Code
```

Our complete Jenkinsfile requires additional integrations.

---

# 32. Plugins Needed by the Current Jenkinsfile

Verify/install only what is actually needed.

Our Pipeline requires functionality from plugins such as:

```text
Kubernetes
Pipeline
Git
Configuration as Code
SonarQube Scanner for Jenkins
AWS Credentials
Credentials Binding
Workspace Cleanup
```

Examples:

```groovy
withSonarQubeEnv(...)
waitForQualityGate()
```

require SonarQube Jenkins integration.

```groovy
$class: 'AmazonWebServicesCredentialsBinding'
```

requires AWS credential binding support.

```groovy
cleanWs(...)
```

requires workspace cleanup support.

---

# 33. Current Jenkinsfile — High-Level Flow

The current Jenkinsfile implements:

```text
Checkout
   |
   v
Gitleaks
   |
   v
SonarQube SAST
   |
   v
Sonar Quality Gate
   |
   v
Trivy Filesystem / SCA
   |
   +--> optional Lynis + Docker Bench
   |
   v
Docker Build
   |
   v
Trivy Image Scan
   |
   v
Runtime Hardening Validation
   |
   v
InSpec / Cinc
   |
   v
SBOM
   |
   v
Push to ECR
   |
   v
Cosign Sign
   |
   v
Update GitOps Repository
   |
   v
Argo CD later reconciles GKE
```

It is a strong target Pipeline, but several integrations are intentionally not ready yet.

---

# 34. Jenkinsfile Top Level

Current:

```groovy
pipeline {
    agent any
```

This is a Declarative Pipeline.

Because the controller has:

```text
numExecutors = 0
```

the Pipeline must eventually run on agents.

Before running the full Pipeline, we first need to prove dynamic Kubernetes agent provisioning works.

---

# 35. Pipeline Options

```groovy
disableConcurrentBuilds()
```

prevents concurrent builds of the same job.

```groovy
timeout(time: 60, unit: 'MINUTES')
```

prevents indefinitely stuck builds.

```groovy
timestamps()
```

adds timestamps to Jenkins console output.

```groovy
buildDiscarder(logRotator(numToKeepStr: '30'))
```

limits build-history growth.

---

# 36. Host Security Audit Parameter

Current parameter:

```text
RUN_HOST_SECURITY_AUDIT
```

Default:

```text
false
```

When enabled, the Pipeline expects a dedicated agent labeled:

```text
docker-security-host
```

for:

```text
Lynis
Docker Bench for Security
```

That agent is not the Jenkins controller.

---

# 37. Application Values

```groovy
APP_NAME    = 'fitgear-backend'
ENVIRONMENT = 'staging'
```

Used for application naming, GitOps pathing, release metadata, and temporary runtime container naming.

---

# 38. Real AWS/ECR Values

Current real values:

```groovy
AWS_REGION     = 'eu-central-1'
AWS_ACCOUNT_ID = '365811604437'
ECR_REPOSITORY = 'devsecops-webapp'
```

Registry:

```text
365811604437.dkr.ecr.eu-central-1.amazonaws.com
```

Full image format:

```text
365811604437.dkr.ecr.eu-central-1.amazonaws.com/devsecops-webapp:<IMAGE_TAG>
```

---

# 39. Git SHA and Image Tag

Global values start empty:

```groovy
GIT_SHA   = ''
IMAGE_TAG = ''
IMAGE_URI = ''
```

After checkout, the Pipeline calculates:

```bash
git rev-parse HEAD
```

and:

```bash
git rev-parse --short=7 HEAD
```

The short Git SHA becomes the immutable traceable image tag.

Example:

```text
Git commit:
a91c73e4f2...

Image tag:
a91c73e
```

Then:

```text
IMAGE_URI =
365811604437.dkr.ecr.eu-central-1.amazonaws.com/devsecops-webapp:a91c73e
```

This is better than using `latest`.

---

# 40. Checkout Stage

The stage performs:

```groovy
checkout scm
```

then reads:

```text
full Git SHA
short Git SHA
Git origin URL
```

It creates:

```text
IMAGE_URI
SBOM_REPORT
RUNTIME_TEST_CONTAINER
```

This creates traceability between:

```text
source commit
     |
     v
container image
     |
     v
SBOM
     |
     v
GitOps release
```

---

# 41. Gitleaks

Runs:

```bash
gitleaks detect
```

with a JSON report and nonzero failure behavior.

Purpose:

```text
hard-coded secret detected
        |
        v
security gate fails
```

The report is archived even on failure.

---

# 42. SonarQube

The Pipeline uses:

```text
credential ID:
sonarqube-token

configured Jenkins Sonar server:
sonarqube-server
```

Current URL in the file:

```text
https://sonarqube.internal.fitgear.io
```

This URL has **not yet been verified/deployed as part of the current environment**.

Before this stage can work, we need:

```text
SonarQube reachable
Sonar plugin configured
sonar-scanner on agent
token stored in Jenkins
```

---

# 43. Sonar Quality Gate

The Pipeline calls:

```groovy
waitForQualityGate()
```

and stops release when status is not:

```text
OK
```

So SAST becomes a gate, not only a report.

---

# 44. Trivy Filesystem / SCA

The Pipeline scans:

```text
source/dependencies
```

for:

```text
HIGH
CRITICAL
```

fixable findings.

Report:

```text
trivy-fs-report.json
```

The stage fails on findings matching its policy.

---

# 45. Optional Lynis + Docker Bench

Runs only when the parameter is enabled.

Expected dedicated agent requirements:

```text
label: docker-security-host
lynis
Docker Bench
sudo
Docker host access
/opt/docker-bench-security
```

This stage should remain separated from the controller.

---

# 46. Docker Build Stage

Current command:

```bash
docker build   --pull   --label "org.opencontainers.image.revision=$GIT_SHA"   --label "org.opencontainers.image.source=$GIT_SOURCE_URL"   -t "$IMAGE_URI"   -f backend/Dockerfile   backend
```

Important parts:

```text
--pull
refresh base-image reference

revision label
link image to Git SHA

source label
link image to source repository

-f backend/Dockerfile
use backend Dockerfile

backend
Docker build context
```

---

# 47. Critical Issue: Docker on Kubernetes Agents

Our GKE worker nodes use:

```text
containerd
```

The current Jenkinsfile expects Docker CLI/runtime operations:

```text
docker build
docker create
docker inspect
docker push
docker rm
docker logout
```

Therefore the complete Jenkinsfile will **not automatically run** just because Jenkins is installed.

We still need to design a safe build/runtime agent.

We should not blindly mount:

```text
/var/run/docker.sock
```

from a Kubernetes host into an untrusted CI Pod.

Possible architectures to evaluate:

```text
BuildKit-based agent
dedicated isolated Docker VM agent
carefully isolated Docker-in-Docker agent
daemonless image builder + redesign runtime checks
```

This is one of the next major technical decisions.

---

# 48. Trivy Image Scan

The built image is scanned for:

```text
HIGH
CRITICAL
```

fixable vulnerabilities.

Report:

```text
trivy-image-report.json
```

---

# 49. Runtime Hardening Validation

The Pipeline creates a test container with controls including:

```text
read-only root filesystem
tmpfs /tmp
drop ALL capabilities
no-new-privileges
memory limit
CPU limit
PID limit
```

Purpose:

```text
Can the image tolerate a hardened runtime configuration?
```

This stage also requires a Docker-compatible runtime environment on the agent.

---

# 50. InSpec / Cinc

The Pipeline tries:

```text
cinc-auditor
```

or falls back to:

```text
inspec
```

Profile:

```text
security/inspec/docker-runtime
```

Output:

```text
inspec-runtime-report.json
```

Required on agent:

```text
Cinc or InSpec
Docker runtime access
profile files
```

---

# 51. SBOM

The Pipeline uses Trivy to generate:

```text
SPDX JSON SBOM
```

Output pattern:

```text
sbom-<IMAGE_TAG>.spdx.json
```

This links the SBOM to the Git-derived image tag.

---

# 52. Push to ECR

The Pipeline references Jenkins credential:

```text
aws-jenkins-ecr-push
```

Then:

```bash
aws ecr get-login-password   --region "$AWS_REGION" | docker login   --username AWS   --password-stdin "$ECR_REGISTRY"

docker push "$IMAGE_URI"
```

Important current status:

Terraform created:

```text
IAM user:
jenkins-devsecops-ecr
```

and its ECR IAM policy.

Terraform intentionally did **not** create a long-lived access key.

Therefore:

```text
aws-jenkins-ecr-push
```

does not automatically exist in Jenkins.

We still need to choose the secure AWS authentication design.

---

# 53. AWS Source IP Restriction

The ECR IAM design uses GCP Cloud NAT IP:

```text
35.205.238.62/32
```

Expected path:

```text
Jenkins Agent Pod
       |
       v
Private GKE Node
       |
       v
Cloud NAT
       |
       v
35.205.238.62
       |
       v
AWS ECR
```

---

# 54. Cosign

Expected Jenkins credentials:

```text
cosign-private-key
cosign-key-password
```

The stage resolves the pushed image digest and signs:

```text
repository@sha256:<digest>
```

Those credentials still need a proper secrets-management design.

---

# 55. GitOps Update

Current Jenkinsfile points to:

```text
git@github.com:OmarHesham249/fitgear-gitops.git
```

Branch:

```text
main
```

Path:

```text
apps/fitgear-backend/overlays/staging
```

The stage expects:

```text
gitops-repo-deploy-key
github-known-hosts
```

It then runs:

```bash
kustomize edit set image ...
git commit
git push
```

Architecture:

```text
Jenkins
   |
   X--> no normal direct kubectl deployment
   |
   +--> GitOps Repo
            |
            v
          Argo CD
            |
            v
           GKE
```

---

# 56. DefectDojo Status

The Jenkinsfile currently contains:

```text
https://defectdojo.internal.fitgear.io
```

and describes it as a placeholder integration target.

DefectDojo ingestion is not implemented yet.

---

# 57. Jenkins Credentials Required by the Full Pipeline

| Credential ID | Purpose | Status |
|---|---|---|
| `sonarqube-token` | SonarQube auth | configure later |
| `aws-jenkins-ecr-push` | AWS/ECR auth | secure design needed |
| `cosign-private-key` | image signing | configure later |
| `cosign-key-password` | Cosign key password | configure later |
| `gitops-repo-deploy-key` | GitOps SSH push | configure later |
| `github-known-hosts` | SSH host verification | configure later |

---

# 58. Agent Tools Required

The full Jenkinsfile expects:

```text
git
bash
gitleaks
sonar-scanner
trivy
docker or equivalent runtime design
cinc-auditor or inspec
aws cli
cosign
kustomize
ssh
```

The optional host-security agent also needs:

```text
lynis
Docker Bench for Security
sudo permissions
```

A plain default JNLP agent is not enough for the final Pipeline.

---

# 59. Do Not Run the Full Pipeline Yet

Correct progression:

```text
1. Login to Jenkins UI
2. Verify plugins
3. Inspect Kubernetes Cloud
4. Run tiny dynamic-agent job
5. Verify checkout
6. Design build-agent image/runtime
7. Add Gitleaks
8. Add Trivy
9. Solve image build/runtime
10. Configure AWS auth
11. Push one image from Jenkins to ECR
12. Configure SonarQube
13. Configure Cosign
14. Configure GitOps SSH
15. Update GitOps
16. Argo CD deployment
```

This isolates problems instead of generating ten failures at once.

---

# 60. First Dynamic-Agent Test

Use a minimal Pipeline first:

```groovy
pipeline {
    agent any

    stages {
        stage('Hello') {
            steps {
                sh '''
                    echo "Hello from Jenkins"
                    hostname
                    whoami
                    cat /etc/os-release
                '''
            }
        }
    }
}
```

Goal:

```text
controller
   |
   v
requests executor
   |
   v
Kubernetes agent Pod appears
   |
   v
shell runs
   |
   v
build completes
```

Observe with:

```bash
kubectl get pods -n jenkins -w
```

---

# 61. Useful Jenkins Kubernetes Commands

```bash
kubectl get all -n jenkins
```

```bash
kubectl get pod jenkins-0 -n jenkins -o wide
```

```bash
kubectl describe pod jenkins-0 -n jenkins
```

```bash
kubectl logs jenkins-0 -n jenkins -c jenkins
```

```bash
kubectl logs jenkins-0 -n jenkins -c jenkins -f
```

```bash
kubectl get pvc -n jenkins
```

```bash
kubectl get svc -n jenkins
```

```bash
kubectl get serviceaccount -n jenkins
```

```bash
kubectl get role,rolebinding -n jenkins
```

---

# 62. Useful Helm Commands

Status:

```bash
helm status jenkins -n jenkins
```

List:

```bash
helm list -n jenkins
```

Values supplied by us:

```bash
helm get values jenkins -n jenkins
```

Release history:

```bash
helm history jenkins -n jenkins
```

Upgrade after changing `jenkins-values.yaml`:

```bash
helm upgrade --install jenkins jenkins/jenkins   --namespace jenkins   -f jenkins-values.yaml   --wait   --timeout 10m
```

Rollback:

```bash
helm rollback jenkins <REVISION> -n jenkins
```

---

# 63. Be Careful with Destructive Storage Operations

Current StorageClass has:

```text
ReclaimPolicy: Delete
```

The Jenkins PVC is:

```text
jenkins
20Gi
standard-rwo
```

Do not casually run:

```bash
kubectl delete pvc jenkins -n jenkins
```

Deleting a dynamically provisioned PVC with a Delete reclaim policy can result in deletion of the backing persistent storage.

Before destructive operations, create a backup/restore plan.

---

# 64. Restarting the Controller

If only the controller Pod needs to be recreated:

```bash
kubectl delete pod jenkins-0 -n jenkins
```

The StatefulSet should recreate it.

The PVC is intended to preserve Jenkins home independently of that Pod lifecycle.

---

# 65. Current Security Positives

```text
[+] no public Jenkins LoadBalancer
[+] controller executors disabled
[+] private GKE workers
[+] persistent Jenkins home
[+] namespace separation
[+] rendered Secret material not committed
[+] AWS Terraform did not create Jenkins access keys
[+] ECR IAM has GKE NAT source-IP design
```

Still to design:

```text
[ ] Jenkins authorization model
[ ] Kubernetes agent least privilege
[ ] NetworkPolicies
[ ] secure AWS authentication
[ ] purpose-built build agent
[ ] SonarQube integration
[ ] Vault integration
[ ] Cosign key management
[ ] GitOps credentials
[ ] backup/restore
```

---

# 66. Current Architecture

```text
                         GKE
                          |
                  namespace: jenkins
                          |
          +---------------+---------------+
          |                               |
          v                               v
 Service: jenkins                 Service: jenkins-agent
 ClusterIP 10.30.12.89            ClusterIP 10.30.2.215
 Port 8080                        Port 50000
          |                               |
          v                               |
     StatefulSet                          |
       jenkins                            |
          |                               |
          v                               |
     jenkins-0 <--------------------------+
      Ready 2/2
          |
          v
 /var/jenkins_home
          |
          v
     PVC jenkins
      20Gi RWO
          |
          v
   standard-rwo
          |
          v
 GCP Persistent Disk
```

Future agent lifecycle:

```text
Jenkins Controller
        |
        v
Kubernetes Plugin
        |
        +--> Agent Pod
        +--> Agent Pod
        +--> Agent Pod
```

---

# 67. Immediate Next Step

Right now, Jenkins installation is complete.

The next step is **UI access**.

## On devsecops VM

Get password:

```bash
kubectl exec   --namespace jenkins   -it svc/jenkins   -c jenkins   -- /bin/cat /run/secrets/additional/chart-admin-password

echo
```

Then keep this running:

```bash
kubectl -n jenkins   port-forward svc/jenkins 8080:8080
```

## On your local machine

Create SSH local forwarding:

```bash
ssh   -L 8080:127.0.0.1:8080   <VM_USER>@<DEVSECOPS_VM_PUBLIC_IP>
```

Then browse to:

```text
http://127.0.0.1:8080
```

Login:

```text
username: admin
password: retrieved Kubernetes Secret value
```

After login, stop before creating the full production Pipeline.

First inspect:

```text
Manage Jenkins
-> Plugins
-> Clouds
-> Nodes
-> Credentials
```

Then we will test one tiny Kubernetes agent.

---

# 68. Official Documentation References

Official Jenkins Kubernetes installation:

```text
https://www.jenkins.io/doc/book/installing/kubernetes/
```

Official Jenkins Pipeline / Jenkinsfile:

```text
https://www.jenkins.io/doc/book/pipeline/jenkinsfile/
```

Official Jenkins Pipeline syntax:

```text
https://www.jenkins.io/doc/book/pipeline/syntax/
```

Official Jenkins Helm chart values:

```text
https://github.com/jenkinsci/helm-charts/blob/main/charts/jenkins/values.yaml
```

Kubernetes StorageClass:

```text
https://kubernetes.io/docs/concepts/storage/storage-classes/
```

---

# 69. Final Review Answer

If someone asks what you did, explain it like this:

```text
I kept the admin VM as an administration workstation and deployed the
Jenkins controller into the private GKE platform.

I restored the Terraform-managed node pool first, then created a
dedicated Jenkins namespace.

I inspected the GKE StorageClasses and chose standard-rwo for Jenkins
persistent state.

I added the official Jenkins Helm repository and created a custom
jenkins-values.yaml.

The values configure a ClusterIP-only controller, explicit resource
requests/limits, zero controller executors, health probes, a persistent
20Gi RWO Jenkins home, and Kubernetes agents.

Before installation I used helm template to render and review the
Kubernetes resources without modifying the cluster.

I verified the PVC, Services and StatefulSet, and removed the rendered
file because it contained generated Secret material.

Then I installed Jenkins with helm upgrade --install and --wait.

The release is deployed, the Jenkins Pod is Running 2/2, the PVC is
Bound, and both Jenkins Services remain internal ClusterIP Services.

The next phase is not the full security Pipeline yet. First I will log
in to Jenkins, verify plugins and Kubernetes Cloud configuration, and
prove that a dynamic agent Pod can execute a minimal job. After that I
will build the specialized agent/tooling and add the DevSecOps stages
incrementally.
```

