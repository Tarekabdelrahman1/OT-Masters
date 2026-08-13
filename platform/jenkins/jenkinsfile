pipeline {
    agent {
        kubernetes {
            defaultContainer 'devsecops-tools'
            yaml '''
            apiVersion: v1
            kind: Pod
            spec:
              containers:
              - name: dind
                image: docker:24.0-dind
                securityContext:
                  privileged: true
                env:
                - name: DOCKER_TLS_CERTDIR
                  value: ""

              - name: devsecops-tools
                image: omarhesham249/jenkins-devsecops-agent:latest
                command:
                - cat
                tty: true
                env:
                - name: DOCKER_HOST
                  value: tcp://localhost:2375
            '''
        }
    }

    options {
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
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
        SONAR_HOST_URL    = 'http://sonarqube.internal.fitgear.io:9000'

        GITOPS_REPO_URL = 'git@github.com:OmarHesham249/fitgear-gitops.git'
        GITOPS_BRANCH   = 'main'
        GITOPS_APP_PATH = "apps/${APP_NAME}/overlays/${ENVIRONMENT}"

        DEFECTDOJO_URL          = 'http://defectdojo.internal.fitgear.io'
        DEFECTDOJO_ENGAGEMENT_ID = '1'

        TRIVY_FS_REPORT    = 'trivy-fs-report.json'
        TRIVY_IMAGE_REPORT = 'trivy-image-report.json'
        GITLEAKS_REPORT    = 'gitleaks-report.json'
        SBOM_REPORT        = 'sbom.spdx.json'
        INSPEC_REPORT      = 'inspec-runtime-report.json'

        INSPEC_PROFILE = 'security/inspec/docker-runtime'

        CONTAINER_MEMORY_LIMIT = '512m'
        CONTAINER_CPU_LIMIT    = '1.0'
        CONTAINER_PIDS_LIMIT   = '256'
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

                    env.IMAGE_URI =
                        "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

                    env.SBOM_REPORT =
                        "sbom-${env.IMAGE_TAG}.spdx.json"

                    env.RUNTIME_TEST_CONTAINER =
                        "${env.APP_NAME}-security-${env.BUILD_NUMBER}"
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
                    archiveArtifacts
                        artifacts: "${GITLEAKS_REPORT}",
                        allowEmptyArchive: true
                }
            }
        }

        stage('SAST — SonarQube') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'sonarqube-token',
                        variable: 'SONAR_TOKEN'
                    )
                ]) {
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

        stage('SCA — Trivy Filesystem Scan') {
            steps {
                sh '''#!/bin/bash
                set -euo pipefail

                trivy fs \
                  --severity HIGH,CRITICAL \
                  --exit-code 1 \
                  --format json \
                  --output "$TRIVY_FS_REPORT" \
                  --ignore-unfixed .
                '''
            }

            post {
                always {
                    archiveArtifacts
                        artifacts: "${TRIVY_FS_REPORT}",
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
                  -f fitgear/backend/Dockerfile \
                  fitgear/backend
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
                  --ignore-unfixed "$IMAGE_URI"
                '''
            }

            post {
                always {
                    archiveArtifacts
                        artifacts: "${TRIVY_IMAGE_REPORT}",
                        allowEmptyArchive: true
                }
            }
        }

        stage('Runtime Hardening — Validation') {
            steps {
                sh '''#!/bin/bash
                set -euo pipefail

                docker rm -f "$RUNTIME_TEST_CONTAINER" \
                  >/dev/null 2>&1 || true

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

                AUDITOR_BIN="$(command -v cinc-auditor || command -v inspec)"

                "$AUDITOR_BIN" check "$INSPEC_PROFILE"

                CONTAINER_ID="$(
                    docker inspect \
                      --format='{{.Id}}' \
                      "$RUNTIME_TEST_CONTAINER"
                )"

                "$AUDITOR_BIN" exec "$INSPEC_PROFILE" \
                  --input container_id="$CONTAINER_ID" \
                  --reporter cli \
                  json:"$INSPEC_REPORT"
                '''
            }

            post {
                always {
                    archiveArtifacts
                        artifacts: "${INSPEC_REPORT}",
                        allowEmptyArchive: true
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
                    archiveArtifacts
                        artifacts: "${SBOM_REPORT}",
                        allowEmptyArchive: true
                }
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([
                    [
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'aws-jenkins-ecr-push'
                    ]
                ]) {
                    sh '''#!/bin/bash
                    set -euo pipefail

                    aws ecr get-login-password \
                      --region "$AWS_REGION" |
                    docker login \
                      --username AWS \
                      --password-stdin "$ECR_REGISTRY"

                    docker push "$IMAGE_URI"
                    '''
                }
            }
        }

        stage('Image Signing — Cosign') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'cosign-private-key',
                        variable: 'COSIGN_KEY_FILE'
                    ),
                    string(
                        credentialsId: 'cosign-key-password',
                        variable: 'COSIGN_PASSWORD'
                    )
                ]) {
                    sh '''#!/bin/bash
                    set -euo pipefail

                    cosign sign \
                      --key "$COSIGN_KEY_FILE" \
                      --yes \
                      "$IMAGE_URI"
                    '''
                }
            }
        }

        stage('Upload Reports to DefectDojo') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'defectdojo-api-key',
                        variable: 'DEFECTDOJO_API_KEY'
                    )
                ]) {
                    sh '''#!/bin/bash
                    set +e

                    if [ -f "$TRIVY_FS_REPORT" ]; then
                        curl -s \
                          -X POST \
                          "$DEFECTDOJO_URL/api/v2/import-scan/" \
                          -H "Authorization: Token $DEFECTDOJO_API_KEY" \
                          -F "scan_type=Trivy Scan" \
                          -F "file=@$TRIVY_FS_REPORT" \
                          -F "engagement=$DEFECTDOJO_ENGAGEMENT_ID"
                    fi

                    if [ -f "$GITLEAKS_REPORT" ]; then
                        curl -s \
                          -X POST \
                          "$DEFECTDOJO_URL/api/v2/import-scan/" \
                          -H "Authorization: Token $DEFECTDOJO_API_KEY" \
                          -F "scan_type=Gitleaks Scan" \
                          -F "file=@$GITLEAKS_REPORT" \
                          -F "engagement=$DEFECTDOJO_ENGAGEMENT_ID"
                    fi
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

                    export GIT_SSH_COMMAND="ssh \
                      -i $GITOPS_SSH_KEY \
                      -o IdentitiesOnly=yes \
                      -o StrictHostKeyChecking=yes \
                      -o UserKnownHostsFile=$GIT_KNOWN_HOSTS"

                    rm -rf gitops-repo

                    git clone \
                      --branch "$GITOPS_BRANCH" \
                      --depth 1 \
                      "$GITOPS_REPO_URL" \
                      gitops-repo

                    cd "gitops-repo/$GITOPS_APP_PATH"

                    kustomize edit set image \
                      "$ECR_REGISTRY/$ECR_REPOSITORY=$IMAGE_URI"

                    git config user.email "jenkins-ci@fitgear.io"
                    git config user.name "jenkins-ci"

                    git add .

                    if ! git diff --cached --quiet; then
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

            docker rm -f "$RUNTIME_TEST_CONTAINER" \
              >/dev/null 2>&1 || true

            docker logout "$ECR_REGISTRY" \
              >/dev/null 2>&1 || true
            '''
        }
    }
}