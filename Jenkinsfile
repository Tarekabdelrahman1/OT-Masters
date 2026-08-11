pipeline {
    agent any

    options {
        // Prevent overlapping runs from racing on the same ECR tag/GitOps commit.
        disableConcurrentBuilds()
        // Don't let a hung scan or registry call block the agent forever.
        timeout(time: 45, unit: 'MINUTES')
        timestamps()
        // Keep a bounded build history instead of unbounded artifact growth.
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        // ---- Application / naming ----
        APP_NAME       = 'fitgear-backend'
        ENVIRONMENT    = 'staging'

        // ---- AWS / ECR ----
        AWS_REGION     = 'us-east-1'
        AWS_ACCOUNT_ID = '123456789012'               // Replace with the real account ID
        ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPOSITORY = 'fitgear/backend'
        IMAGE_TAG      = "${GIT_COMMIT.take(7)}"       // Immutable, traceable tag — never "latest"
        IMAGE_URI      = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

        // ---- SonarQube ----
        SONAR_PROJECT_KEY = 'fitgear-backend'
        SONAR_HOST_URL    = 'https://sonarqube.internal.fitgear.io'

        // ---- GitOps ----
        GITOPS_REPO_URL = 'git@github.com:OmarHesham249/fitgear-gitops.git'
        GITOPS_BRANCH   = 'main'
        GITOPS_APP_PATH = "apps/${APP_NAME}/overlays/${ENVIRONMENT}"

        // ---- DefectDojo (placeholder integration target) ----
        DEFECTDOJO_URL = 'https://defectdojo.internal.fitgear.io'

        // ---- Local scan output paths ----
        TRIVY_FS_REPORT    = 'trivy-fs-report.json'
        TRIVY_IMAGE_REPORT = 'trivy-image-report.json'
        GITLEAKS_REPORT    = 'gitleaks-report.json'
        SBOM_REPORT        = "sbom-${IMAGE_TAG}.spdx.json"
    }

    stages {

        // ---------------------------------------------------------------
        // 1. CHECKOUT — pull the exact commit that triggered this build.
        // ---------------------------------------------------------------
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    echo "Building ${APP_NAME} @ commit ${GIT_COMMIT} -> tag ${IMAGE_TAG}"
                }
            }
        }

        // ---------------------------------------------------------------
        // 2. SECRET SCANNING — fail fast before any code ever leaves the
        //    checkout. Catching a hardcoded secret here is the cheapest
        //    place to catch it (pre-build, pre-registry, pre-Git-history-push).
        // ---------------------------------------------------------------
        stage('Secret Scanning — Gitleaks') {
            steps {
                sh """
                    gitleaks detect \
                        --source . \
                        --report-format json \
                        --report-path ${GITLEAKS_REPORT} \
                        --exit-code 1 \
                        --no-git=false
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: "${GITLEAKS_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: Gitleaks detected hardcoded secrets. Pipeline halted.'
                }
            }
        }

        // ---------------------------------------------------------------
        // 3. SAST — SonarQube static analysis for bugs, code smells and
        //    vulnerable patterns. Quality Gate result is polled and enforced.
        // ---------------------------------------------------------------
        stage('SAST — SonarQube') {
            steps {
                withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                    withSonarQubeEnv('sonarqube-server') {
                        sh """
                            sonar-scanner \
                                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                                -Dsonar.sources=. \
                                -Dsonar.host.url=${SONAR_HOST_URL} \
                                -Dsonar.login=${SONAR_TOKEN}
                        """
                    }
                }
            }
        }

        stage('SAST — Quality Gate') {
            steps {
                // Blocks until SonarQube webhook posts the analysis result.
                // ABORTED status intentionally fails the build.
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

        // ---------------------------------------------------------------
        // 4. SCA / FILESYSTEM SCAN — Trivy scans source + dependency
        //    manifests (package-lock.json, etc.) for known CVEs before
        //    we ever spend time building a container image around them.
        // ---------------------------------------------------------------
        stage('SCA — Trivy Filesystem Scan') {
            steps {
                sh """
                    trivy fs \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --format json \
                        --output ${TRIVY_FS_REPORT} \
                        --ignore-unfixed \
                        .
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: "${TRIVY_FS_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: Trivy found HIGH/CRITICAL CVEs in filesystem/dependencies.'
                }
            }
        }

        // ---------------------------------------------------------------
        // 5. DOCKER BUILD — image tagged strictly with the Git commit SHA.
        //    Immutable, traceable, reproducible. "latest" is never used
        //    anywhere in this pipeline.
        // ---------------------------------------------------------------
        stage('Docker Build') {
            steps {
                sh """
                    docker build \
                        --pull \
                        --label org.opencontainers.image.revision=${GIT_COMMIT} \
                        --label org.opencontainers.image.source=${GIT_URL} \
                        -t ${IMAGE_URI} \
                        -f backend/Dockerfile \
                        backend
                """
            }
        }

        // ---------------------------------------------------------------
        // 6. CONTAINER IMAGE SCAN — Trivy scans the actual built image
        //    (OS packages + app layer). This is the last gate before the
        //    image is allowed anywhere near a registry.
        // ---------------------------------------------------------------
        stage('Container Image Scan — Trivy') {
            steps {
                sh """
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --format json \
                        --output ${TRIVY_IMAGE_REPORT} \
                        --ignore-unfixed \
                        ${IMAGE_URI}
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: "${TRIVY_IMAGE_REPORT}", allowEmptyArchive: true
                }
                failure {
                    echo 'GATE FAILED: HIGH/CRITICAL CVEs found in the built container image.'
                }
            }
        }

        // ---------------------------------------------------------------
        // 7. SBOM GENERATION — SPDX-JSON bill of materials, archived as a
        //    build artifact for audit/compliance and downstream vuln
        //    re-scanning without needing to pull the image again.
        // ---------------------------------------------------------------
        stage('SBOM Generation') {
            steps {
                sh """
                    trivy image \
                        --format spdx-json \
                        --output ${SBOM_REPORT} \
                        ${IMAGE_URI}
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: "${SBOM_REPORT}", allowEmptyArchive: true
                }
            }
        }

        // ---------------------------------------------------------------
        // 8. PUSH TO AWS ECR — short-lived credentials only. Prefer an
        //    IAM role attached to the Jenkins agent/instance profile; the
        //    withCredentials block below is the fallback for agents that
        //    authenticate via an IAM user instead of an instance role.
        // ---------------------------------------------------------------
        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-ecr-push'
                ]]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} \
                            | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        docker push ${IMAGE_URI}
                    """
                }
            }
        }

        // ---------------------------------------------------------------
        // 9. IMAGE SIGNING — Cosign signs the pushed image by digest,
        //    establishing provenance. Kyverno (admission control on GKE)
        //    can later enforce "only signed images may run."
        // ---------------------------------------------------------------
        stage('Image Signing — Cosign') {
            steps {
                withCredentials([
                    file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY_FILE'),
                    string(credentialsId: 'cosign-key-password', variable: 'COSIGN_PASSWORD')
                ]) {
                    sh """
                        DIGEST=\$(docker inspect --format='{{index .RepoDigests 0}}' ${IMAGE_URI} | cut -d'@' -f2)

                        cosign sign \
                            --key \${COSIGN_KEY_FILE} \
                            --yes \
                            ${ECR_REGISTRY}/${ECR_REPOSITORY}@\${DIGEST}
                    """
                }
            }
        }

        // ---------------------------------------------------------------
        // 10. UPDATE GITOPS REPO — Jenkins' only write access to the
        //     deployment side of the world. It updates the staging
        //     overlay's image reference and pushes; Argo CD detects the
        //     commit and reconciles GKE. Jenkins never touches the cluster.
        // ---------------------------------------------------------------
        stage('Update GitOps Repo') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'gitops-repo-deploy-key', keyFileVariable: 'GITOPS_SSH_KEY')]) {
                    sh """
                        export GIT_SSH_COMMAND="ssh -i \${GITOPS_SSH_KEY} -o StrictHostKeyChecking=no"

                        rm -rf gitops-repo
                        git clone --branch ${GITOPS_BRANCH} --depth 1 ${GITOPS_REPO_URL} gitops-repo
                        cd gitops-repo/${GITOPS_APP_PATH}

                        # kustomize edit rewrites the image tag in-place in kustomization.yaml.
                        # A plain `sed` fallback is shown commented below if kustomize isn't available.
                        kustomize edit set image ${ECR_REGISTRY}/${ECR_REPOSITORY}=${IMAGE_URI}
                        # sed -i "s|image: .*fitgear/backend.*|image: ${IMAGE_URI}|" deployment-patch.yaml

                        git config user.email "jenkins-ci@fitgear.io"
                        git config user.name "jenkins-ci"
                        git add .
                        git commit -m "ci: deploy ${APP_NAME} ${IMAGE_TAG} to ${ENVIRONMENT}" \
                                    -m "Triggered by build ${BUILD_NUMBER}, commit ${GIT_COMMIT}"
                        git push origin ${GITOPS_BRANCH}
                    """
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // POST — always runs regardless of pipeline outcome.
    // ---------------------------------------------------------------
    post {
        always {
            echo "Uploading security reports to DefectDojo at ${DEFECTDOJO_URL} (placeholder — wire up defectdojo-import CLI or REST API call here)"
            // Example (fill in real engagement/product IDs and credentials before enabling):
            // withCredentials([string(credentialsId: 'defectdojo-api-key', variable: 'DD_API_KEY')]) {
            //     sh """
            //         defectdojo-import \
            //             --url ${DEFECTDOJO_URL} \
            //             --api-key \${DD_API_KEY} \
            //             --scan-type "Trivy Scan" --file ${TRIVY_IMAGE_REPORT} \
            //             --scan-type "Gitleaks Scan" --file ${GITLEAKS_REPORT}
            //     """
            // }

            cleanWs(
                cleanWhenNotBuilt: true,
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }
        success {
            echo "Pipeline succeeded: ${IMAGE_URI} pushed, signed, and GitOps repo updated for ${ENVIRONMENT}."
        }
        failure {
            echo "Pipeline FAILED — one or more security gates or build stages blocked the release. No GitOps commit was made."
        }
    }
}
