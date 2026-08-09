#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# DevSecOps Bootstrap VM - Ubuntu 24.04 LTS
# Purpose:
#   Prepare a GCE Ubuntu VM as the ADMIN / BOOTSTRAP workstation for:
#   Terraform, GCP/GKE, AWS ECR, Helm, Argo CD, Vault and security tooling.
#
# IMPORTANT:
#   - This does NOT install Jenkins server. In our architecture Jenkins will run
#     inside GKE using dynamic Kubernetes agents.
#   - This does NOT store GCP/AWS credentials.
#   - Reboot/login again after running if you enable Docker group membership.
#
# Usage:
#   chmod +x bootstrap-devsecops-vm.sh
#   ./bootstrap-devsecops-vm.sh
#
# Optional:
#   ADD_USER_TO_DOCKER_GROUP=true ./bootstrap-devsecops-vm.sh
# ==============================================================================

if [[ "${EUID}" -eq 0 ]]; then
  echo "ERROR: Run this script as your normal Ubuntu user, not as root."
  echo "The script will use sudo when required."
  exit 1
fi

TARGET_USER="${USER}"
ADD_USER_TO_DOCKER_GROUP="${ADD_USER_TO_DOCKER_GROUP:-false}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

trap 'echo "ERROR: bootstrap failed at line $LINENO" >&2' ERR

# ------------------------------------------------------------------------------
# OS / architecture checks
# ------------------------------------------------------------------------------

source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
  echo "ERROR: This script supports Ubuntu only. Detected: ${ID}"
  exit 1
fi

case "$(uname -m)" in
  x86_64)
    ARCH="amd64"
    AWS_ARCH="x86_64"
    GITLEAKS_ASSET_REGEX='linux_x64\.tar\.gz$'
    ;;
  aarch64|arm64)
    ARCH="arm64"
    AWS_ARCH="aarch64"
    GITLEAKS_ASSET_REGEX='linux_arm64\.tar\.gz$'
    ;;
  *)
    echo "ERROR: Unsupported CPU architecture: $(uname -m)"
    exit 1
    ;;
esac

log "Preparing Ubuntu ${VERSION_ID} (${ARCH}) for the DevSecOps project"

sudo -v

# Keep sudo alive during the installation.
while true; do
  sudo -n true
  sleep 50
  kill -0 "$$" 2>/dev/null || exit
done &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# Base OS packages
# ------------------------------------------------------------------------------

log "Updating Ubuntu and installing base packages"

sudo apt-get update
sudo apt-get -y upgrade

sudo apt-get install -y \
  apt-transport-https \
  bash-completion \
  ca-certificates \
  coreutils \
  curl \
  dnsutils \
  fail2ban \
  file \
  git \
  gnupg \
  jq \
  less \
  lsb-release \
  make \
  netcat-openbsd \
  openssh-client \
  pipx \
  python3 \
  python3-pip \
  rsync \
  shellcheck \
  software-properties-common \
  tar \
  tmux \
  tree \
  ufw \
  unattended-upgrades \
  unzip \
  vim \
  wget \
  zip

# ------------------------------------------------------------------------------
# Basic host security
# ------------------------------------------------------------------------------

log "Applying safe baseline host hardening"

sudo systemctl enable --now fail2ban
sudo systemctl enable --now unattended-upgrades

# Keep SSH reachable before enabling UFW.
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable

# Safer default permissions for newly-created files.
if ! grep -q '^umask 027$' "${HOME}/.profile" 2>/dev/null; then
  echo 'umask 027' >> "${HOME}/.profile"
fi

# ------------------------------------------------------------------------------
# Docker Engine
# ------------------------------------------------------------------------------

log "Installing Docker Engine from Docker's official APT repository"

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

cat <<EOF | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker

# Prevent unbounded local Docker JSON logs on the admin VM.
if [[ ! -f /etc/docker/daemon.json ]]; then
  cat <<'EOF' | sudo tee /etc/docker/daemon.json >/dev/null
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  sudo systemctl restart docker
else
  warn "/etc/docker/daemon.json already exists; leaving it unchanged."
fi

if [[ "${ADD_USER_TO_DOCKER_GROUP}" == "true" ]]; then
  sudo usermod -aG docker "${TARGET_USER}"
  warn "Added ${TARGET_USER} to the docker group. Docker group membership is effectively root-equivalent."
  warn "Log out and back in before using Docker without sudo."
else
  ok "Docker installed. Use 'sudo docker ...' by default."
  warn "For convenience only, rerun with ADD_USER_TO_DOCKER_GROUP=true to enable rootless-looking Docker CLI access."
fi

# ------------------------------------------------------------------------------
# Google Cloud CLI + kubectl + GKE auth plugin
# ------------------------------------------------------------------------------

log "Installing Google Cloud CLI, kubectl and GKE auth plugin"

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

sudo apt-get update
sudo apt-get install -y \
  google-cloud-cli \
  kubectl \
  google-cloud-sdk-gke-gcloud-auth-plugin

# ------------------------------------------------------------------------------
# HashiCorp repository: Terraform + Vault CLI
# ------------------------------------------------------------------------------

log "Installing Terraform and Vault CLI from HashiCorp's official repository"

curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

HASHICORP_CODENAME="$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || true)"
if [[ -z "${HASHICORP_CODENAME}" ]]; then
  HASHICORP_CODENAME="$(lsb_release -cs)"
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${HASHICORP_CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

sudo apt-get update
sudo apt-get install -y terraform vault

# We install Vault CLI only here. Vault SERVER will be deployed later on GKE.
sudo systemctl disable vault.service >/dev/null 2>&1 || true
sudo systemctl stop vault.service >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# Helm
# ------------------------------------------------------------------------------

log "Installing Helm"

HELM_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
HELM_KEY_TMP="$(mktemp)"

curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
  -o "${HELM_KEY_TMP}"

ACTUAL_HELM_KEY_ID="$(
  gpg --show-keys --with-colons "${HELM_KEY_TMP}" \
    | awk -F: '$1 == "fpr" {print $10}' \
    | head -n 1
)"

if [[ "${ACTUAL_HELM_KEY_ID}" != "${HELM_APT_KEY_ID}" ]]; then
  echo "ERROR: Unexpected Helm repository key fingerprint."
  echo "Expected: ${HELM_APT_KEY_ID}"
  echo "Actual:   ${ACTUAL_HELM_KEY_ID}"
  rm -f "${HELM_KEY_TMP}"
  exit 1
fi

gpg --dearmor < "${HELM_KEY_TMP}" \
  | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
rm -f "${HELM_KEY_TMP}"

echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null

sudo apt-get update
sudo apt-get install -y helm

# ------------------------------------------------------------------------------
# AWS CLI v2
# ------------------------------------------------------------------------------

log "Installing AWS CLI v2"

TMP_DIR="$(mktemp -d)"
pushd "${TMP_DIR}" >/dev/null

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
  -o awscliv2.zip
unzip -q awscliv2.zip

if command -v aws >/dev/null 2>&1; then
  sudo ./aws/install --update
else
  sudo ./aws/install
fi

popd >/dev/null
rm -rf "${TMP_DIR}"

# ------------------------------------------------------------------------------
# Trivy
# ------------------------------------------------------------------------------

log "Installing Trivy"

curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/trivy.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null

sudo apt-get update
sudo apt-get install -y trivy

# ------------------------------------------------------------------------------
# yq
# ------------------------------------------------------------------------------

log "Installing yq"

sudo curl -fsSL \
  "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" \
  -o /usr/local/bin/yq
sudo chmod 0755 /usr/local/bin/yq

# ------------------------------------------------------------------------------
# Argo CD CLI
# ------------------------------------------------------------------------------

log "Installing Argo CD CLI"

sudo curl -fsSL \
  "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${ARCH}" \
  -o /usr/local/bin/argocd
sudo chmod 0555 /usr/local/bin/argocd

# ------------------------------------------------------------------------------
# Cosign
# ------------------------------------------------------------------------------

log "Installing Cosign"

sudo curl -fsSL \
  "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-${ARCH}" \
  -o /usr/local/bin/cosign
sudo chmod 0755 /usr/local/bin/cosign

# ------------------------------------------------------------------------------
# Gitleaks - resolve the correct latest release asset dynamically
# ------------------------------------------------------------------------------

log "Installing Gitleaks"

GITLEAKS_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest)"
GITLEAKS_URL="$(
  jq -r --arg re "${GITLEAKS_ASSET_REGEX}" \
    '.assets[] | select(.name | test($re)) | .browser_download_url' \
    <<< "${GITLEAKS_RELEASE_JSON}" \
    | head -n 1
)"

if [[ -z "${GITLEAKS_URL}" || "${GITLEAKS_URL}" == "null" ]]; then
  echo "ERROR: Could not locate a Gitleaks release asset for this architecture."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
curl -fsSL "${GITLEAKS_URL}" -o "${TMP_DIR}/gitleaks.tar.gz"
tar -xzf "${TMP_DIR}/gitleaks.tar.gz" -C "${TMP_DIR}"
sudo install -m 0755 "${TMP_DIR}/gitleaks" /usr/local/bin/gitleaks
rm -rf "${TMP_DIR}"

# ------------------------------------------------------------------------------
# Syft - SBOM generator
# ------------------------------------------------------------------------------

log "Installing Syft"

SYFT_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/anchore/syft/releases/latest)"
SYFT_URL="$(
  jq -r --arg re "linux_${ARCH}\\.tar\\.gz$" \
    '.assets[] | select(.name | test($re)) | .browser_download_url' \
    <<< "${SYFT_RELEASE_JSON}" \
    | head -n 1
)"

if [[ -z "${SYFT_URL}" || "${SYFT_URL}" == "null" ]]; then
  echo "ERROR: Could not locate a Syft release asset for this architecture."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
curl -fsSL "${SYFT_URL}" -o "${TMP_DIR}/syft.tar.gz"
tar -xzf "${TMP_DIR}/syft.tar.gz" -C "${TMP_DIR}"
sudo install -m 0755 "${TMP_DIR}/syft" /usr/local/bin/syft
rm -rf "${TMP_DIR}"

# ------------------------------------------------------------------------------
# Pre-commit
# ------------------------------------------------------------------------------

log "Installing pre-commit with pipx"

pipx ensurepath >/dev/null 2>&1 || true
if ! "${HOME}/.local/bin/pre-commit" --version >/dev/null 2>&1; then
  pipx install pre-commit
else
  pipx upgrade pre-commit || true
fi

# ------------------------------------------------------------------------------
# Workspace and shell helpers
# ------------------------------------------------------------------------------

log "Creating DevSecOps workspace"

mkdir -p \
  "${HOME}/devsecops/repos" \
  "${HOME}/devsecops/terraform" \
  "${HOME}/devsecops/security-reports" \
  "${HOME}/devsecops/tmp" \
  "${HOME}/.kube" \
  "${HOME}/.aws"

chmod 0700 "${HOME}/.kube" "${HOME}/.aws"

BASH_MARKER="# >>> DEVSECOPS BOOTSTRAP >>>"
if ! grep -qF "${BASH_MARKER}" "${HOME}/.bashrc"; then
  cat <<'EOF' >> "${HOME}/.bashrc"

# >>> DEVSECOPS BOOTSTRAP >>>
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

alias k='kubectl'
alias tf='terraform'
alias dc='docker compose'
alias kgp='kubectl get pods -A'
alias kctx='kubectl config current-context'

source <(kubectl completion bash 2>/dev/null)
complete -o default -F __start_kubectl k 2>/dev/null || true
# <<< DEVSECOPS BOOTSTRAP <<<
EOF
fi

# ------------------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------------------

log "Verifying installed tools"

printf '\n%-24s %s\n' "Tool" "Version"
printf '%-24s %s\n' "------------------------" "----------------------------------------"

print_version() {
  local name="$1"
  shift
  local output
  output="$("$@" 2>&1 | head -n 1)" || output="ERROR"
  printf '%-24s %s\n' "${name}" "${output}"
}

print_version "git" git --version
print_version "docker" docker --version
print_version "docker compose" docker compose version
print_version "gcloud" gcloud version
print_version "kubectl" kubectl version --client
print_version "gke auth plugin" gke-gcloud-auth-plugin --version
print_version "terraform" terraform version
print_version "vault" vault version
print_version "helm" helm version --short
print_version "aws" aws --version
print_version "trivy" trivy --version
print_version "gitleaks" gitleaks version
print_version "syft" syft version
print_version "cosign" cosign version
print_version "argocd" argocd version --client
print_version "yq" yq --version

if [[ -x "${HOME}/.local/bin/pre-commit" ]]; then
  print_version "pre-commit" "${HOME}/.local/bin/pre-commit" --version
fi

# ------------------------------------------------------------------------------
# Final instructions
# ------------------------------------------------------------------------------

cat <<'EOF'

==============================================================================
DevSecOps bootstrap VM is ready.
==============================================================================

NEXT LOGIN / SHELL:
  source ~/.bashrc

GCP:
  Preferred: use a dedicated GCE service account attached to this VM.
  For personal interactive auth:
    gcloud auth login --no-launch-browser
    gcloud auth application-default login --no-launch-browser

  Then:
    gcloud config set project <PROJECT_ID>
    gcloud config set compute/region <REGION>

GKE (after the cluster exists):
    gcloud container clusters get-credentials <CLUSTER_NAME> \
      --region <REGION> \
      --project <PROJECT_ID>

    kubectl get nodes

AWS:
  Do NOT place AWS keys in Git.
  Configure temporary/SSO credentials when possible:
    aws configure sso

  Verify:
    aws sts get-caller-identity

PROJECT:
    cd ~/devsecops

IMPORTANT:
  This VM is the admin/bootstrap workstation.
  Jenkins, Argo CD, Vault, Falco, Gatekeeper, DefectDojo, etc. will be deployed
  into GKE in the later project stages rather than being installed directly
  on this VM.

==============================================================================
EOF

ok "Bootstrap completed successfully."

