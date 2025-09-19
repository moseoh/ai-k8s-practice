# NFS Server Setup

Ubuntu 기반 NFS 서버를 Kubernetes 클러스터용 Persistent Volume 스토리지로 구성하는 가이드입니다.

## 개요

- **서버**: nfs-server (192.168.0.101)
- **공유 디렉토리**: `/srv/k8s`
- **접근 허용**: K8s 클러스터 노드 + 로컬 네트워크 (192.168.0.0/24)
- **기반 문서**: [Ubuntu NFS Installation Guide](https://documentation.ubuntu.com/server/how-to/networking/install-nfs)

## 실행 방법

### 1. 연결 테스트

```bash
# NFS 서버 연결 확인
cd ansible
uv run ansible nfs-server -m ping

# storage 그룹 전체 확인
uv run ansible storage -m ping
```

### 2. NFS 서버 설치 및 구성

```bash
# 전체 설치 및 구성
uv run ansible-playbook playbooks/setup-nfs-server.yml

# 실행 계획 확인 (dry-run)
uv run ansible-playbook playbooks/setup-nfs-server.yml --check

# 자세한 출력
uv run ansible-playbook playbooks/setup-nfs-server.yml -v
```

## 구성 상세

### 설치 패키지

- `nfs-kernel-server`: Ubuntu NFS 서버 패키지

### 공유 디렉토리

- 경로: `/srv/k8s`
- 소유자: `nobody:nogroup`
- 권한: `777`
- 용도: Kubernetes Persistent Volume 데이터 저장

### NFS Exports 설정

```
/srv/k8s <client-ip>(rw,sync,no_subtree_check,no_root_squash)    # control-plane
```

#### 옵션 설명

- `rw`: 읽기/쓰기 권한
- `sync`: 동기 쓰기 (데이터 무결성 보장)
- `no_subtree_check`: 성능 향상
- `no_root_squash`: 컨테이너의 root 권한 유지

### 방화벽 설정 (UFW)

> NFSv4 의 경우 2049 포트 하나로 서비스 가능. v3, v2 의 경우 추가적인 포트 + 동적 포트들이 있어 구성이 어렵다.
> 
> nfs server의 경우 명시적으로 지정하지 않은 한 모든 버전을 제공하며,\
> nfs client의 경우 기본적으로 최신 버전으로 통신하지만 v4 를 명시하는 것이 좋다.

| 포트   | 프로토콜 | 서비스 |
|------|------|-----|
| 2049 | TCP  | NFS |

