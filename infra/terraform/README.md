# GCP 환경 구성

## 1. gcloud CLI 설치

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

## 2. Terraform 용 계정 및 키 생성

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

## 3. SSH 키 생성 및 설정

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

## 4. Terraform 실행

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

인스턴스 접속 테스트:

```shell
# 마스터 노드 접속
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -raw master_external_ip)

# 워커 노드 접속
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -json worker_external_ips | jq -r '.[0]')
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -json worker_external_ips | jq -r '.[1]')
ssh -i ~/.ssh/ai-k8s-practice ubuntu@$(terraform output -json worker_external_ips | jq -r '.[2]')
```

## 5. 다음 단계

Terraform으로 인프라가 배포되면, [Ansible](../ansible/README.md)을 사용하여 Kubernetes 클러스터를 구성할 수 있습니다.

> **Note**: Ansible 플레이북은 별도로 준비되어야 합니다. 인프라는 Terraform이, 구성 관리는 Ansible이 담당하는 역할 분리 구조입니다.

