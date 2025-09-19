# GCP 인프라 구성 (Terraform)

## 개요

이 폴더는 **Kubernetes 클러스터 구축을 위한 GCP 인프라를 자동화**하는 Terraform 구성을 포함합니다.

### 목적
- **Infrastructure as Code**: GCP 리소스를 코드로 관리하여 일관성 있는 인프라 구성
- **자동화된 인프라 배포**: 수동 설정의 실수를 방지하고 재현 가능한 환경 구성
- **Kubernetes 클러스터 기반 마련**: kubeadm을 사용한 K8s 클러스터 구축을 위한 VM 인스턴스와 네트워크 환경 제공

### 전체 워크플로우에서의 역할
```
1. Terraform (이 폴더) → GCP 인프라 구성 (VM, 네트워크, 방화벽)
2. Ansible (../ansible/) → Kubernetes 소프트웨어 설치 및 클러스터 구성
3. 실습 환경 → Kubernetes 학습 및 실습
```

## 구성 요소

이 Terraform 구성으로 생성되는 주요 리소스:

### 컴퓨팅 리소스
- **Master Node**: k8s-master (e2-standard-2, 30GB SSD)
- **Worker Nodes**: k8s-worker-0,1,2 (각각 e2-standard-2, 30GB SSD)

### 네트워크 구성
- **VPC 네트워크**: k8s-network (커스텀 모드)
- **서브넷**: k8s-subnet (10.240.0.0/24, asia-northeast3)
- **방화벽 규칙**:
  - 내부 통신 허용 (TCP/UDP/ICMP)
  - 외부 SSH 및 K8s API 서버 접근 (22, 6443)

### 보안 구성
- **SSH 키 관리**: 자동 SSH 키 등록
- **서비스 계정**: Terraform 전용 서비스 계정과 최소 권한 원칙

## 사전 준비

### 1. gcloud CLI 설치

```shell
brew install --cask gcloud-cli

# gcloud 초기화 및 프로젝트 설정
gcloud init

# 기본 리전/존 설정
gcloud config set compute/region asia-northeast3
gcloud config set compute/zone asia-northeast3-a

# 설정 확인
gcloud config list
```

### 2. Terraform 용 계정 및 키 생성

GCP 계정 생성:

```shell
# 계정 생성
gcloud iam service-accounts create terraform-sa \
    --display-name="Terraform Service Account" \
    --description="Service account for Terraform"
```

GCP 계정 권한 부여:

```shell
# 권한 부여
export PROJECT_ID=$(gcloud config get-value project)
export SA_EMAIL=terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Compute Admin 권한 부여
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.admin"

# Security Admin 권한 부여 (방화벽 규칙용)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.securityAdmin"

# Service Account User 권한 부여
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser"
```

GCP 계정 키 생성:

```shell
gcloud iam service-accounts keys create terraform-key.json \
    --iam-account=${SA_EMAIL}

chmod 600 terraform-key.json
```

### 3. SSH 키 생성 및 설정

인스턴스 접속을 위한 SSH 키페어 생성:

```shell
# SSH 키가 없는 경우 새로 생성
export KEY_NAME=ai-k8s-practice
export KEY_PATH=~/.ssh/${KEY_NAME}

ssh-keygen -t rsa -b 4096 -f ${KEY_PATH} -C ${KEY_NAME}

# 권한 설정
chmod 600 ${KEY_PATH}
chmod 644 ${KEY_PATH}.pub

# 공개키 내용 확인
cat ${KEY_PATH}.pub
```

> **참고**: main.tf에서 `~/.ssh/{KEY_NAME}.pub` 경로의 공개키를 자동으로 읽어서 인스턴스 메타데이터에 추가합니다.

## 배포 및 관리

### 4. Terraform 실행

인프라 배포:

```shell
# Terraform 초기화 (처음 실행 시)
terraform init

# variables.tf 파일 수정하여 프로젝트 정보 설정
# - project_id: GCP 프로젝트 ID

# 실행 계획 확인
terraform plan

# 인프라 배포
terraform apply

# 배포된 인프라 정보 확인
terraform output
```

### 5. 배포 확인 및 접속 테스트

배포 완료 후 인스턴스 정보 확인:

```shell
# 배포된 리소스 정보 출력
terraform output

# 인스턴스 상태 확인
terraform show
```

인스턴스 SSH 접속 테스트:

```shell
# 마스터 노드 접속
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -raw master_external_ip)

# 워커 노드 접속
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -json worker_external_ips | jq -r '.[0]')
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -json worker_external_ips | jq -r '.[1]')
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -json worker_external_ips | jq -r '.[2]')
```

### 6. 인프라 관리

인프라 수정:

```shell
# 설정 변경 후 계획 확인
terraform plan

# 변경사항 적용
terraform apply

# 특정 리소스만 다시 생성
terraform taint google_compute_instance.k8s-master
terraform apply
```

인프라 삭제:

```shell
# 주의: 모든 리소스가 삭제됩니다
terraform destroy

# 삭제 전 계획 확인
terraform plan -destroy
```

### 주의사항

- **상태 관리**: Terraform 상태 파일(`terraform.tfstate`)을 안전하게 보관
- **비용 관리**: 사용하지 않는 리소스는 `terraform destroy`로 삭제

### 트러블슈팅

**일반적인 문제와 해결방법:**

1. **권한 에러**: 서비스 계정 키와 권한 설정 확인
2. **SSH 접속 실패**: SSH 키 경로와 권한(600) 확인
3. **리소스 할당량 초과**: GCP 프로젝트의 할당량 확인
4. **네트워크 접근 불가**: 방화벽 규칙과 VPC 설정 확인

## 다음 단계

Terraform으로 인프라 배포가 완료되면, [Ansible](../ansible/README.md)을 사용하여 Kubernetes 클러스터를 구성할 수 있습니다.

**역할 분리**: Terraform은 인프라 구성, Ansible은 소프트웨어 구성을 담당합니다.