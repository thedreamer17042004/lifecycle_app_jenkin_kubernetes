# Local CI/CD Lab – Jenkins + Docker + FloCI/K3s + SonarQube + Kubernetes

## 1. Mục tiêu

Tài liệu này mô tả cách xây dựng môi trường CI/CD local trên Windows sử dụng:

* GitHub
* Jenkins chạy bằng Docker
* Docker CLI thông qua Docker Socket
* SonarQube chạy local
* Cloudflare Quick Tunnel cho SonarQube Webhook
* FloCI giả lập AWS
* K3s làm Kubernetes backend cho FloCI EKS
* Kubernetes CLI (`kubectl`)
* Jenkins deploy ứng dụng lên Kubernetes
* `kubectl port-forward` để kiểm tra ứng dụng từ Windows

Kiến trúc tổng quát:

```text
                         GitHub
                            │
                            │ git push
                            ▼
                    ┌─────────────────┐
                    │     Jenkins     │
                    │ Docker          │
                    │ Node.js         │
                    │ kubectl         │
                    │ Trivy           │
                    └────────┬────────┘
                             │
             ┌───────────────┼────────────────┐
             │               │                │
             ▼               ▼                ▼
        SonarQube          Docker          Kubernetes
        localhost:9000      Socket          K3s
             │                                │
             │ Webhook                        │
             ▼                                │
       Cloudflare Tunnel                      │
                                             │
                                      FloCI K3s container
                                      floci-eks-acman-dev
                                             │
                                             ▼
                                      Netflix Application
```

---

# 2. Các container chính

Trong lab có thể có các container:

```text
jenkins-blueocean
floci
floci-eks-acman-dev
floci-ui
floci-ecr-registry
```

Trong đó cần phân biệt rất rõ:

### `floci`

Đây là container FloCI chính được tạo từ Docker Compose.

Ví dụ:

```yaml
services:
  floci:
    image: floci/floci:latest
    container_name: floci

    ports:
      - "4566:4566"
      - "32000:32000"

    volumes:
      - ./data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock

    environment:
      FLOCI_DEFAULT_REGION: us-east-1
      FLOCI_SERVICES_EKS_ENABLED: "true"
      FLOCI_SERVICES_EKS_MOCK: "false"
      FLOCI_SERVICES_EKS_PROVIDER: k3s
```

### `floci-eks-acman-dev`

Đây là container K3s được FloCI tự động tạo khi tạo EKS.

Container này **không phải service mà mình trực tiếp quản lý trong `docker-compose.yml`**.

Ví dụ:

```text
floci
   │
   │ FloCI EKS provider
   ▼
floci-eks-acman-dev
   │
   └── K3s
        ├── Kubernetes API : 6443
        ├── NodePort
        └── Application Pods
```

Đây là điểm rất quan trọng.

Dòng:

```yaml
- "32000:32000"
```

trong service `floci` chỉ publish port của container `floci`.

Nó **không tự động publish port 32000 của container**:

```text
floci-eks-acman-dev
```

---

# 3. Jenkins chạy bằng Docker

## 3.1. Tạo Jenkins network

Tạo Docker network riêng:

```powershell
docker network create jenkins
```

Kiểm tra:

```powershell
docker network ls
```

Kết quả mong muốn:

```text
NETWORK ID     NAME
xxxxxxx       jenkins
```

---

# 4. Chạy Jenkins container

Jenkins sử dụng custom image:

```text
jenkins-custom
```

Chạy:

```powershell
docker run --name jenkins-blueocean `
  --restart=on-failure `
  --detach `
  --network jenkins `
  --volume jenkins-data:/var/jenkins_home `
  --volume /var/run/docker.sock:/var/run/docker.sock `
  --publish 8080:8080 `
  --publish 50000:50000 `
  jenkins-custom
```

Các thành phần:

```text
--name jenkins-blueocean
```

Tên container Jenkins.

```text
--restart=on-failure
```

Nếu Jenkins bị lỗi thì Docker tự restart container.

```text
--network jenkins
```

Đưa Jenkins vào Docker network `jenkins`.

```text
--volume jenkins-data:/var/jenkins_home
```

Lưu dữ liệu Jenkins ra Docker named volume.

```text
--volume /var/run/docker.sock:/var/run/docker.sock
```

Cho phép Jenkins sử dụng Docker daemon của Docker Desktop.

```text
--publish 8080:8080
```

Jenkins Web UI:

```text
http://localhost:8080
```

```text
--publish 50000:50000
```

Jenkins inbound agent port.

---

# 5. Cho Jenkins sử dụng Docker CLI

Jenkins container có Docker CLI nhưng cần truy cập Docker daemon thông qua:

```text
/var/run/docker.sock
```

Kiểm tra:

```powershell
docker exec jenkins-blueocean docker version
```

Nếu gặp lỗi permission:

```text
permission denied while trying to connect to the Docker daemon socket
```

có thể dùng cách đơn giản cho local lab:

```powershell
docker exec -u root -it jenkins-blueocean chmod 666 /var/run/docker.sock
```

Sau đó kiểm tra:

```powershell
docker exec jenkins-blueocean docker ps
```

Nếu thành công sẽ thấy danh sách Docker containers.

## Lưu ý security

`chmod 666 /var/run/docker.sock` chỉ nên dùng cho **local learning/lab**.

Docker socket gần như tương đương quyền rất cao trên Docker host.

Trong production nên dùng:

* Docker-in-Docker phù hợp
* ephemeral build agents
* Kubernetes agents
* rootless/containerized builders
* hoặc các cơ chế build chuyên dụng

Không nên mở Docker socket quyền `666` trên production host.

---

# 6. Kiểm tra Jenkins có nhìn thấy Docker không

Chạy:

```powershell
docker exec jenkins-blueocean docker ps
```

Kiểm tra Docker CLI:

```powershell
docker exec jenkins-blueocean docker --version
```

Kiểm tra:

```powershell
docker exec jenkins-blueocean docker info
```

Nếu cả ba hoạt động thì Jenkins đã kết nối được Docker daemon.

---

# 7. Jenkins kết nối Kubernetes K3s

FloCI tạo Kubernetes/K3s container:

```text
floci-eks-acman-dev
```

K3s config nằm trong:

```text
/etc/rancher/k3s/k3s.yaml
```

Copy kubeconfig ra Windows:

```powershell
docker cp floci-eks-acman-dev:/etc/rancher/k3s/k3s.yaml .\k3s-kubeconfig.yaml
```

---

# 8. Quan trọng: thay đổi Kubernetes API Server hostname

Kubeconfig mặc định của K3s thường có:

```yaml
server: https://127.0.0.1:6443
```

Điều này chỉ đúng khi chạy `kubectl` **bên trong chính container K3s**.

Jenkins lại chạy trong container khác.

Vì vậy không được dùng:

```yaml
server: https://127.0.0.1:6443
```

vì:

```text
Jenkins container
     │
     └── 127.0.0.1
          ↓
       Jenkins
```

chứ không phải:

```text
floci-eks-acman-dev
```

---

# 9. Cho Jenkins và K3s cùng Docker network

Kết nối K3s container vào network `jenkins`:

```powershell
docker network connect jenkins floci-eks-acman-dev
```

Kiểm tra:

```powershell
docker network inspect jenkins
```

Phải thấy cả:

```text
jenkins-blueocean
floci-eks-acman-dev
```

Ví dụ:

```text
jenkins
├── jenkins-blueocean
└── floci-eks-acman-dev
```

Khi cùng Docker network, Jenkins có thể resolve:

```text
floci-eks-acman-dev
```

---

# 10. Kubeconfig sử dụng Docker hostname

Trong:

```text
k3s-kubeconfig.yaml
```

thay:

```yaml
server: https://127.0.0.1:6443
```

bằng hostname mà Jenkins có thể resolve:

```yaml
server: https://floci-eks-acman-dev:6443
```

Không thay đổi:

```yaml
certificate-authority-data:
```

Không thay đổi:

```yaml
client-certificate-data:
```

Không thay đổi:

```yaml
client-key-data:
```

Đặc biệt không đưa private key trong kubeconfig lên GitHub.

---

# 11. Vấn đề TLS certificate

Khi dùng:

```yaml
server: https://floci-eks-acman-dev:6443
```

có thể gặp:

```text
tls: failed to verify certificate:
x509: certificate is valid for ...
not floci-eks-acman-dev
```

Nguyên nhân:

K3s certificate chưa có:

```text
floci-eks-acman-dev
```

trong SAN.

Đây là lỗi **TLS hostname**, không phải Docker network.

Kiểm tra connectivity trước:

```powershell
docker exec jenkins-blueocean curl -k \
  https://floci-eks-acman-dev:6443/version
```

Nếu nhận:

```json
{
  "status": "Failure",
  "message": "Unauthorized",
  "reason": "Unauthorized",
  "code": 401
}
```

thì điều đó thực ra là tín hiệu tốt.

Nó chứng minh:

```text
Jenkins
   ↓
Docker DNS
   ↓
floci-eks-acman-dev
   ↓
K3s API Server
```

đã kết nối được.

`401 Unauthorized` chỉ có nghĩa là request chưa cung cấp Kubernetes credentials.

---

# 12. Kiểm tra Kubernetes bằng kubeconfig

Copy kubeconfig vào Jenkins:

```powershell
docker cp .\k3s-kubeconfig.yaml jenkins-blueocean:/tmp/k3s.yaml
```

Sau đó:

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get nodes
```

Nếu thành công:

```text
NAME                    STATUS   ROLES
floci-eks-acman-dev     Ready    control-plane,master
```

thì Jenkins đã có thể quản lý K3s.

---

# 13. Không sử dụng IP Docker nếu không cần thiết

Không nên hard-code:

```yaml
server: https://172.18.0.4:6443
```

vì Docker container IP có thể thay đổi.

Tốt hơn:

```yaml
server: https://floci-eks-acman-dev:6443
```

Docker network cung cấp DNS service/container name.

Kiến trúc:

```text
Jenkins
   │
   │ DNS
   ▼
floci-eks-acman-dev
   │
   ▼
K3s :6443
```

---

# 14. Một trường hợp đặc biệt: sử dụng Docker container ID

Trong một số trường hợp lab, K3s certificate có SAN là Docker container hostname/ID.

Ví dụ certificate có thể chứa:

```text
57ef521f8f78
```

Nếu hostname này nằm trong certificate SAN và Docker DNS resolve được:

```powershell
docker exec jenkins-blueocean getent hosts 57ef521f8f78
```

thì có thể dùng:

```yaml
server: https://57ef521f8f78:6443
```

để test.

Tuy nhiên đây chỉ nên xem là **temporary workaround**.

Container ID có thể thay đổi khi container được recreate.

Giải pháp lâu dài tốt hơn là cấu hình K3s certificate với hostname ổn định.

---

# 15. Kiểm tra Jenkins → Kubernetes

Sau khi kubeconfig hoạt động:

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get nodes
```

Kiểm tra namespace:

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get namespaces
```

Kiểm tra Pod:

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get pods -A
```

---

# 16. Cài Kubernetes CLI Plugin cho Jenkins

Để Jenkins Pipeline sử dụng:

```groovy
withKubeConfig(...)
```

cần cài:

```text
Kubernetes CLI Plugin
```

Plugin ID:

```text
kubernetes-cli
```

Sau khi cài plugin, tạo Jenkins Credential:

```text
Kind:
Secret file

ID:
k3s-kubeconfig
```

Upload:

```text
k3s-kubeconfig.yaml
```

---

# 17. Deploy Kubernetes từ Jenkins

Ví dụ:

```groovy
stage("Deploy Kubernetes") {
    steps {
        withKubeConfig(credentialsId: 'k3s-kubeconfig') {
            sh '''
                set -e

                echo "=== Kubernetes Nodes ==="
                kubectl get nodes

                echo "=== Deploy Kubernetes ==="
                kubectl apply -f Kubernetes/

                echo "=== Pods ==="
                kubectl get pods

                echo "=== Services ==="
                kubectl get services
            '''
        }
    }
}
```

Flow:

```text
GitHub
   ↓
Jenkins
   ↓
Checkout
   ↓
Build/Test
   ↓
SonarQube
   ↓
Security Scan
   ↓
Docker Build
   ↓
Docker Push
   ↓
kubectl apply
   ↓
K3s
   ↓
Application
```

---

# 18. Kubernetes NodePort

Ví dụ Service:

```yaml
apiVersion: v1
kind: Service

metadata:
  name: netflix-app

spec:
  type: NodePort

  selector:
    app: netflix

  ports:
    - port: 80
      targetPort: 80
      nodePort: 32000
```

Kiểm tra:

```powershell
kubectl get svc
```

Kết quả:

```text
NAME          TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)
netflix-app   NodePort   10.43.75.131    <none>        80:32000/TCP
```

Điều này có nghĩa:

```text
Service port:
80

Container target:
80

NodePort:
32000
```

---

# 19. Kiểm tra Deployment

```powershell
kubectl get deployment
```

Ví dụ:

```text
NAME          READY   UP-TO-DATE   AVAILABLE
netflix-app   2/2     2            2
```

Kiểm tra Pod:

```powershell
kubectl get pods -o wide
```

Ví dụ:

```text
NAME                           READY   STATUS
netflix-app-xxxxxxxxxx-xxxxx   1/1     Running
netflix-app-xxxxxxxxxx-yyyyy   1/1     Running
```

Kiểm tra endpoint:

```powershell
kubectl get endpoints netflix-app
```

Phải có:

```text
10.42.x.x:80
```

Nếu:

```text
<none>
```

thì Service chưa tìm được Pod phù hợp với selector.

---

# 20. Vì sao `http://localhost:32000` chưa chắc hoạt động?

Đây là điểm quan trọng nhất của FloCI/K3s lab.

Có:

```text
Kubernetes Service
      │
      │ NodePort 32000
      ▼
K3s container
```

không đồng nghĩa với:

```text
Windows localhost:32000
```

Docker phải publish:

```text
Windows:32000
        ↓
K3s container:32000
```

Trong môi trường FloCI:

```text
floci
```

và:

```text
floci-eks-acman-dev
```

là **hai container khác nhau**.

Dòng:

```yaml
ports:
  - "32000:32000"
```

của:

```text
floci
```

không có nghĩa:

```text
floci-eks-acman-dev
```

cũng có port mapping này.

---

# 21. `kubectl port-forward` – cách test nhanh

Để kiểm tra application sau khi Jenkins deploy thành công, không cần expose Docker port.

Dùng:

```powershell
kubectl port-forward svc/netflix-app 32000:80
```

Kết quả:

```text
Forwarding from 127.0.0.1:32000 -> 80
Forwarding from [::1]:32000 -> 80
```

Sau đó mở:

```text
http://localhost:32000
```

Flow lúc này:

```text
Browser
   │
   │ localhost:32000
   ▼
kubectl port-forward
   │
   ▼
Kubernetes Service
   │
   ▼
netflix-app Pod
```

Đây là cách **rất tốt để test deployment trong local lab**.

Lưu ý:

```text
kubectl port-forward
```

chỉ tồn tại khi terminal đang chạy lệnh đó.

Đóng terminal → forwarding mất.

---

# 22. Không dùng port-forward làm production deployment

`kubectl port-forward` phù hợp:

```text
Development
Testing
Debugging
Demo
```

Không phù hợp:

```text
Production traffic
Permanent public endpoint
Load balancing
High availability
```

Nếu muốn truy cập permanent trong local lab, có thể dùng:

```text
NodePort
Ingress
Traefik
NGINX Ingress
LoadBalancer
```

---

# 23. SonarQube local

SonarQube chạy trên Windows:

```text
http://localhost:9000
```

Jenkins container không nên dùng:

```text
http://localhost:9000
```

vì `localhost` bên trong Jenkins container là Jenkins container.

Thay vào đó:

```text
http://host.docker.internal:9000
```

Flow:

```text
Jenkins container
       │
       │ host.docker.internal
       ▼
Windows Host
       │
       ▼
SonarQube :9000
```

---

# 24. SonarQube Jenkins configuration

Trong Jenkins:

```text
Manage Jenkins
    ↓
System
    ↓
SonarQube servers
```

Ví dụ:

```text
Name:
sonar-server

Server URL:
http://host.docker.internal:9000
```

Pipeline:

```groovy
withSonarQubeEnv('sonar-server') {
    sh '''
        npx @sonar/scan \
          -Dsonar.projectKey=NetflixClone \
          -Dsonar.projectName=NetflixClone \
          -Dsonar.sources=src \
          -Dsonar.exclusions=dist/**,node_modules/**,public/** \
          -Dsonar.host.url=$SONAR_HOST_URL \
          -Dsonar.token=$SONAR_AUTH_TOKEN
    '''
}
```

---

# 25. SonarQube Quality Gate

Sau khi scan:

```groovy
stage("Quality Gate") {
    steps {
        timeout(time: 10, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true
        }
    }
}
```

Flow:

```text
Jenkins
   │
   │ Sonar Scan
   ▼
SonarQube
   │
   │ Analysis
   ▼
Quality Gate
   │
   ├── PASS → tiếp tục pipeline
   │
   └── FAIL → stop pipeline
```

---

# 26. Cloudflare Tunnel cho SonarQube Webhook

SonarQube cần gửi webhook về Jenkins.

Nhưng Jenkins local thường chạy:

```text
http://localhost:8080
```

SonarQube và Jenkins đều nằm trong local environment.

SonarQube Cloud/Webhook hoặc các thành phần bên ngoài không thể trực tiếp truy cập:

```text
localhost
```

Vì `localhost` chỉ có ý nghĩa trên chính máy gửi request.

Có thể sử dụng Cloudflare Quick Tunnel để tạo public URL.

Ví dụ:

```text
https://xxxxx.trycloudflare.com
```

Flow:

```text
SonarQube
    │
    │ Webhook
    ▼
Cloudflare Tunnel
    │
    ▼
Jenkins
    │
    ▼
/sonarqube-webhook/
```

Webhook URL:

```text
https://xxxxx.trycloudflare.com/sonarqube-webhook/
```

---

# 27. Quan trọng về Cloudflare hostname

Không nên hiểu rằng:

```text
trycloudflare.com
```

là một hostname local cần đưa vào Docker `/etc/hosts`.

Cloudflare Tunnel hoạt động theo mô hình:

```text
Public URL
      │
      ▼
Cloudflare
      │
      ▼
cloudflared tunnel
      │
      ▼
localhost:8080
      │
      ▼
Jenkins
```

Do đó Quick Tunnel phải được chạy liên tục.

Ví dụ:

```powershell
cloudflared tunnel --url http://localhost:8080
```

Nếu Jenkins chạy trên port `8080`.

Nếu tunnel expose SonarQube thì tunnel phải trỏ tới SonarQube endpoint tương ứng.

Cần đảm bảo URL webhook cuối cùng trỏ đúng vào Jenkins:

```text
/sonarqube-webhook/
```

---

# 28. Jenkins Webhook Endpoint

Endpoint Jenkins cho SonarQube:

```text
/sonarqube-webhook/
```

Ví dụ:

```text
https://xxxxx.trycloudflare.com/sonarqube-webhook/
```

Không dùng:

```text
https://xxxxx.trycloudflare.com/
```

nếu webhook đang được cấu hình cho Jenkins SonarQube plugin.

---

# 29. Kiểm tra Webhook

Trong SonarQube:

```text
Administration
    ↓
Configuration
    ↓
Webhooks
```

Thêm:

```text
Name:
Jenkins

URL:
https://xxxxx.trycloudflare.com/sonarqube-webhook/
```

Sau khi pipeline chạy Sonar Analysis:

```text
Jenkins
   ↓
SonarQube Analysis
   ↓
SonarQube
   ↓
Quality Gate
   ↓
Webhook
   ↓
Jenkins
   ↓
waitForQualityGate
```

---

# 30. CI/CD Pipeline hoàn chỉnh

Pipeline local có thể thiết kế:

```text
GitHub Push
     │
     ▼
Jenkins
     │
     ├── Clean Workspace
     │
     ├── Checkout
     │
     ├── Install Dependencies
     │
     ├── Unit Test
     │
     ├── SonarQube Analysis
     │
     ├── Quality Gate
     │
     ├── OWASP Dependency Check
     │
     ├── Trivy Filesystem Scan
     │
     ├── Docker Build
     │
     ├── Trivy Image Scan
     │
     ├── Docker Push
     │
     └── Kubernetes Deploy
              │
              ▼
       FloCI / K3s
              │
              ▼
       Kubernetes Service
              │
              ▼
       Netflix Application
```

---

# 31. Kiểm tra từng layer khi troubleshooting

Khi deploy không thành công, không nên kiểm tra tất cả cùng lúc.

Kiểm tra theo thứ tự:

## Layer 1 – Docker

```powershell
docker ps
```

Kiểm tra:

```text
jenkins-blueocean
floci
floci-eks-acman-dev
```

---

## Layer 2 – Docker Network

```powershell
docker network inspect jenkins
```

Phải có:

```text
jenkins-blueocean
floci-eks-acman-dev
```

---

## Layer 3 – DNS

Từ Jenkins:

```powershell
docker exec jenkins-blueocean getent hosts floci-eks-acman-dev
```

Phải resolve được IP.

---

## Layer 4 – Kubernetes API

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get nodes
```

---

## Layer 5 – Deployment

```powershell
kubectl get deployment
```

---

## Layer 6 – Pod

```powershell
kubectl get pods -o wide
```

---

## Layer 7 – Service

```powershell
kubectl get svc
```

---

## Layer 8 – Endpoint

```powershell
kubectl get endpoints netflix-app
```

---

## Layer 9 – Application

Test:

```powershell
kubectl port-forward svc/netflix-app 32000:80
```

Sau đó:

```text
http://localhost:32000
```

---

# 32. Các lỗi thường gặp

## Lỗi 1 – `kubectl` không tìm thấy

```text
kubectl: command not found
```

Jenkins agent chưa có Kubernetes CLI.

Giải pháp:

* cài `kubectl` trong Jenkins custom image
* hoặc dùng Jenkins Kubernetes CLI tool/plugin.

---

## Lỗi 2 – `withKubeConfig` không tồn tại

```text
No such DSL method 'withKubeConfig'
```

Cài:

```text
Kubernetes CLI Plugin
```

---

## Lỗi 3 – Jenkins không truy cập Docker

```text
permission denied
/var/run/docker.sock
```

Local lab:

```powershell
docker exec -u root jenkins-blueocean `
  chmod 666 /var/run/docker.sock
```

---

## Lỗi 4 – Kubernetes `127.0.0.1:6443`

```text
Unable to connect to the server
```

Kiểm tra kubeconfig:

```yaml
server: https://127.0.0.1:6443
```

Nếu Jenkins chạy container khác thì cần hostname K3s:

```yaml
server: https://floci-eks-acman-dev:6443
```

---

## Lỗi 5 – TLS SAN

```text
x509:
certificate is valid for ...
not floci-eks-acman-dev
```

Đây là lỗi certificate hostname.

Không phải lỗi Docker DNS.

---

## Lỗi 6 – NodePort không truy cập được từ Windows

Kubernetes:

```text
80:32000/TCP
```

nhưng:

```powershell
Test-NetConnection localhost -Port 32000
```

trả:

```text
TcpTestSucceeded : False
```

Có nghĩa Docker host chưa publish NodePort của `floci-eks-acman-dev`.

Có thể dùng tạm:

```powershell
kubectl port-forward svc/netflix-app 32000:80
```

để test application.

---

# 33. Checklist khởi động Lab

Mỗi lần dựng lại environment:

### Docker

```powershell
docker ps
```

### Jenkins

```powershell
docker ps --filter name=jenkins-blueocean
```

### Docker socket

```powershell
docker exec jenkins-blueocean docker ps
```

### FloCI

```powershell
docker ps --filter name=floci
```

### K3s

```powershell
docker ps --filter name=floci-eks-acman-dev
```

### Network

```powershell
docker network inspect jenkins
```

### Kubeconfig

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get nodes
```

### Kubernetes

```powershell
docker exec jenkins-blueocean `
  kubectl --kubeconfig=/tmp/k3s.yaml get pods -A
```

### Application

```powershell
kubectl port-forward svc/netflix-app 32000:80
```

### Browser

```text
http://localhost:32000
```

---

# 34. Nguyên tắc quan trọng của Lab

Có 5 nguyên tắc cần nhớ.

### 1. `floci` khác `floci-eks-acman-dev`

```text
floci
```

là FloCI service.

```text
floci-eks-acman-dev
```

là K3s cluster container được FloCI tạo tự động.

---

### 2. Cùng Docker network để Jenkins truy cập K3s

```text
jenkins
├── jenkins-blueocean
└── floci-eks-acman-dev
```

---

### 3. Không dùng `127.0.0.1` cho K3s API từ Jenkins

Dùng:

```text
https://floci-eks-acman-dev:6443
```

hoặc hostname phù hợp với certificate SAN.

---

### 4. NodePort không đồng nghĩa Docker Host Port

```text
Kubernetes NodePort 32000
```

không tự động có nghĩa:

```text
Windows localhost:32000
```

Để test nhanh:

```powershell
kubectl port-forward svc/netflix-app 32000:80
```

---

### 5. Không đưa kubeconfig/private key lên GitHub

Kubeconfig K3s chứa:

```text
client-certificate-data
client-key-data
```

Đây là credentials.

Không commit:

```text
k3s-kubeconfig.yaml
```

vào repository.

Nên thêm:

```gitignore
k3s-kubeconfig.yaml
*.kubeconfig
```

và lưu kubeconfig trong Jenkins Credentials:

```text
Secret file
ID: k3s-kubeconfig
```

---

# 35. Kiến trúc Lab hoàn chỉnh

Cuối cùng, mô hình local CI/CD của project:

```text
                         ┌───────────────┐
                         │    GitHub     │
                         └───────┬───────┘
                                 │
                              git push
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │ Jenkins Docker         │
                    │                        │
                    │ Node.js                │
                    │ Docker CLI             │
                    │ kubectl                │
                    │ Trivy                  │
                    └───────┬─────────┬──────┘
                            │         │
                   SonarQube│         │Docker
                            │         │
                            ▼         ▼
                    ┌───────────┐   Docker
                    │ SonarQube │   Registry
                    │ :9000     │
                    └─────┬─────┘
                          │
                       Webhook
                          │
                    Cloudflare Tunnel
                          │
                          ▼
                       Jenkins


Jenkins
   │
   │ kubectl
   ▼
┌───────────────────────────────────┐
│ Docker Network: jenkins           │
│                                   │
│ ┌───────────────────────────────┐ │
│ │ floci-eks-acman-dev           │ │
│ │                               │ │
│ │ K3s                           │ │
│ │   │                           │ │
│ │   ├── Deployment              │ │
│ │   │     └── netflix-app       │ │
│ │   │                           │ │
│ │   └── Service                 │ │
│ │         NodePort: 32000       │ │
│ └───────────────────────────────┘ │
└───────────────────────────────────┘
                  │
                  │ kubectl port-forward
                  ▼
        Windows localhost:32000
                  │
                  ▼
             Web Browser
```

---

# 36. Kết luận

Mục tiêu cuối cùng của lab là mô phỏng gần giống quy trình thực tế:

```text
Developer
   │
   │ git push
   ▼
GitHub
   │
   ▼
Jenkins
   │
   ├── Test
   ├── Build
   ├── SonarQube
   ├── Quality Gate
   ├── OWASP
   ├── Trivy
   ├── Docker Build
   └── Docker Push
            │
            ▼
       Kubernetes
            │
            ▼
      FloCI / K3s
            │
            ▼
     Application Pods
            │
            ▼
       Kubernetes Service
            │
            ▼
    kubectl port-forward
            │
            ▼
    http://localhost:32000
```

Đây là một mô hình rất phù hợp để học **CI/CD + Docker + Kubernetes + Terraform + AWS/EKS concepts** hoàn toàn local trước khi chuyển sang AWS thật.

------------------------------

docker run --name jenkins-blueocean `
  --restart=on-failure `
  --detach `
  --network jenkins `
  --volume jenkins-data:/var/jenkins_home `
  --volume /var/run/docker.sock:/var/run/docker.sock `
  --publish 8080:8080 `
  --publish 50000:50000 `
  jenkins-custom

  -- to allow jenkins connect to docker daemon cli
  docker exec -u root -it jenkins chmod 666 /var/run/docker.sock


  -to copy config k3s to container jenkins
  docker cp .\k3s-kubeconfig.yaml jenkins-blueocean:/tmp/k3s.yaml
 
 cho floci-eks-acman-dev cung network voi jenkins 

  --docker network connect jenkins floci-eks-acman-dev 

  --để jenkins có thể kết nối được kubernetes cùng chạy trên docker thì chungs phải cùng network và file cấu hình của floci kubernetes server phải là hostname khong phải ip 127.0.0.1 nhé - lay cai id ma dùng đc oke rồi nhé 

  --phải resolve fake cloudflare hostname de local cua sonar co thể webhook tới jenkins ci/cd nhé

  -- to test deploy to kubernetes thành công thì dùng
  kubectl port-forward svc/netflix-app 32000:80