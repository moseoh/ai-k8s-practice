# Kubernetes 클러스터 구성 (Ansible)

## 개요

이 폴더는 **Terraform으로 생성된 GCP 인스턴스에 Kubernetes 클러스터를 자동화 구성**하는 Ansible 플레이북을 포함합니다.

### 목적
- **자동화된 K8s 클러스터 구성**: 수동 설정 과정을 자동화하여 일관성 있는 클러스터 구축
- **Configuration as Code**: 클러스터 설정을 코드로 관리하여 재현 가능한 환경 구성
- **멱등성 보장**: 반복 실행 시에도 동일한 결과를 보장하는 안정적인 구성

### 전체 워크플로우에서의 역할
```
1. Terraform → GCP 인프라 구성 (VM, 네트워크, 방화벽)
2. Ansible (이 폴더) → Kubernetes 소프트웨어 설치 및 클러스터 구성
3. 실습 환경 → Kubernetes 학습 및 실습
```

## 구성 요소

### Playbook 구조
- **setup-k8s-nodes.yml**: Kubernetes 노드 기본 환경 구성
- **setup-nfs-server.yml**: NFS 서버 설정 (Persistent Volume용)
- **setup-k8s-cluster.yml**: Kubernetes 클러스터 초기화 및 구성

### 설치 및 구성 내용
- **시스템 환경**: 커널 모듈, sysctl, swap 비활성화
- **컨테이너 런타임**: containerd 설치 및 구성
- **Kubernetes**: kubeadm, kubelet, kubectl 설치
- **클러스터**: Master 초기화, Worker 조인, 네트워크 플러그인
- **스토리지**: NFS 서버 구성 및 Persistent Volume 지원

## 사전 요구사항

- [Terraform](../terraform/README.md)으로 인프라가 이미 배포되어 있어야 함
- uv 설치

## Ansible 환경 설정

### 방법 1: 새로운 환경에서 시작하는 경우

```shell
# uv로 새 프로젝트 초기화
uv init
# 프로젝트명 변경 (패키지명 충돌 방지)
# pyproject.toml에서 name = "ansible" → name = "k8s-ansible"

# Ansible 패키지 설치
uv add ansible ansible-core

# 설치 확인
uv run ansible --version
```

### 방법 2: 기존 레포지토리를 사용하는 경우

```shell
# 기존 의존성 설치 (레포지토리 클론 후)
uv sync

# 설치 확인
uv run ansible --version
```

> **참고**: 이후 모든 ansible 명령어는 `uv run`을 사용합니다. 가상환경을 별도로 활성화할 필요 없습니다.

## 인벤토리 구성

`./inventory/hosts.yml`에서 실제 IP 주소로 업데이트 후 연결 테스트:

```shell
# 연결 테스트
uv run ansible all -m ping

# 인벤토리 확인
uv run ansible-inventory --list
```

## Playbook 실행 가이드

### 1단계: 노드 준비

#### Kubernetes 노드 기본 환경 구성
```shell
# 전체 Kubernetes 클러스터 기본 환경 준비
uv run ansible-playbook playbooks/setup-k8s-nodes.yml --limit k8s_cluster
```

**포함되는 작업:**
- 호스트명 설정 및 네트워크 확인
- 필수 커널 모듈 로드 (overlay, br_netfilter)
- sysctl 파라미터 설정, swap 비활성화
- containerd 설치 및 구성
- kubeadm, kubelet, kubectl 설치

### 2단계: NFS 서버 설정
Persistent Volume으로 사용할 NFS 서버를 설정합니다.

```shell
# 연결 테스트 (SSH agent 사용)
uv run ansible storage -m ping

# NFS 서버 설정
uv run ansible-playbook playbooks/setup-nfs-server.yml --limit storage

# 서비스 상태 확인
uv run ansible storage -m shell -a "systemctl status nfs-kernel-server"
```

**포함되는 작업:**
- NFS 서버 패키지 설치 및 구성
- 공유 디렉토리 생성 및 권한 설정
- NFS exports 설정
- 방화벽 규칙 구성

### 3단계: Kubernetes 클러스터 구성
```shell
# 통합 Kubernetes 클러스터 설치 및 구성
uv run ansible-playbook playbooks/setup-k8s-cluster.yml --limit k8s_cluster
```

**포함되는 작업:**
- Master 노드 클러스터 초기화 (kubeadm init)
- kubeconfig 설정 및 kubectl 구성
- CNI 네트워크 플러그인 설치 (Calico)
- Worker 노드 클러스터 조인
- 클러스터 상태 확인 및 검증

**주의사항:**
- 1단계 노드 준비가 완료된 후 실행해야 함
- Master 노드가 먼저 초기화된 후 Worker 노드들이 조인함

## 그룹별 관리

```shell
# 전체 인벤토리 확인
uv run ansible-inventory --list

# 그룹별 연결 테스트
uv run ansible k8s_cluster -m ping      # Kubernetes 클러스터
uv run ansible infrastructure -m ping   # 인프라 서비스
uv run ansible storage -m ping          # NFS 서버
```

## 설정 파일 구조

```
ansible/
├── pyproject.toml              # uv 프로젝트 설정
├── ansible.cfg                 # Ansible 기본 설정
├── inventory/
│   ├── hosts.yml              # 역할 기반 인벤토리
│   └── update_inventory.sh     # Terraform 출력 자동 업데이트
├── playbooks/
│   ├── setup-k8s-nodes.yml     # Kubernetes 노드 기본 환경 구성
│   ├── setup-nfs-server.yml    # NFS 서버 설정
│   └── setup-k8s-cluster.yml   # K8s 클러스터 초기화 및 구성
```