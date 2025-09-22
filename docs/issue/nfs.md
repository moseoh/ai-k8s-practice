# NFSv4 설정 이슈

## 1. 환경 정보

### 시스템 환경

* **OS**: Ubuntu 24.04 LTS (로컬 서버)
* **IP**: Internal: 192.168.0.101, External: 218.55.125.24

---

## 2. 문제 상황

### 2.1 초기 증상

NFS 서버를 구성한 뒤 `showmount -e` 명령으로 export 목록을 확인하려 했으나 결과가 비어 있음:

```bash
$ showmount -e localhost
Export list for localhost:
```

또한 클라이언트에서 마운트 시도 시 오류 발생:

```bash
mount_nfs: can't mount /srv/k8s from 192.168.0.101: Operation not permitted
```

---

## 3. 원인 분석

### 3.1 NFSv3와 NFSv4 동작 차이

* `showmount` 명령은 **rpcbind/portmapper** 기반으로 동작하는 **NFSv3 이하 전용 도구**임.
* **NFSv4-only 환경**에서는 `showmount -e` 결과가 비어 있는 것이 정상.

### 3.2 포트 사용 차이

* **NFSv3**: 여러 포트를 사용 (2049 외에 mountd, statd, lockd 등). 여기에 더해 **동적 포트**까지 활용하기 때문에 방화벽 관리가 매우 복잡함.
* **NFSv4**: **2049/TCP 단일 포트만 사용** → 방화벽 관리가 간단하고 명확함.

### 3.3 root export 문제

* NFSv4에서는 반드시 `fsid=0` root export가 필요함.
* 이를 지정하지 않으면 클라이언트에서 "invalid file system" 오류 발생.

---

## 4. 해결 방안

### 4.1 `/etc/exports` 수정

```bash
/srv/k8s 192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=0)
```

### 4.2 서버 적용

```bash
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

### 4.3 클라이언트 마운트 확인 (MacOS)

```bash
sudo mkdir -p ~/nfs-test
sudo mount -t nfs -o vers=4,resvport 192.168.0.101:/srv/k8s ~/nfs-test
```

정상 마운트 후 파일 생성 테스트:

```bash
sudo touch ~/nfs-test/hello.txt
```

---

## 5. 결과

* NFSv4-only 모드에서 `showmount` 결과가 비어 있는 것은 정상 동작임을 확인.
* root export(`fsid=0`)를 추가하여 클라이언트 마운트 문제 해결.
* 방화벽은 2049/TCP만 열면 충분하며, v3 대비 관리가 훨씬 단순함.

---

## 참고 자료

* [Ubuntu 공식 문서 - NFS 설치](https://documentation.ubuntu.com/server/how-to/networking/install-nfs/)
* [NFSv4 설계 개요 (RFC 3530)](https://www.rfc-editor.org/rfc/rfc3530)
