# Production CI/CD Solution với Jenkins, GitHub, Security Scanning và Kubernetes

## 1. Mục tiêu

Tài liệu này mô tả kiến trúc CI/CD thực tế cho Angular 19 + .NET 9:

- GitHub: source control
- Jenkins: CI/CD orchestration
- Jenkins Controller: điều phối, không chứa toàn bộ tool
- Ephemeral Build Agents: build/test riêng
- Semgrep Cloud: SAST
- SonarQube: code quality
- OWASP Dependency-Check: SCA
- Trivy: filesystem và container image scanning
- Docker: build image
- ECR/Container Registry: image registry
- Terraform: infrastructure as code
- Kubernetes/EKS: runtime
- Helm: deployment
- Argo CD: GitOps CD
- AWS IAM/OIDC: authentication production

---

# 2. Nguyên tắc kiến trúc

## 2.1 Không biến Jenkins Controller thành toolbox

Không nên production theo kiểu:

```text
Jenkins Controller
├── Node
├── npm
├── .NET SDK
├── Docker CLI
├── kubectl
├── Helm
├── Terraform
├── AWS CLI
├── Trivy
├── Semgrep
└── rất nhiều tool
```

Mô hình này phù hợp với lab hoặc hệ thống nhỏ.

Production nên:

```text
Jenkins Controller
        |
        +----------------------+----------------------+
        |                      |                      |
        v                      v                      v
   Build Agent          Security Agent          Deploy Agent
   Node/.NET            Semgrep/Trivy/OWASP     kubectl/Helm
```

Controller chủ yếu làm:

- Pipeline orchestration
- Schedule
- Credentials integration
- Plugin management
- Job metadata
- Build history

---

# 3. Kiến trúc production đề xuất

```text
Developer
   |
   v
GitHub
   |
   | webhook
   v
Jenkins Controller
   |
   +-------------------+-------------------+
   |                   |                   |
   v                   v                   v
Build Agent        Security Agent      Deploy Agent
   |                   |                   |
Node 22             Semgrep Cloud      kubectl
.NET 9              Trivy              Helm
npm/pnpm             OWASP              Terraform
   |                   |                   |
   +-------------------+-------------------+
                       |
                       v
                Container Registry
                    ECR/Registry
                       |
                       v
                Kubernetes / EKS
```

---

# 4. Repository strategy

Có thể bắt đầu với một repository application:

```text
company-app/
├── src/
│   ├── frontend/
│   └── backend/
├── tests/
├── Dockerfile
├── Jenkinsfile
└── README.md
```

Infrastructure nên tách:

```text
company-infrastructure/
├── terraform/
│   ├── environments/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── modules/
│       ├── vpc/
│       ├── eks/
│       ├── iam/
│       ├── rds/
│       └── redis/
└── README.md
```

Nếu dùng GitOps:

```text
company-gitops/
├── apps/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── helm/
    └── company-app/
```

---

# 5. Branch strategy

Mô hình đơn giản:

```text
feature/*
     |
     v
Pull Request
     |
     v
develop
     |
     v
staging
     |
     v
main
     |
     v
production
```

Không cho developer push trực tiếp vào `main`.

GitHub branch protection nên yêu cầu:

- Pull Request
- CI passed
- Code review
- Security checks passed
- Quality Gate passed

---

# 6. Jenkins Controller

Controller production nên tương đối mỏng:

```text
Jenkins Controller
├── Jenkins
├── Required plugins
├── Basic utilities
└── Credentials integration
```

Không nên trực tiếp chạy:

```text
npm install
dotnet build
docker build
terraform apply
kubectl apply
```

cho workload production nếu có thể dùng agent.

---

# 7. Jenkins Agent Strategy

Có thể xây các Docker image riêng.

## 7.1 Angular Agent

```dockerfile
FROM node:22-bookworm

RUN npm install -g pnpm

WORKDIR /workspace
```

Tools:

```text
Node 22
npm
pnpm
Angular CLI nếu cần
```

## 7.2 .NET Agent

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0

WORKDIR /workspace
```

Tools:

```text
.NET 9 SDK
dotnet restore
dotnet build
dotnet test
dotnet publish
```

## 7.3 Security Agent

Security agent:

```text
Semgrep CLI
Trivy
OWASP Dependency-Check
jq
curl
git
```

Ví dụ:

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        git \
        jq \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/semgrep && \
    /opt/semgrep/bin/pip install --no-cache-dir semgrep && \
    ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep
```

## 7.4 Deploy Agent

```text
deploy-agent
├── kubectl
├── helm
├── terraform
├── aws-cli
└── jq
```

---

# 8. Semgrep Cloud

Semgrep dùng cho SAST.

```text
Source Code
    |
    v
Semgrep CLI
    |
    v
Semgrep Cloud
    |
    v
Security Findings
```

Tạo Jenkins credential:

```text
Kind: Secret text
ID: semgrep-token
Secret: <Semgrep Cloud token>
```

Không commit token vào GitHub.

Pipeline:

```groovy
stage('Semgrep Cloud SAST') {
    steps {
        withCredentials([
            string(
                credentialsId: 'semgrep-token',
                variable: 'SEMGREP_APP_TOKEN'
            )
        ]) {
            sh '''
                set -e
                semgrep ci
            '''
        }
    }
}
```

---

# 9. SonarQube

SonarQube kiểm tra:

- Bugs
- Code Smells
- Reliability
- Maintainability
- Coverage
- Quality Gate

Flow:

```text
Source
  |
  v
SonarQube Scan
  |
  v
Quality Gate
  |
  +---- PASS ----> Continue
  |
  +---- FAIL ----> Stop
```

SonarQube không thay thế Semgrep.

---

# 10. OWASP Dependency-Check

OWASP kiểm tra dependency:

```text
Angular
  └── npm packages

.NET
  └── NuGet packages
```

Jenkins credential:

```text
ID: nvd-api-key
Kind: Secret text
```

Pipeline nên generate report và publish report.

---

# 11. Trivy

Nên scan ít nhất hai lớp.

## 11.1 Filesystem

```bash
trivy fs .
```

## 11.2 Container image

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  company-api:${IMAGE_TAG}
```

Security order:

```text
Docker Build
     |
     v
Trivy Image Scan
     |
     +---- FAIL ----> Stop
     |
     +---- PASS ----> Push
```

Nên scan trước push.

---

# 12. Image tagging

Không nên production chỉ dùng:

```text
latest
```

Nên dùng immutable tag:

```text
company-api:1.4.2
company-api:git-a81f92c
company-api:build-152
```

Ví dụ:

```groovy
environment {
    IMAGE_TAG = "${GIT_COMMIT.take(8)}"
}
```

Image:

```text
company/api:a81f92c3
```

Điều này giúp rollback.

---

# 13. Docker Build

```groovy
stage('Docker Build') {
    steps {
        sh '''
            docker build \
              -t ${IMAGE_NAME}:${IMAGE_TAG} .
            '''
    }
}
```

Trong production, cân nhắc build service như:

- BuildKit
- Kaniko
- Buildah
- Tekton

thay vì expose Docker socket cho mọi agent.

---

# 14. Container Registry

Production AWS:

```text
Jenkins
   |
   v
AWS ECR
   |
   v
EKS
```

Không hard-code:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

Ưu tiên:

```text
Jenkins Agent
      |
      v
IAM Role / OIDC
      |
      v
ECR
```

---

# 15. Terraform

Terraform quản lý infrastructure:

```text
VPC
Subnet
Security Group
IAM
EKS
RDS
Redis
S3
Load Balancer
```

Phân chia trách nhiệm:

```text
Terraform
   |
   +--> AWS infrastructure

Helm / Argo CD
   |
   +--> Kubernetes applications
```

Không nên để Terraform và Helm cùng quản lý một resource Kubernetes.

---

# 16. Terraform pipeline

Validate:

```bash
terraform init
terraform validate
terraform plan
```

Production:

```text
terraform plan
       |
       v
Review
       |
       v
Manual Approval
       |
       v
terraform apply
```

Tránh `terraform apply -auto-approve` cho production nếu không có governance phù hợp.

---

# 17. Kubernetes Deployment

Dùng immutable image tag:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: company-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: company-api
  template:
    metadata:
      labels:
        app: company-api
    spec:
      containers:
        - name: company-api
          image: company/api:a81f92c3
          ports:
            - containerPort: 8080
```

---

# 18. Helm

Project lớn nên dùng Helm:

```text
helm/
└── company-api/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-staging.yaml
    ├── values-prod.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        └── configmap.yaml
```

Deploy:

```bash
helm upgrade --install \
  company-api \
  ./helm/company-api \
  -f ./helm/company-api/values-prod.yaml \
  --set image.tag=${IMAGE_TAG}
```

---

# 19. CI/CD Pipeline hoàn chỉnh

```text
GitHub
   |
   v
Checkout
   |
   v
Unit Test / Build
   |
   v
Semgrep Cloud
   |
   v
SonarQube
   |
   v
Quality Gate
   |
   v
OWASP Dependency Check
   |
   v
Trivy FS
   |
   v
Docker Build
   |
   v
Trivy Image
   |
   +---- FAIL ---> Stop
   |
   v
ECR Push
   |
   v
Kubernetes / Argo CD
   |
   v
Smoke Test
```

---

# 20. Jenkinsfile production skeleton

```groovy
pipeline {

    agent none

    environment {
        IMAGE_NAME = 'company-api'
        IMAGE_TAG = "${GIT_COMMIT.take(8)}"
    }

    stages {

        stage('Checkout') {
            agent { label 'general' }
            steps { checkout scm }
        }

        stage('Build & Test') {
            agent { label 'dotnet' }
            steps {
                sh '''
                    dotnet restore
                    dotnet build --no-restore
                    dotnet test --no-build
                '''
            }
        }

        stage('Semgrep Cloud') {
            agent { label 'security' }
            steps {
                withCredentials([
                    string(
                        credentialsId: 'semgrep-token',
                        variable: 'SEMGREP_APP_TOKEN'
                    )
                ]) {
                    sh '''
                        set -e
                        semgrep ci
                    '''
                }
            }
        }

        stage('SonarQube') {
            agent { label 'dotnet' }
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh '''
                        # SonarScanner command depends on project type.
                        # Keep scanner setup in the appropriate build agent.
                        dotnet build
                    '''
                }
            }
        }

        stage('Quality Gate') {
            agent none
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('OWASP') {
            agent { label 'security' }
            steps {
                dependencyCheck(
                    odcInstallation: 'owasp-dp-check',
                    additionalArguments: '''
                        --scan .
                        --format XML
                        --out .
                        --disableKnownExploited
                    '''
                )
                dependencyCheckPublisher(
                    pattern: '**/dependency-check-report.xml'
                )
            }
        }

        stage('Trivy FS') {
            agent { label 'security' }
            steps {
                sh '''
                    trivy fs . \
                      --severity HIGH,CRITICAL \
                      --exit-code 1
                '''
            }
        }

        stage('Docker Build') {
            agent { label 'docker' }
            steps {
                sh '''
                    docker build \
                      -t ${IMAGE_NAME}:${IMAGE_TAG} .
                '''
            }
        }

        stage('Trivy Image') {
            agent { label 'docker' }
            steps {
                sh '''
                    trivy image \
                      --severity HIGH,CRITICAL \
                      --exit-code 1 \
                      ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Push Image') {
            agent { label 'docker' }
            steps {
                sh '''
                    docker push \
                      ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Deploy') {
            agent { label 'deploy' }
            steps {
                sh '''
                    helm upgrade --install \
                      company-api \
                      ./helm/company-api \
                      --set image.tag=${IMAGE_TAG}
                '''
            }
        }
    }
}
```

Đây là skeleton; command SonarQube cụ thể cần thay theo Angular/.NET project và scanner version thực tế.

---

# 21. Jenkins Agent trên Kubernetes

Production có thể dùng Kubernetes plugin để tạo agent pod động:

```text
Jenkins Controller
       |
       v
Kubernetes Plugin
       |
       v
Ephemeral Pod
├── jnlp
├── build container
└── security container
```

Build xong pod bị xóa.

Ưu điểm:

- Isolation
- Không giữ state
- Scale tốt
- Không xung đột tool version
- Chạy parallel
- Dễ nâng version agent

---

# 22. Docker Socket Security

Lab:

```text
Jenkins
  |
  +-- /var/run/docker.sock
```

rất tiện.

Production cần cẩn thận vì Docker socket có quyền rất cao.

Nếu cần build image, cân nhắc:

```text
BuildKit
Kaniko
Buildah
Tekton
Cloud Native Buildpacks
```

---

# 23. Kubernetes Authentication

Lab có thể dùng:

```text
Jenkins
  |
  +--> kubeconfig
  |
  v
FloCI K3s
```

Production EKS nên ưu tiên:

```text
Jenkins Agent
      |
      v
AWS IAM / OIDC
      |
      v
EKS
```

Không dùng một kubeconfig `cluster-admin` cho toàn bộ pipeline.

Tách quyền:

```text
deploy-dev
deploy-staging
deploy-prod
```

---

# 24. GitOps với Argo CD

Khi hệ thống lớn, nên tách CI và CD.

CI:

```text
GitHub
  |
  v
Jenkins
  |
  +--> Test
  +--> Semgrep
  +--> SonarQube
  +--> OWASP
  +--> Trivy
  +--> Docker Build
  +--> Push ECR
```

Jenkins cập nhật GitOps repository.

CD:

```text
GitOps Repository
       |
       v
    Argo CD
       |
       v
      EKS
```

---

# 25. Environment Strategy

Có:

```text
dev
staging
prod
```

Mỗi environment nên có credential và secrets riêng.

Không dùng production credential cho dev.

---

# 26. Secrets

Không lưu secrets trong Git.

Không lưu:

```text
DB_PASSWORD
JWT_SECRET
AWS_SECRET
API_KEY
SEMGREP_APP_TOKEN
```

Có thể dùng:

```text
AWS Secrets Manager
AWS Parameter Store
HashiCorp Vault
External Secrets Operator
```

Production EKS:

```text
EKS
 |
 v
External Secrets Operator
 |
 v
AWS Secrets Manager
```

---

# 27. Observability

```text
Application
   |
   +--> Logs
   +--> Metrics
   +--> Traces
```

Stack:

```text
OpenTelemetry
       |
       +--> Prometheus
       +--> Loki
       +--> Jaeger
              |
              v
           Grafana
```

.NET 9 có thể dùng OpenTelemetry cho metrics, traces và logs.

---

# 28. Deployment Verification

Sau deploy:

```bash
kubectl rollout status deployment/company-api
kubectl get pods
kubectl get svc
kubectl get ingress
```

Smoke test:

```bash
curl https://api.company.com/health
```

Nếu fail thì rollback.

---

# 29. Rollback

Immutable image:

```text
company-api:a81f92c3
company-api:b91f231a
```

Kubernetes:

```bash
kubectl rollout undo deployment/company-api
```

Helm:

```bash
helm rollback company-api 12
```

---

# 30. Security Gates

Production nên có policy:

```text
Semgrep
  HIGH/CRITICAL
      |
      +--> FAIL

SonarQube
  Quality Gate
      |
      +--> FAIL

OWASP
  unacceptable vulnerability
      |
      +--> FAIL

Trivy FS
  HIGH/CRITICAL
      |
      +--> FAIL

Trivy Image
  HIGH/CRITICAL
      |
      +--> FAIL
```

Không chỉ scan và lưu report rồi vẫn deploy.

---

# 31. Promotion Model

Không build lại image ở mỗi environment.

Build một lần:

```text
Git commit
   |
   v
company-api:a81f92c3
```

Promote:

```text
DEV
 |
 v
STAGING
 |
 v
PRODUCTION
```

Cùng một immutable image được test rồi chạy production.

---

# 32. Local Lab hiện tại

| Production | Local Lab |
|---|---|
| GitHub | GitHub |
| Jenkins | Jenkins Docker |
| ECR | Docker Hub |
| EKS | FloCI K3s |
| AWS | FloCI / AWS mock |
| Terraform | Terraform |
| Semgrep Cloud | Semgrep Cloud |
| SonarQube | SonarQube |
| Trivy | Trivy |
| Argo CD | Có thể cài local |

Kiến trúc local:

```text
Windows
 |
 +------------------------------------------------+
 | Docker Desktop                                 |
 |                                                |
 | Jenkins                                        |
 |   |                                            |
 |   +--> Semgrep Cloud                           |
 |   +--> SonarQube                               |
 |   +--> Trivy                                   |
 |   +--> Docker                                  |
 |   +--> kubectl                                 |
 |                                                |
 | FloCI                                           |
 |   |                                            |
 |   +--> floci-eks-acman-dev                     |
 |            |                                   |
 |            +--> K3s                            |
 |                 |                              |
 |                 +--> Applications              |
 +------------------------------------------------+
```

---

# 33. Custom Jenkins Image hiện tại

Lab hiện tại:

```text
jenkins-custom
├── Jenkins
├── Docker CLI
├── kubectl
├── Trivy
└── Semgrep
```

là hợp lý.

Không nhất thiết phải nhét Node, .NET, Terraform, AWS CLI, Helm vào controller.

Khi cần production-like, hãy tách thành agents.

---

# 34. Khi nào chuyển sang Ephemeral Agents?

Nên chuyển khi:

- Nhiều project
- Nhiều team
- Build song song
- Tool version khác nhau
- Cần isolation
- Cần autoscaling
- Cần security boundary

Ví dụ:

```text
Project A -> Node 22
Project B -> Node 24
Project C -> .NET 9
Project D -> .NET 8
```

Không nên cài tất cả vào một Jenkins image.

---

# 35. Lộ trình triển khai cho lab

## Phase 1 — Local CI/CD

```text
GitHub
  ↓
Jenkins
  ↓
Semgrep Cloud
  ↓
SonarQube
  ↓
OWASP
  ↓
Trivy
  ↓
Docker Build
  ↓
Docker Push
  ↓
FloCI K3s
```

Mục tiêu: pipeline chạy end-to-end.

## Phase 2 — Agent Separation

```text
Jenkins Controller
       |
       +--> Angular Agent
       +--> .NET Agent
       +--> Security Agent
       +--> Deploy Agent
```

## Phase 3 — Terraform

Terraform quản lý:

```text
VPC
EKS
IAM
ECR
RDS
Redis
```

## Phase 4 — EKS

Chuyển FloCI K3s sang AWS EKS.

## Phase 5 — GitOps

Thêm Argo CD:

```text
Jenkins
   |
   v
ECR
   |
   v
GitOps Repository
   |
   v
Argo CD
   |
   v
EKS
```

## Phase 6 — Production Security

Bổ sung:

```text
IAM/OIDC
Secrets Manager
External Secrets
Network Policies
Pod Security
Image Signing
SBOM
Admission Controller
Runtime Security
```

---

# 36. Solution cuối cùng khuyến nghị

```text
                         Developer
                             |
                             v
                          GitHub
                             |
                             v
                    +----------------+
                    | Jenkins        |
                    | Controller     |
                    +-------+--------+
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
          Build         Security        Deploy
          Agent           Agent          Agent
             |              |              |
       Node/.NET       Semgrep Cloud    Helm
       npm/pnpm        Trivy            kubectl
                      OWASP             Terraform
             |              |              |
             +--------------+--------------+
                            |
                            v
                           ECR
                            |
                            v
                    GitOps Repository
                            |
                            v
                         Argo CD
                            |
                            v
                           EKS
                            |
          +-----------------+-----------------+
          |                 |                 |
          v                 v                 v
       Angular            .NET API         Workers
                            |
                            v
                     Observability
                            |
                 +----------+----------+
                 |          |          |
                 v          v          v
              Grafana    Loki      Prometheus
                                      |
                                      v
                                    Jaeger
```

---

# 37. Kết luận

## Lab

Dùng custom Jenkins image:

```text
Docker CLI
kubectl
Trivy
Semgrep
```

là hợp lý.

## Production

Không gom tất cả tool vào Controller.

Nên:

```text
Jenkins Controller
        |
        v
Ephemeral Agents
        |
        +--> Build
        +--> Security
        +--> Deploy
```

Kiến trúc mục tiêu:

```text
Jenkins = CI orchestration
ECR = Artifact Registry
Argo CD = CD
EKS = Runtime
Terraform = Infrastructure
Semgrep = SAST
SonarQube = Code Quality
Trivy = Vulnerability/Image
AWS IAM/OIDC = Authentication
Secrets Manager = Secrets
OpenTelemetry/Grafana = Observability
```

Đây là hướng nên phát triển từ lab hiện tại sang production thay vì biến `jenkins-custom` thành một image chứa toàn bộ ecosystem.
