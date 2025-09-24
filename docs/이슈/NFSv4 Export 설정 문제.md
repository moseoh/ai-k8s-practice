## 환경 정보

### 시스템 환경

- **OS**: Ubuntu 24.04 LTS (로컬 서버)
- **네트워크**: Internal IP 192.168.0.101, External IP 218.55.125.24
- **서비스**: NFS 서버 (nfs-kernel-server)
- **클라이언트**: macOS (NFSv4 클라이언트)

---

## 문제 상황 분석

### 초기 증상

**발견 시점**: NFS 서버 구성 완료 후 export 목록 확인 시

**에러 현상**:
1. `showmount -e localhost` 명령 결과가 비어있음
2. 클라이언트 마운트 시도 실패

```bash
$ showmount -e localhost
Export list for localhost:
```

**클라이언트 마운트 오류**:
```bash
mount_nfs: can't mount /srv/k8s from 192.168.0.101: Operation not permitted
```

**영향 범위**: NFS 클라이언트에서 서버 디렉토리 접근 불가

### 예상 동작 vs 실제 동작

**예상**: `showmount -e` 명령으로 export된 디렉토리 목록 확인 가능
**실제**: 빈 결과 반환, 클라이언트에서 "Operation not permitted" 오류 발생

---

## 원인 조사 과정

### 1. 초기 진단

#### 시스템 상태 확인

**NFS 서비스 상태**:
- `nfs-kernel-server` 서비스 정상 동작 중
- 2049/TCP 포트 정상 바인딩

**설정 검증**:
- `/etc/exports` 파일 존재 및 디렉토리 export 설정 확인

### 2. 근본 원인 도출

#### NFSv3 vs NFSv4 동작 차이 분석

**핵심 발견**:
- `showmount` 명령은 **rpcbind/portmapper 기반** NFSv3 이하 전용 도구
- **NFSv4-only 환경**에서 `showmount -e` 결과가 비어있는 것은 **정상 동작**

#### 포트 사용 패턴 차이

| 구분 | NFSv3 | NFSv4 |
|------|-------|-------|
| **포트** | 2049 + mountd/statd/lockd + 동적 포트 | **2049/TCP 단일 포트** |
| **방화벽** | 복잡한 다중 포트 관리 | 간단한 단일 포트 |
| **관리성** | 매우 복잡 | 명확하고 단순 |

#### Root Export 문제 식별

**문제**: NFSv4에서는 반드시 `fsid=0` root export 필요
**결과**: root export 미설정 시 "invalid file system" 오류 발생

---

## 해결 방안 적용

### 근본 해결 (Permanent Fix)

#### 해결 방안

NFSv4 root export 설정을 통한 근본적 문제 해결

#### 구현 단계

**1단계: /etc/exports 수정**
```bash
/srv/k8s 192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=0)
```

**핵심 변경사항**:
- `fsid=0` 추가 → NFSv4 root export 지정
- 클라이언트 네트워크 범위: `192.168.0.0/24`
- 권한: 읽기/쓰기, root 접근 허용

**2단계: 서버 설정 적용**
```bash
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

**3단계: 클라이언트 마운트 테스트 (macOS)**
```bash
sudo mkdir -p ~/nfs-test
sudo mount -t nfs -o vers=4,resvport 192.168.0.101:/srv/k8s ~/nfs-test
```

#### 검증 결과

**마운트 성공 확인**:
```bash
sudo touch ~/nfs-test/hello.txt
ls -la ~/nfs-test/
```

✅ 파일 생성 및 권한 확인 정상
✅ 클라이언트-서버 간 읽기/쓰기 동작 정상

---

## 사후 분석 및 개선

### 핵심 교훈

**기술적 교훈**:
- NFSv4 환경에서 `showmount` 결과가 비어있는 것은 **정상 동작**
- NFSv4는 `fsid=0` root export 필수 설정
- 포트 관리 측면에서 NFSv4가 NFSv3 대비 현저히 단순함

**프로세스 교훈**:
- NFS 버전별 특성을 사전에 이해하고 문제를 판단해야 함
- Legacy 도구(`showmount`)와 현대 프로토콜(NFSv4) 간 호환성 고려 필요

### 예방 방안

**설정 표준화**:
- NFSv4 환경에서 root export(`fsid=0`) 필수 포함
- 클라이언트별 마운트 명령어 문서화

**모니터링 개선**:
- NFSv4 전용 상태 확인 방법 적용
- `showmount` 대신 실제 마운트 테스트로 검증

---

## 참고 자료

### 공식 문서

- [Ubuntu 공식 문서 - NFS 설치](https://documentation.ubuntu.com/server/how-to/networking/install-nfs/) - NFSv4 설정 가이드
- [NFSv4 설계 개요 (RFC 3530)](https://www.rfc-editor.org/rfc/rfc3530) - 프로토콜 명세