# Kubernetes 노드 준비 (prepare-k8s-nodes.yml)

kubeadm을 사용한 Kubernetes 클러스터 구축 전에 필요한 모든 노드의 사전 준비 작업을 수행하는 Playbook입니다.

## 대상 호스트

- **그룹**: `k8s_cluster` (control_plane + nodes + gpu_nodes)
- **권한**: `become: yes` (sudo 필요)

## 실행 방법

### 전체 클러스터 준비
```shell
# 실행 계획 확인 (Dry-run)
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --check

# 전체 Kubernetes 클러스터 준비
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --limit k8s_cluster
```

### 특정 그룹만 실행
```shell
# 제어 평면 노드만
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --limit control_plane

# 워커 노드만
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --limit nodes

# GPU 노드만 (추가된 경우)
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --limit gpu_nodes
```

### 특정 작업만 실행 (태그 사용)
```shell
# Swap 관련 작업만
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --tags "swap"

# 커널 모듈 관련 작업만
uv run ansible-playbook playbooks/prepare-k8s-nodes.yml --tags "kernel"
```

## 수행 작업 상세

### 1. 시스템 업데이트
- **APT 패키지 캐시 업데이트**
- **필수 패키지 설치**:
  - `apt-transport-https`: HTTPS를 통한 패키지 다운로드
  - `ca-certificates`: SSL 인증서
  - `curl`: HTTP 클라이언트
  - `gnupg`: GPG 키 관리
  - `lsb-release`: OS 버전 정보
  - `software-properties-common`: APT 저장소 관리

### 2. Kubernetes 준비 작업

#### Swap 메모리 비활성화
- **즉시 비활성화**: `swapoff -a` 실행
- **영구 비활성화**: `/etc/fstab`에서 swap 항목 주석처리
- **이유**: Kubernetes는 swap이 활성화된 환경에서 실행되지 않음

#### 커널 모듈 로드
- **overlay**: Container 오버레이 파일시스템
- **br_netfilter**: Bridge 네트워크 필터링
- **영구 설정**: `/etc/modules-load.d/k8s.conf` 파일 생성

#### sysctl 매개변수 설정
- **net.bridge.bridge-nf-call-iptables = 1**: Bridge 트래픽이 iptables 규칙을 통과하도록 설정
- **net.bridge.bridge-nf-call-ip6tables = 1**: IPv6 bridge 트래픽 설정
- **net.ipv4.ip_forward = 1**: IP 포워딩 활성화
- **설정 파일**: `/etc/sysctl.d/k8s.conf`

### 3. Container Runtime 설치 (containerd)

#### 저장소 설정
- **Docker GPG 키 추가**: 패키지 서명 검증
- **Docker 저장소 추가**: containerd 패키지 다운로드용

#### containerd 설치 및 구성
- **패키지 설치**: `containerd.io`
- **기본 설정 생성**: `containerd config default`
- **systemd cgroup driver 설정**:
  - `SystemdCgroup = true`로 변경
  - Kubernetes와 일관성 있는 cgroup 관리

#### 서비스 활성화
- **containerd 서비스 시작 및 활성화**
- **부팅 시 자동 시작 설정**

### 4. 네트워크 및 시스템 설정

#### 호스트명 설정
- **각 노드의 호스트명을 inventory 이름으로 설정**
- 예: `k8s-control-plane-1`, `k8s-node-1`

#### /etc/hosts 파일 업데이트
- **클러스터 내 모든 노드의 IP와 호스트명 매핑 추가**
- 노드 간 이름 해석 지원

#### 방화벽 임시 비활성화
- **ufw 서비스 중지 및 비활성화** (테스트 환경용)
- 프로덕션 환경에서는 필요한 포트만 개방 권장

### 5. 검증 및 알림

#### 재부팅 필요 확인
- `/var/run/reboot-required` 파일 존재 확인
- 커널 업데이트 등으로 재부팅이 필요한 경우 알림

#### 준비 완료 메시지
- 모든 작업 완료 후 상태 요약 표시

## 주의사항

### 보안 고려사항
- **방화벽 비활성화**: 현재 설정은 테스트 환경용
- **프로덕션 환경**: 필요한 포트만 선별적으로 개방 필요

### 필수 포트 (프로덕션용 참고)
- **Control Plane**:
  - 6443: Kubernetes API Server
  - 2379-2380: etcd
  - 10250: kubelet API
  - 10251: kube-scheduler
  - 10252: kube-controller-manager

- **Worker Nodes**:
  - 10250: kubelet API
  - 30000-32767: NodePort Services

### 네트워크 요구사항
- **모든 노드 간 통신 가능**
- **인터넷 접속 가능** (패키지 다운로드용)
- **DNS 해상도 정상 작동**

## 문제 해결

### containerd 서비스 실패
```shell
# 서비스 상태 확인
uv run ansible k8s_cluster -m shell -a "systemctl status containerd"

# 로그 확인
uv run ansible k8s_cluster -m shell -a "journalctl -u containerd -f"

# 설정 파일 검증
uv run ansible k8s_cluster -m shell -a "containerd config dump"
```

### 커널 모듈 로드 실패
```shell
# 모듈 상태 확인
uv run ansible k8s_cluster -m shell -a "lsmod | grep -E '(overlay|br_netfilter)'"

# 수동 모듈 로드
uv run ansible k8s_cluster -m shell -a "modprobe overlay && modprobe br_netfilter"
```

### Swap 비활성화 확인
```shell
# Swap 상태 확인
uv run ansible k8s_cluster -m shell -a "swapon --show"

# 결과가 빈 출력이어야 함 (swap이 완전히 비활성화됨)
```

## 다음 단계

노드 준비가 완료되면 다음 작업을 진행할 수 있습니다:

1. **kubeadm, kubelet, kubectl 설치**
2. **Control Plane 초기화** (`kubeadm init`)
3. **Worker 노드 조인** (`kubeadm join`)
4. **CNI 플러그인 설치** (Calico, Flannel 등)

> **참고**: 이 Playbook은 노드 준비 작업만 수행합니다. 실제 Kubernetes 설치는 별도의 Playbook에서 진행됩니다.