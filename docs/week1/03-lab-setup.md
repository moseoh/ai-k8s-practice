# 실습환경 구성 - Ubuntu 22.04 + GCP + kubeadm

## 목차

1. [환경 요구사항](#환경-요구사항)
2. [GCP 환경 준비](#gcp-환경-준비)
3. [시스템 사전 설정](#시스템-사전-설정)
4. [kubeadm 설치 및 구성](#kubeadm-설치-및-구성)
5. [kubectl 설정](#kubectl-설정)
6. [실습 시나리오](#실습-시나리오)
7. [문제 해결](#문제-해결)

---

## 환경 요구사항

### [공식 Kubernetes 시스템 요구사항](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#check-required-ports) (kubeadm 기준)

#### 하드웨어 요구사항 (Kubernetes 공식 문서 기준)

| 구성 요소   | Master Node | Worker Node | 설명                |
|---------|-------------|-------------|-------------------|
| **CPU** | 2 cores 이상  | -           | 최소 요구사항           |
| **메모리** | 2GB 이상      | 2GB 이상      | 앱 실행 공간 확보 필요     |
| **디스크** | 20GB 이상     | 20GB 이상     | OS + K8s + 애플리케이션 |

#### 실습 권장 구성 (GCP Compute Engine)

| 노드 타입      | 머신 타입    | CPU    | 메모리 | 디스크      | 수량 |
|------------|----------|--------|-----|----------|----|
| **Master** | e2-small | 2 vCPU | 8GB | 30GB SSD | 1개 |
| **Worker** | e2-small | 2 vCPU | 8GB | 30GB SSD | 3개 |

> e2-small: \$15.6887439 / 1 month\
> e2-small * 4: \$62.7549756 / 1 month

### 소프트웨어 요구사항

#### 운영체제

- **Ubuntu 22.04 LTS** (Jammy Jellyfish)
- 64-bit 아키텍처
- 최신 보안 업데이트 적용

#### 필수 소프트웨어

- **Container Runtime**: containerd (권장) 또는 Docker
- **Network Plugin**: Calico 또는 Flannel
- **kubectl**: Kubernetes CLI 도구
- **kubeadm**: 클러스터 부트스트랩 도구
- **kubelet**: Kubernetes 노드 에이전트

#### 시스템 요구사항

- Swap 메모리 비활성화 필수
- 고유한 hostname, MAC 주소, product_uuid
- 필요한 포트 오픈 (아래 포트 섹션 참조)
- glibc 지원 (Ubuntu 22.04는 기본 지원)

### 네트워크 요구사항

#### 포트 요구사항

**Master Node:**

| 포트        | 프로토콜 | 용도                      |
|-----------|------|-------------------------|
| 6443      | TCP  | Kubernetes API Server   |
| 2379-2380 | TCP  | etcd server client API  |
| 10250     | TCP  | Kubelet API             |
| 10259     | TCP  | kube-scheduler          |
| 10257     | TCP  | kube-controller-manager |

**Worker Node:**

| 포트          | 프로토콜 | 용도                |
|-------------|------|-------------------|
| 10250       | TCP  | Kubelet API       |
| 30000-32767 | TCP  | NodePort Services |

#### 네트워크 설정

- 모든 노드 간 통신 가능
- 방화벽 규칙 설정 (필요한 포트 오픈)
- DNS 해석 가능
- 시간 동기화 (NTP)

---

## GCP 환경 준비

### Google Cloud Platform 설정

#### 1. GCP 프로젝트 생성

```bash
# gcloud CLI 설치 (로컬에서)
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# 새 프로젝트 생성
gcloud projects create k8s-lab-project-$(date +%s)
gcloud config set project k8s-lab-project-$(date +%s)

# Compute Engine API 활성화
gcloud services enable compute.googleapis.com
```

#### 2. VPC 네트워크 구성

```bash
# VPC 네트워크 생성
gcloud compute networks create k8s-network --subnet-mode=custom

# 서브넷 생성
gcloud compute networks subnets create k8s-subnet \
    --network=k8s-network \
    --range=10.240.0.0/24 \
    --region=asia-northeast3

# 방화벽 규칙 생성 (내부 통신)
gcloud compute firewall-rules create k8s-allow-internal \
    --allow tcp,udp,icmp \
    --network k8s-network \
    --source-ranges 10.240.0.0/24

# 방화벽 규칙 생성 (외부 SSH, API 서버)
gcloud compute firewall-rules create k8s-allow-external \
    --allow tcp:22,tcp:6443,icmp \
    --network k8s-network \
    --source-ranges 0.0.0.0/0
```

#### 3. Compute Engine 인스턴스 생성

**Master Node 생성:**

```bash
gcloud compute instances create k8s-master \
    --async \
    --boot-disk-size 30GB \
    --boot-disk-type pd-ssd \
    --can-ip-forward \
    --image-family ubuntu-2204-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --private-network-ip 10.240.0.10 \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet k8s-subnet \
    --tags k8s-node,master \
    --zone asia-northeast3-a
```

**Worker Node 생성:**

```bash
for i in 0 1 2; do
  gcloud compute instances create k8s-worker-${i} \
    --async \
    --boot-disk-size 30GB \
    --boot-disk-type pd-ssd \
    --can-ip-forward \
    --image-family ubuntu-2204-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --private-network-ip 10.240.0.2${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet k8s-subnet \
    --tags k8s-node,worker \
    --zone asia-northeast3-a
done
```

#### 4. SSH 키 설정

```bash
# SSH 키 생성 (로컬에서)
ssh-keygen -t rsa -b 2048 -f ~/.ssh/k8s-key

# SSH 키 등록
gcloud compute project-info add-metadata \
    --metadata-from-file ssh-keys=~/.ssh/k8s-key.pub
```

### 인스턴스 접속 확인

```bash
# 인스턴스 목록 확인
gcloud compute instances list

# Master 노드 접속
gcloud compute ssh k8s-master --zone=asia-northeast3-a

# Worker 노드 접속
gcloud compute ssh k8s-worker-0 --zone=asia-northeast3-a
```

---

## 시스템 사전 설정

### 모든 노드에서 공통 작업

#### 1. 시스템 업데이트

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl
```

#### 2. Swap 비활성화

```bash
# Swap 비활성화
sudo swapoff -a

# 영구적으로 Swap 비활성화
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 확인
free -h
```

#### 3. 커널 모듈 및 sysctl 설정

```bash
# 필요한 커널 모듈 로드
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl 설정
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 설정 적용
sudo sysctl --system

# 확인
lsmod | grep br_netfilter
lsmod | grep overlay
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

#### 4. Container Runtime 설치 (containerd)

**containerd 설치:**

```bash
# containerd 설치
sudo apt update
sudo apt install -y containerd

# containerd 구성 디렉토리 생성
sudo mkdir -p /etc/containerd

# 기본 구성 생성
containerd config default | sudo tee /etc/containerd/config.toml

# SystemdCgroup 설정 (runc 사용 시)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# containerd 재시작 및 자동 시작 설정
sudo systemctl restart containerd
sudo systemctl enable containerd

# 상태 확인
sudo systemctl status containerd
```

#### 5. 호스트명 설정

```bash
# Master 노드에서
sudo hostnamectl set-hostname k8s-master

# Worker 노드에서 (각각)
sudo hostnamectl set-hostname k8s-worker-0
sudo hostnamectl set-hostname k8s-worker-1
sudo hostnamectl set-hostname k8s-worker-2

# /etc/hosts 파일 업데이트 (모든 노드에서)
cat <<EOF | sudo tee -a /etc/hosts
10.240.0.10 k8s-master
10.240.0.20 k8s-worker-0
10.240.0.21 k8s-worker-1
10.240.0.22 k8s-worker-2
EOF
```

---

## kubeadm 설치 및 구성

### Kubernetes 패키지 설치 (모든 노드)

#### 1. Kubernetes 저장소 추가

```bash
# 패키지 저장소 키 추가
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
    https://packages.cloud.google.com/apt/doc/apt-key.gpg

# Kubernetes 저장소 추가
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] \
    https://apt.kubernetes.io/ kubernetes-xenial main" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list
```

#### 2. Kubernetes 패키지 설치

```bash
# 패키지 업데이트
sudo apt update

# 특정 버전 설치 (1.28.0 권장)
sudo apt install -y kubelet=1.28.0-00 kubeadm=1.28.0-00 kubectl=1.28.0-00

# 패키지 버전 고정 (자동 업데이트 방지)
sudo apt-mark hold kubelet kubeadm kubectl

# kubelet 자동 시작 설정
sudo systemctl enable kubelet
```

#### 3. 설치 확인

```bash
kubeadm version
kubelet --version
kubectl version --client
```

### Master Node 초기화

#### 1. 클러스터 초기화

```bash
# Master 노드에서만 실행
sudo kubeadm init \
  --apiserver-advertise-address=10.240.0.10 \
  --apiserver-cert-extra-sans=10.240.0.10 \
  --pod-network-cidr=192.168.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --node-name k8s-master

# 결과에서 join 명령어 저장 (Worker 노드 조인용)
```

#### 2. kubeconfig 설정

```bash
# 일반 사용자용 kubeconfig 설정
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# kubectl 자동 완성 설정
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

#### 3. 클러스터 상태 확인

```bash
# 노드 상태 확인
kubectl get nodes

# 시스템 Pod 상태 확인
kubectl get pods -n kube-system
```

### Pod Network 애드온 설치

#### Calico 설치 (권장)

```bash
# Calico 설치
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Calico 설정
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# CIDR 확인 및 설정 적용
kubectl create -f custom-resources.yaml

# Calico Pod 상태 확인
kubectl get pods -n calico-system
```

### Worker Node 조인

#### 1. Worker 노드에서 조인 실행

```bash
# Master 노드 초기화 시 출력된 명령어 실행
sudo kubeadm join 10.240.0.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

#### 2. 조인 토큰이 만료된 경우

```bash
# Master 노드에서 새 토큰 생성
kubeadm token create --print-join-command

# 출력된 명령어를 Worker 노드에서 실행
```

#### 3. 클러스터 상태 확인

```bash
# Master 노드에서 확인
kubectl get nodes
kubectl get nodes -o wide

# 모든 노드가 Ready 상태인지 확인
kubectl get pods --all-namespaces
```

---

## kubectl 설정

### 로컬 환경에서 클러스터 접근

#### 1. Master 노드에서 kubeconfig 복사

```bash
# Master 노드에서 kubeconfig 내용 출력
cat ~/.kube/config

# 로컬 환경에 복사
mkdir -p ~/.kube
# 위에서 출력한 내용을 ~/.kube/config에 저장

# 또는 SCP로 직접 복사
gcloud compute scp k8s-master:~/.kube/config ~/.kube/config --zone=asia-northeast3-a
```

#### 2. API 서버 접근 설정

```bash
# 현재 API 서버 주소 확인
kubectl config view --minify | grep server

# 외부 접근을 위한 방화벽 규칙 추가
gcloud compute firewall-rules create k8s-api-server \
    --allow tcp:6443 \
    --network k8s-network \
    --source-ranges 0.0.0.0/0 \
    --target-tags master
```

#### 3. kubectl 명령어 확인

```bash
# 클러스터 정보
kubectl cluster-info

# 노드 목록
kubectl get nodes

# 전체 리소스 확인
kubectl get all --all-namespaces
```

### kubectl 생산성 도구

#### 별칭 및 자동 완성 설정

```bash
# .bashrc에 추가
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias kgp="kubectl get pods"' >> ~/.bashrc
echo 'alias kgs="kubectl get services"' >> ~/.bashrc
echo 'alias kgd="kubectl get deployments"' >> ~/.bashrc
echo 'alias kaf="kubectl apply -f"' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc

source ~/.bashrc
```

---

## 실습 시나리오

### 시나리오 1: 클러스터 검증

```bash
# 1. 클러스터 정보 확인
kubectl cluster-info
kubectl get nodes -o wide
kubectl get componentstatuses

# 2. 시스템 Pod 상태 확인
kubectl get pods -n kube-system
kubectl get pods -n calico-system

# 3. 클러스터 리소스 확인
kubectl get all --all-namespaces
```

### 시나리오 2: 첫 번째 애플리케이션 배포

```bash
# 1. 테스트 Deployment 생성
kubectl create deployment nginx --image=nginx:latest --replicas=3

# 2. Service 생성
kubectl expose deployment nginx --port=80 --type=NodePort

# 3. 상태 확인
kubectl get pods -o wide
kubectl get services

# 4. 접근 테스트
NODE_PORT=$(kubectl get service nginx -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
curl http://$NODE_IP:$NODE_PORT
```

### 시나리오 3: 스케일링 및 업데이트

```bash
# 1. 스케일링
kubectl scale deployment nginx --replicas=5
kubectl get pods -w

# 2. 롤링 업데이트
kubectl set image deployment/nginx nginx=nginx:1.21
kubectl rollout status deployment/nginx

# 3. 롤백
kubectl rollout history deployment/nginx
kubectl rollout undo deployment/nginx
```

### 시나리오 4: 네임스페이스 관리

```bash
# 1. 네임스페이스 생성
kubectl create namespace development
kubectl create namespace production

# 2. 네임스페이스별 리소스 배포
kubectl create deployment app --image=nginx -n development
kubectl create deployment app --image=nginx:1.20 -n production

# 3. 네임스페이스별 리소스 확인
kubectl get pods -n development
kubectl get pods -n production
```

---

## 문제 해결

### 일반적인 문제

#### 1. 노드가 NotReady 상태

```bash
# 노드 상태 상세 확인
kubectl describe node <node-name>

# kubelet 로그 확인
sudo journalctl -u kubelet -f

# containerd 상태 확인
sudo systemctl status containerd

# 네트워크 플러그인 확인
kubectl get pods -n calico-system
kubectl logs -n calico-system <calico-pod-name>
```

#### 2. Pod가 Pending 상태

```bash
# Pod 상세 정보 확인
kubectl describe pod <pod-name>

# 이벤트 확인
kubectl get events --sort-by='.lastTimestamp'

# 노드 리소스 확인
kubectl top nodes
kubectl describe nodes
```

#### 3. Container Runtime 문제

```bash
# containerd 상태 확인
sudo systemctl status containerd

# containerd 재시작
sudo systemctl restart containerd

# containerd 로그 확인
sudo journalctl -u containerd -f

# 이미지 목록 확인
sudo ctr image ls
```

#### 4. 네트워크 문제

```bash
# Pod 간 통신 테스트
kubectl run test --image=busybox -it --rm -- sh
# Pod 내에서
nslookup kubernetes.default
ping <other-pod-ip>

# Calico 상태 확인
kubectl get pods -n calico-system
kubectl logs -n calico-system -l k8s-app=calico-node

# 네트워크 정책 확인
kubectl get networkpolicies --all-namespaces
```

### kubeadm 관련 문제

#### 초기화 실패

```bash
# kubeadm 리셋
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config

# iptables 정리
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# 재시도
sudo kubeadm init <옵션들>
```

#### 조인 실패

```bash
# Worker 노드에서 리셋
sudo kubeadm reset

# 새로운 토큰 생성 (Master에서)
kubeadm token create --print-join-command

# 다시 조인 시도
```

### GCP 관련 문제

#### 방화벽 문제

```bash
# 방화벽 규칙 확인
gcloud compute firewall-rules list

# 필요한 포트 오픈
gcloud compute firewall-rules create k8s-nodeport \
    --allow tcp:30000-32767 \
    --network k8s-network \
    --source-ranges 0.0.0.0/0 \
    --target-tags k8s-node
```

#### SSH 접근 문제

```bash
# SSH 키 확인
gcloud compute project-info describe | grep ssh-keys

# SSH 접속 테스트
gcloud compute ssh <instance-name> --zone=<zone>
```

---

## 클러스터 정리

### 리소스 삭제

```bash
# Kubernetes 리소스 삭제
kubectl delete deployments --all --all-namespaces
kubectl delete services --all --all-namespaces

# GCP 인스턴스 삭제
gcloud compute instances delete k8s-master k8s-worker-0 k8s-worker-1 k8s-worker-2 \
    --zone=asia-northeast3-a

# VPC 네트워크 삭제
gcloud compute firewall-rules delete k8s-allow-internal k8s-allow-external k8s-api-server k8s-nodeport
gcloud compute networks subnets delete k8s-subnet --region=asia-northeast3
gcloud compute networks delete k8s-network
```

---

## 체크리스트

### 환경 준비

- [ ] GCP 프로젝트 생성 및 설정
- [ ] VPC 네트워크 및 방화벽 규칙 구성
- [ ] Compute Engine 인스턴스 생성 (Master 1개, Worker 3개)
- [ ] SSH 접근 설정 완료

### 시스템 설정

- [ ] 모든 노드에서 시스템 업데이트
- [ ] Swap 메모리 비활성화
- [ ] 필요한 커널 모듈 로드
- [ ] containerd 설치 및 구성
- [ ] 호스트명 및 /etc/hosts 설정

### Kubernetes 설치

- [ ] Kubernetes 패키지 설치 (kubeadm, kubelet, kubectl)
- [ ] Master 노드 초기화 성공
- [ ] Pod 네트워크 애드온 설치 (Calico)
- [ ] Worker 노드 조인 완료
- [ ] 모든 노드 Ready 상태 확인

### 검증 및 테스트

- [ ] kubectl 명령어 정상 작동
- [ ] 테스트 애플리케이션 배포 성공
- [ ] Pod 간 통신 확인
- [ ] 서비스 접근 확인
- [ ] 기본 스케일링 및 업데이트 테스트

---

## 참고 자료

### 공식 문서

- [Kubernetes 공식 설치 가이드](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [kubeadm으로 클러스터 생성](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Google Cloud Compute Engine 문서](https://cloud.google.com/compute/docs)

### 네트워크 플러그인

- [Calico 설치 가이드](https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises)
- [Flannel 설치 가이드](https://github.com/flannel-io/flannel)

### 트러블슈팅

- [kubeadm 트러블슈팅](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
- [kubectl 치트시트](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)