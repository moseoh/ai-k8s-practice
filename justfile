#!/usr/bin/env just --justfile

# AI-K8S Infrastructure Management
# 실습 환경 구성을 위한 justfile

set dotenv-load := true
set export := true

# 기본 변수 설정
project_id := env_var_or_default('PROJECT_ID', '')
key_name := env_var_or_default('KEY_NAME', 'ai-k8s-practice')
key_path := env_var_or_default('KEY_PATH', '~/.ssh/' + key_name)
region := env_var_or_default('REGION', 'asia-northeast3')
zone := env_var_or_default('ZONE', 'asia-northeast3-a')

# 기본 명령: 도움말 표시
default:
    @just --list

# =================================
# GCP 설정 관련 명령
# =================================

# GCP CLI 초기화 및 프로젝트 설정
[group('gcp')]
@gcp-init:
    echo "🔧 GCP 초기화 중..."
    gcloud init
    gcloud config set compute/region {{region}}
    gcloud config set compute/zone {{zone}}
    echo "✅ GCP 설정 완료"
    gcloud config list

# Terraform 서비스 계정 생성
[group('gcp')]
@gcp-create-sa:
    echo "🔑 Terraform 서비스 계정 생성 중..."
    PROJECT_ID=$(gcloud config get-value project)
    SA_EMAIL=terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com
    
    # 계정 생성
    gcloud iam service-accounts create terraform-sa \
        --display-name="Terraform Service Account" \
        --description="Service account for Terraform" || true
    
    # 권한 부여
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/compute.admin"
    
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/compute.securityAdmin"
    
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/iam.serviceAccountUser"
    
    echo "✅ 서비스 계정 생성 및 권한 부여 완료"

# Terraform 서비스 계정 키 생성
[group('gcp')]
@gcp-create-key:
    echo "🔐 Terraform 서비스 계정 키 생성 중..."
    PROJECT_ID=$(gcloud config get-value project)
    SA_EMAIL=terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com
    
    gcloud iam service-accounts keys create terraform/terraform-key.json \
        --iam-account=${SA_EMAIL}
    
    chmod 600 terraform/terraform-key.json
    echo "✅ 키 파일 생성 완료: terraform/terraform-key.json"

# SSH 키페어 생성
[group('ssh')]
@ssh-keygen:
    echo "🔑 SSH 키페어 생성 중..."
    if [ ! -f {{key_path}} ]; then \
        ssh-keygen -t rsa -b 4096 -f {{key_path}} -C {{key_name}} -N ""; \
        chmod 600 {{key_path}}; \
        chmod 644 {{key_path}}.pub; \
        echo "✅ SSH 키 생성 완료: {{key_path}}"; \
    else \
        echo "⚠️  SSH 키가 이미 존재합니다: {{key_path}}"; \
    fi

# =================================
# Terraform 관련 명령
# =================================

# Terraform 초기화
[group('terraform')]
@terraform-init: ssh-keygen
    echo "🚀 Terraform 초기화 중..."
    cd infra/terraform && terraform init
    echo "✅ Terraform 초기화 완료"

# Terraform 실행 계획 확인
[group('terraform')]
@terraform-plan: terraform-init
    echo "📋 Terraform 실행 계획 확인 중..."
    cd infra/terraform && terraform plan

# 인프라 배포
[group('terraform')]
@terraform-apply: terraform-init
    echo "🏗️  인프라 배포 중..."
    cd infra/terraform && terraform apply
    echo "✅ 인프라 배포 완료"
    @just terraform-output

# 인프라 배포 (자동 승인)
[group('terraform')]
@terraform-apply-auto: terraform-init
    echo "🏗️  인프라 자동 배포 중..."
    cd infra/terraform && terraform apply -auto-approve
    echo "✅ 인프라 배포 완료"
    @just terraform-output

# 인프라 삭제
[group('terraform')]
@terraform-destroy:
    echo "🗑️  인프라 삭제 중..."
    cd infra/terraform && terraform destroy
    echo "✅ 인프라 삭제 완료"

# 인프라 삭제 (자동 승인)
[group('terraform')]
@terraform-destroy-auto:
    echo "🗑️  인프라 자동 삭제 중..."
    cd infra/terraform && terraform destroy -auto-approve
    echo "✅ 인프라 삭제 완료"

# Terraform 출력값 확인
[group('terraform')]
@terraform-output:
    echo "📊 Terraform 출력값:"
    cd infra/terraform && terraform output

# Terraform 상태 확인
[group('terraform')]
@terraform-state:
    echo "📊 Terraform 상태:"
    cd infra/terraform && terraform state list

# Terraform 포맷팅
[group('terraform')]
@terraform-fmt:
    echo "🎨 Terraform 코드 포맷팅 중..."
    cd infra/terraform && terraform fmt -recursive
    echo "✅ 포맷팅 완료"

# Terraform 검증
[group('terraform')]
@terraform-validate:
    echo "✔️  Terraform 코드 검증 중..."
    cd infra/terraform && terraform validate
    echo "✅ 검증 완료"

# =================================
# Ansible 관련 명령
# =================================

# Ansible 환경 설정 (새로운 환경)
[group('ansible')]
@ansible-init:
    echo "🔧 Ansible 환경 초기화 중..."
    cd infra/ansible && uv init
    cd infra/ansible && uv add ansible ansible-core
    echo "✅ Ansible 환경 설정 완료"

# Ansible 의존성 설치 (기존 환경)
[group('ansible')]
@ansible-sync:
    echo "📦 Ansible 의존성 설치 중..."
    cd infra/ansible && uv sync
    echo "✅ Ansible 의존성 설치 완료"

# Ansible 버전 확인
[group('ansible')]
@ansible-version:
    echo "📋 Ansible 버전 확인:"
    cd infra/ansible && uv run ansible --version

# 연결 테스트
[group('ansible')]
@ansible-ping:
    echo "🔍 Ansible 연결 테스트 중..."
    cd infra/ansible && uv run ansible all -m ping

# 인벤토리 확인
[group('ansible')]
@ansible-inventory:
    echo "📋 Ansible 인벤토리 확인:"
    cd infra/ansible && uv run ansible-inventory --list

# NFS 서버 설정
[group('ansible')]
@ansible-setup-nfs-server:
    echo "💾 NFS 서버 설정 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-nfs-server.yml --limit storage
    echo "✅ NFS 서버 설정 완료"

# Kubernetes 노드 설정
[group('ansible')]
@ansible-setup-k8s-nodes:
    echo "☸️  Kubernetes 노드 설정 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-k8s-nodes.yml --limit k8s_cluster
    echo "✅ Kubernetes 노드 설정 완료"

# Kubernetes 클러스터 설정
[group('ansible')]
@ansible-setup-k8s-cluster:
    echo "☸️  Kubernetes 클러스터 설정 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-k8s-cluster.yml --limit k8s_cluster
    echo "✅ Kubernetes 클러스터 설정 완료"

# Kubernetes 클러스터 설치만
[group('ansible')]
@ansible-k8s-install:
    echo "📦 Kubernetes 패키지 설치 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "install"
    echo "✅ Kubernetes 패키지 설치 완료"

# Kubernetes 클러스터 초기화만
[group('ansible')]
@ansible-k8s-init:
    echo "🚀 Kubernetes 클러스터 초기화 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "init"
    echo "✅ Kubernetes 클러스터 초기화 완료"

# Kubernetes 노드 조인만
[group('ansible')]
@ansible-k8s-join:
    echo "🔗 Kubernetes 노드 조인 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "join"
    echo "✅ Kubernetes 노드 조인 완료"

# GPU 노드 작업만
[group('ansible')]
@ansible-k8s-gpu:
    echo "🎮 GPU 노드 작업 중..."
    cd infra/ansible && uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "gpu"
    echo "✅ GPU 노드 작업 완료"

# NFS 서버 상태 확인
[group('ansible')]
@ansible-nfs-status:
    echo "📊 NFS 서버 상태 확인:"
    cd infra/ansible && uv run ansible storage -m shell -a "systemctl status nfs-kernel-server"

# 그룹별 연결 테스트
[group('ansible')]
@ansible-ping-groups:
    echo "🔍 그룹별 연결 테스트:"
    echo "Kubernetes 클러스터:"
    cd infra/ansible && uv run ansible k8s_cluster -m ping
    echo "GPU 노드:"
    cd infra/ansible && uv run ansible gpu_nodes -m ping
    echo "인프라 서비스:"
    cd infra/ansible && uv run ansible infrastructure -m ping
    echo "Storage 서버:"
    cd infra/ansible && uv run ansible storage -m ping

# =================================
# SSH 접속 명령
# =================================

# 마스터 노드 접속
[group('ssh')]
@ssh-master:
    echo "🖥️  마스터 노드 접속 중..."
    ssh -i {{key_path}} ubuntu@$(cd infra/terraform && terraform output -raw master_external_ip)

# 워커 노드 접속 (인덱스 지정: 0, 1, 2)
[group('ssh')]
ssh-worker index="0":
    echo "🖥️  워커 노드 {{index}} 접속 중..."
    ssh -i {{key_path}} ubuntu@$(cd infra/terraform && terraform output -json worker_external_ips | jq -r '.[{{index}}]')

# 모든 노드 IP 확인
[group('ssh')]
@list-nodes:
    echo "📋 노드 IP 목록:"
    echo "Master:"
    echo "  - $(cd infra/terraform && terraform output -raw master_external_ip)"
    echo "Workers:"
    cd infra/terraform && terraform output -json worker_external_ips | jq -r '.[] | "  - " + .'

# =================================
# 전체 워크플로우
# =================================

# 전체 GCP 설정 (초기 한 번만)
[group('workflow')]
@setup-gcp: gcp-init gcp-create-sa gcp-create-key
    echo "✅ GCP 설정 완료"

# 전체 인프라 구성 (Terraform만)
[group('workflow')]
@deploy: setup-gcp terraform-apply-auto
    echo "✅ 전체 인프라 구성 완료"

# 전체 K8s 클러스터 구성 (Terraform + Ansible)
[group('workflow')]
@deploy-k8s: deploy ansible-setup-nfs-server ansible-setup-k8s-nodes ansible-setup-k8s-cluster
    echo "✅ 전체 K8s 클러스터 구성 완료"

# Ansible 환경 준비
[group('workflow')]
@setup-ansible: ansible-sync ansible-ping
    echo "✅ Ansible 환경 준비 완료"

# 전체 인프라 정리
[group('workflow')]
@cleanup: terraform-destroy-auto
    echo "✅ 인프라 정리 완료"

# 상태 확인
[group('workflow')]
@status: terraform-state list-nodes
    echo "✅ 상태 확인 완료"

# =================================
# 유틸리티
# =================================

# 환경 변수 확인
[group('utils')]
@env:
    echo "🔧 현재 환경 변수:"
    echo "PROJECT_ID: {{project_id}}"
    echo "REGION: {{region}}"
    echo "ZONE: {{zone}}"
    echo "KEY_NAME: {{key_name}}"
    echo "KEY_PATH: {{key_path}}"

# 의존성 확인
[group('utils')]
@check:
    echo "🔍 의존성 확인 중..."
    @command -v gcloud > /dev/null || echo "❌ gcloud CLI가 설치되지 않았습니다"
    @command -v terraform > /dev/null || echo "❌ Terraform이 설치되지 않았습니다"
    @command -v jq > /dev/null || echo "❌ jq가 설치되지 않았습니다"
    @echo "✅ 의존성 확인 완료"