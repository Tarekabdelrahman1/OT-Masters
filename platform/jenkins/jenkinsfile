pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        booleanParam(
            name: 'RUN_HOST_SECURITY_AUDIT',
            defaultValue: false,
            description: 'Run Lynis + Docker Bench on a dedicated Jenkins agent labelled docker-security-host.'
        )
    }

    environment {
        APP_NAME       = 'fitgear-backend'
        ENVIRONMENT    = 'staging'

        AWS_REGION     = 'eu-central-1'
        AWS_ACCOUNT_ID = '365811604437'
        ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPOSITORY = 'devsecops-webapp'

        GIT_SHA                = ''
        GIT_SOURCE_URL         = ''
        IMAGE_TAG              = ''
        IMAGE_URI              = ''
        RUNTIME_TEST_CONTAINER = ''

        SONAR_PROJECT_KEY = 'fitgear-backend'
        SONAR_HOST_URL    = 'https://sonarqube.internal.fitgear.io'

        GITOPS_REPO_URL = 'git@github.com:OmarHesham249/fitgear-gitops.git'
        GITOPS_BRANCH   = 'main'
        GITOPS_APP_PATH = "apps/${APP_NAME}/overlays/${ENVIRONMENT}"

        DEFECTDOJO_URL = 'https://defectdojo.internal.fitgear.io'

        TRIVY_FS_REPORT      = 'trivy-fs-report.json'
        TRIVY_IMAGE_REPORT   = 'trivy-image-report.json'
        GITLEAKS_REPORT      = 'gitleaks-report.json'
        SBOM_REPORT          = 'sbom.spdx.json'
        INSPEC_REPORT        = 'inspec-runtime-report.json'
        LYNIS_CONSOLE_REPORT = 'lynis-audit.txt'
        LYNIS_DATA_REPORT    = 'lynis-report.dat'
        DOCKER_BENCH_REPORT  = 'docker-bench-security.txt'

        INSPEC_PROFILE = 'security/inspec/docker-runtime'

        CONTAINER_MEMORY_LIMIT = '512m'
        CONTAINER_CPU_LIMIT    = '1.0'
        CONTAINER_PIDS_LIMIT   = '256'

        DOCKER_BENCH_DIR = '/opt/docker-bench-security'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.GIT_SOURCE_URL = sh(
                        script: 'git config --get remote.origin.url',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_URI = "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"
                    env.SBOM_REPORT = "sbom-${env.IMAGE_TAG}.spdx.json"
                    env.RUNTIME_TEST_CONTAINER = "${env.APP_NAME}-security-${env.BUILD_NUMBER}"

                    echo "Building ${env.APP_NAME} @ ${env.GIT_SHA} -> ${env.IMAGE_URI}"
                }
            }
        }

        stage('Secret Scanning — Gitleaks') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

gitleaks detect \
    --source . \
    --report-format json \
    --report-path "$GITLEAKS_REPORT" \
    --exit-code 1 \
    --no-git=false
'''
            }
            post {
                always {
                    archiveArtifacts artifacts: "${GITLEAKS_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: Gitleaks detected hardcoded secrets.'
                }
            }
        }

        stage('SAST — SonarQube') {
            steps {
                withCredentials([
                    string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')
                ]) {
                    withSonarQubeEnv('sonarqube-server') {
                        sh '''#!/bin/bash
set -euo pipefail

sonar-scanner \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    -Dsonar.sources=. \
    -Dsonar.host.url="$SONAR_HOST_URL" \
    -Dsonar.login="$SONAR_TOKEN"
'''
                    }
                }
            }
        }

        stage('SAST — Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "GATE FAILED: SonarQube Quality Gate status = ${qg.status}"
                        }
                    }
                }
            }
        }

        stage('SCA — Trivy Filesystem Scan') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

trivy fs \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --format json \
    --output "$TRIVY_FS_REPORT" \
    --ignore-unfixed \
    .
'''
            }
            post {
                always {
                    archiveArtifacts artifacts: "${TRIVY_FS_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: Trivy found HIGH/CRITICAL fixable CVEs in source/dependencies.'
                }
            }
        }

        stage('Host Security Baseline — Lynis + Docker Bench') {
            when {
                expression { return params.RUN_HOST_SECURITY_AUDIT }
            }
            agent {
                label 'docker-security-host'
            }
            steps {
                sh '''#!/bin/bash
set -euo pipefail

command -v lynis >/dev/null
test -f "$DOCKER_BENCH_DIR/docker-bench-security.sh"

echo "=== Lynis host audit ==="
sudo -n lynis audit system --quick --no-colors 2>&1 | tee "$LYNIS_CONSOLE_REPORT"
sudo -n cat /var/log/lynis-report.dat > "$LYNIS_DATA_REPORT"

echo "=== Docker Bench for Security ==="
sudo -n sh "$DOCKER_BENCH_DIR/docker-bench-security.sh" \
    -b \
    -c container_images,container_runtime \
    2>&1 | tee "$DOCKER_BENCH_REPORT"
'''
            }
            post {
                always {
                    archiveArtifacts artifacts: "${LYNIS_CONSOLE_REPORT},${LYNIS_DATA_REPORT},${DOCKER_BENCH_REPORT}",
                                     allowEmptyArchive: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

docker build \
    --pull \
    --label "org.opencontainers.image.revision=$GIT_SHA" \
    --label "org.opencontainers.image.source=$GIT_SOURCE_URL" \
    -t "$IMAGE_URI" \
    -f backend/Dockerfile \
    backend
'''
            }
        }

        stage('Container Image Scan — Trivy') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

trivy image \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --format json \
    --output "$TRIVY_IMAGE_REPORT" \
    --ignore-unfixed \
    "$IMAGE_URI"
'''
            }
            post {
                always {
                    archiveArtifacts artifacts: "${TRIVY_IMAGE_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: HIGH/CRITICAL fixable CVEs found in the built image.'
                }
            }
        }

        stage('Runtime Hardening — Create Validation Container') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

docker rm -f "$RUNTIME_TEST_CONTAINER" >/dev/null 2>&1 || true

docker create \
    --name "$RUNTIME_TEST_CONTAINER" \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    --cap-drop=ALL \
    --security-opt no-new-privileges=true \
    --security-opt seccomp=builtin \
    --memory="$CONTAINER_MEMORY_LIMIT" \
    --memory-swap="$CONTAINER_MEMORY_LIMIT" \
    --cpus="$CONTAINER_CPU_LIMIT" \
    --pids-limit="$CONTAINER_PIDS_LIMIT" \
    "$IMAGE_URI"

docker inspect "$RUNTIME_TEST_CONTAINER" >/dev/null
'''
            }
        }

        stage('Compliance as Code — InSpec/Cinc') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

if command -v cinc-auditor >/dev/null 2>&1; then
    AUDITOR_BIN="$(command -v cinc-auditor)"
elif command -v inspec >/dev/null 2>&1; then
    AUDITOR_BIN="$(command -v inspec)"
else
    echo "ERROR: neither cinc-auditor nor inspec is installed."
    exit 1
fi

"$AUDITOR_BIN" check "$INSPEC_PROFILE"

CONTAINER_ID="$(docker inspect --format='{{.Id}}' "$RUNTIME_TEST_CONTAINER")"

"$AUDITOR_BIN" exec "$INSPEC_PROFILE" \
    --input container_id="$CONTAINER_ID" \
    --reporter cli json:"$INSPEC_REPORT"
'''
            }
            post {
                always {
                    archiveArtifacts artifacts: "${INSPEC_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: Docker runtime compliance controls failed.'
                }
            }
        }

        stage('SBOM Generation') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail

trivy image \
    --format spdx-json \
    --output "$SBOM_REPORT" \
    "$IMAGE_URI"
'''
            }
            post {
                always {
                    archiveArtifacts artifacts: "${SBOM_REPORT}", allowEmptyArchive: true
                }
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-ecr-push'
                ]]) {
                    sh '''#!/bin/bash
set -euo pipefail

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker push "$IMAGE_URI"
'''
                }
            }
        }

        stage('Image Signing — Cosign') {
            steps {
                withCredentials([
                    file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY_FILE'),
                    string(credentialsId: 'cosign-key-password', variable: 'COSIGN_PASSWORD')
                ]) {
                    sh '''#!/bin/bash
set -euo pipefail

DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE_URI" | cut -d'@' -f2)"

if [[ -z "$DIGEST" ]]; then
    echo "ERROR: Could not resolve pushed image digest."
    exit 1
fi

cosign sign \
    --key "$COSIGN_KEY_FILE" \
    --yes \
    "$ECR_REGISTRY/$ECR_REPOSITORY@$DIGEST"
'''
                }
            }
        }

        stage('Update GitOps Repo') {
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'gitops-repo-deploy-key',
                        keyFileVariable: 'GITOPS_SSH_KEY'
                    ),
                    file(
                        credentialsId: 'github-known-hosts',
                        variable: 'GIT_KNOWN_HOSTS'
                    )
                ]) {
                    sh '''#!/bin/bash
set -euo pipefail

export GIT_SSH_COMMAND="ssh -i $GITOPS_SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$GIT_KNOWN_HOSTS"

rm -rf gitops-repo
git clone \
    --branch "$GITOPS_BRANCH" \
    --depth 1 \
    "$GITOPS_REPO_URL" \
    gitops-repo

cd "gitops-repo/$GITOPS_APP_PATH"

kustomize edit set image "$ECR_REGISTRY/$ECR_REPOSITORY=$IMAGE_URI"

git config user.email "jenkins-ci@fitgear.io"
git config user.name "jenkins-ci"
git add .

if git diff --cached --quiet; then
    echo "GitOps manifests already reference $IMAGE_URI; nothing to commit."
else
    git commit \
        -m "ci: deploy $APP_NAME $IMAGE_TAG to $ENVIRONMENT" \
        -m "Triggered by build $BUILD_NUMBER, commit $GIT_SHA"

    git push origin "$GITOPS_BRANCH"
fi
'''
                }
            }
        }
    }

    post {
        always {
            sh '''#!/bin/bash
set +e

if [[ -n "${RUNTIME_TEST_CONTAINER:-}" ]]; then
    docker rm -f "$RUNTIME_TEST_CONTAINER" >/dev/null 2>&1 || true
fi

docker logout "$ECR_REGISTRY" >/dev/null 2>&1 || true
'''

            echo "DefectDojo integration target: ${DEFECTDOJO_URL} (still a placeholder)."

            cleanWs(
                cleanWhenNotBuilt: true,
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }

        success {
            echo "Pipeline succeeded: ${IMAGE_URI} passed security gates, was pushed, signed, and GitOps was updated for ${ENVIRONMENT}."
        }

        failure {
            echo 'Pipeline FAILED — a build/security/compliance gate blocked the release.'
        }
    }
}
