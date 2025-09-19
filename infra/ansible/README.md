# Kubernetes 클러스터 구성

Ansible을 사용한 Kubernetes 클러스터 자동화 구성

## 1. 사전 요구사항

- [Terraform](../terraform/README.md)으로 인프라가 이미 배포되어 있어야 함
- uv 설치

## 2. Ansible 환경 설정

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

## 3. 인벤토리 구성

`./inventory/hosts.yml`에서 실제 IP 주소로 업데이트 후 연결 테스트:

```shell
# 연결 테스트
uv run ansible all -m ping

# 인벤토리 확인
uv run ansible-inventory --list
```

## 4. Playbook 실행

### 1단계: 노드 준비

#### 일반 노드 준비
```shell
# 전체 Kubernetes 클러스터 준비
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --limit k8s_cluster
```
**📖 상세 문서**: [Kubernetes 노드 준비](docs/prepare-k8s-nodes.md)

#### GPU 노드 준비 (선택사항)
```shell
# GPU 노드 전용 준비
uv run ansible-playbook playbooks/prepare-gpu-nodes.yml --limit gpu_nodes
```

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

**📖 상세 문서**: [NFS 서버 설정](docs/setup-nfs-server.md)

### 3단계: Kubernetes 클러스터 구성
```shell
# 통합 Kubernetes 클러스터 설치 및 구성
uv run ansible-playbook playbooks/setup-k8s-cluster.yml --limit k8s_cluster

# 특정 작업만 실행 (태그 사용)
uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "install"    # 패키지 설치만
uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "init"      # 클러스터 초기화만
uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "join"      # 노드 조인만
uv run ansible-playbook playbooks/setup-k8s-cluster.yml --tags "gpu"       # GPU 노드 작업만
```
**📖 상세 문서**: [Kubernetes 클러스터 설치](docs/setup-k8s-cluster.md)

## 5. 그룹별 관리

```shell
# 전체 인벤토리 확인
uv run ansible-inventory --list

# 그룹별 연결 테스트
uv run ansible k8s_cluster -m ping      # Kubernetes 클러스터
uv run ansible gpu_nodes -m ping        # GPU 노드
uv run ansible infrastructure -m ping   # 인프라 서비스
uv run ansible storage -m ping          # NFS 서버
```

## 6. 설정 파일 구조

```
ansible/
├── pyproject.toml              # uv 프로젝트 설정
├── ansible.cfg                 # Ansible 기본 설정
├── inventory/
│   ├── hosts.yml              # 역할 기반 인벤토리
│   └── update_inventory.sh     # Terraform 출력 자동 업데이트
├── playbooks/
│   ├── prepare-k8s-nodes.yml   # Kubernetes 노드 준비
│   ├── prepare-gpu-nodes.yml   # GPU 노드 전용 준비
│   ├── setup-nfs-server.yml    # NFS 서버 설정
│   └── setup-k8s-cluster.yml   # K8s 클러스터 통합 설치
└── docs/                       # 상세 문서
    ├── prepare-k8s-nodes.md    # K8s 노드 준비 가이드
    ├── setup-nfs-server.md     # NFS 서버 설정 가이드
    └── setup-k8s-cluster.md    # K8s 클러스터 설치 가이드
```