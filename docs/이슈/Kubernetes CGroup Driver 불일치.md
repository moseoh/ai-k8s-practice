
## 환경 정보

**클러스터 구성**:
- Control Plane: 1대 (k8s-control-plane-1)
- Worker Node: 3대 (k8s-node-1~3)
- Network: 10.244.0.0/16 Pod CIDR

**시스템 환경**:
- OS: Ubuntu 22.04 LTS (GCP VM)
- Kubernetes: v1.34.1
- Container Runtime: containerd v1.x
- CRI Socket: `/run/containerd/containerd.sock`

---

## 문제 상황 분석

### 초기 증상

`kubeadm init` 실행 중 control plane 컴포넌트 health check 단계에서 4분간 대기 후 실패:

```
[control-plane-check] Waiting for healthy control plane components. This can take up to 4m0s
[control-plane-check] Checking kube-apiserver at https://10.240.0.10:6443/livez
[control-plane-check] Checking kube-controller-manager at https://127.0.0.1:10257/healthz
[control-plane-check] Checking kube-scheduler at https://127.0.0.1:10259/livez
[control-plane-check] kube-apiserver is not healthy after 4m0.000263022s
[control-plane-check] kube-controller-manager is not healthy after 4m0.000358394s
[control-plane-check] kube-scheduler is not healthy after 4m0.000758212s
```

**영향 범위**: 클러스터 초기화 완전 실패, 모든 컨트롤 플레인 컴포넌트 미작동

### 예상 동작 vs 실제 동작

- **예상**: kubeadm이 static pod 매니페스트를 생성하고 kubelet이 이를 감지하여 컨테이너 실행
- **실제**: 매니페스트 파일은 생성되었으나 실제 컨테이너가 하나도 시작되지 않음

---

## 원인 조사 과정

### 1. 초기 진단

#### Static Pod 매니페스트 확인

```bash
ubuntu@k8s-control-plane-1:~$ ls -la /etc/kubernetes/manifests/
total 24
drwxrwxr-x 2 root root 4096 Sep 18 15:44 .
drwxrwxr-x 4 root root 4096 Sep 18 15:44 ..
-rw------- 1 root root 2612 Sep 18 15:44 etcd.yaml
-rw------- 1 root root 3949 Sep 18 15:44 kube-apiserver.yaml
-rw------- 1 root root 3458 Sep 18 15:44 kube-controller-manager.yaml
-rw------- 1 root root 1726 Sep 18 15:44 kube-scheduler.yaml
```

*발견사항*: 매니페스트 파일이 정상적으로 생성됨

#### 컨테이너 상태 확인

```bash
ubuntu@k8s-control-plane-1:~$ sudo crictl ps -a
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID
```

*발견사항*: 매니페스트가 생성되었음에도 불구하고 실제 컨테이너가 하나도 실행되지 않음

#### 시스템 로그 분석

kubelet 로그에서 CGroup 관련 에러 확인:

```
E0918 15:44:04.244173   57437 log.go:32] "RuntimeConfig from runtime service failed" err="rpc error: code = Unimplemented"
I0918 15:44:04.244283   57437 kubelet.go:1400] "CRI implementation should be updated to support RuntimeConfig. Falling back"
```

*발견사항*: containerd가 RuntimeConfig CRI RPC를 지원하지 않아 kubelet이 fallback 모드로 전환

### 2. 심화 분석

#### CGroup Driver 설정 검증

kubelet 설정 확인:
```json
"CgroupDriver":"cgroupfs"
```

containerd 설정 확인:
```toml
SystemdCgroup = true
```

*발견사항*: kubelet(`cgroupfs`)과 containerd(`systemd`) 간 cgroup driver 불일치 발생

#### 근본 원인 도출

**Kubernetes 1.34의 CGroup Driver 자동 감지 메커니즘**:
- `KubeletCgroupDriverFromCRI` 기능 게이트 활성화로 런타임에서 자동 감지 시도
- containerd v1.x는 `RuntimeConfig` CRI RPC 미지원으로 자동 감지 실패
- kubelet이 자체 기본값(`cgroupfs`) 사용하나 containerd는 `systemd` 사용하여 불일치 발생

---

## 해결 방안 적용

### 1. 근본 해결 (Permanent Fix)

#### 해결 방안

kubeadm 설정 파일을 통한 명시적 cgroup driver 지정으로 불일치 해결

#### 구현 단계

1. **kubeadm 설정 파일 생성**:

```yaml
# kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16
controlPlaneEndpoint: "10.240.0.10:6443"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

2. **클러스터 초기화 재실행**:

```bash
sudo kubeadm reset --force
sudo kubeadm init --config=kubeadm-config.yaml
```

3. **Ansible Playbook 자동화 추가**:

```yaml
- name: kubeadm 설정 파일 생성
  ansible.builtin.copy:
    dest: /tmp/kubeadm-config.yaml
    content: |
      apiVersion: kubeadm.k8s.io/v1beta4
      kind: InitConfiguration
      nodeRegistration:
        criSocket: unix:///run/containerd/containerd.sock
      ---
      apiVersion: kubeadm.k8s.io/v1beta4
      kind: ClusterConfiguration
      networking:
        podSubnet: {{ pod_network_cidr }}
      controlPlaneEndpoint: "{{ ansible_default_ipv4.address }}:6443"
      ---
      apiVersion: kubelet.config.k8s.io/v1beta1
      kind: KubeletConfiguration
      cgroupDriver: systemd

- name: kubeadm init 실행 (설정 파일 사용)
  ansible.builtin.command: |
    kubeadm init --config=/tmp/kubeadm-config.yaml
```

#### 검증 결과

- ✅ containerd와 kubelet 모두 systemd cgroup driver 사용 확인
- ✅ Control plane 컴포넌트 정상 시작 확인
- ✅ 클러스터 초기화 완료

---

## 사후 분석 및 개선

### 핵심 교훈

**기술적 교훈**:
- Kubernetes 1.34의 자동 cgroup driver 감지 기능은 containerd v2.x 이상에서만 완전 지원
- 명시적 설정이 자동 감지보다 안정적인 환경 구성 보장
- CRI RPC 지원 여부가 kubelet과 container runtime 간 호환성에 중요한 영향

**프로세스 교훈**:
- 버전별 호환성 매트릭스 사전 검증 필요
- 로그 분석을 통한 근본 원인 규명이 문제 해결의 핵심
- Infrastructure as Code 접근으로 재현 가능한 환경 구성

### 예방 방안

1. **호환성 검증**: Kubernetes 버전 업그레이드 시 container runtime 버전 호환성 사전 확인
2. **명시적 설정**: cgroup driver 등 핵심 설정은 자동 감지에 의존하지 않고 명시적으로 지정
3. **버전 로드맵**: containerd v2.x 업그레이드를 통한 Kubernetes 1.36 대응 준비

### 모니터링 강화

- kubelet과 containerd 설정 불일치 감지 스크립트 추가
- 클러스터 초기화 과정의 각 단계별 검증 포인트 설정
- CRI RPC 지원 상태 모니터링 추가

---

## 참고 자료

### 공식 문서

- [Kubernetes 공식 문서 - Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) - kubeadm 설치 및 구성 가이드
- [Kubernetes 1.34 Release Notes - CGroup Driver](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers) - cgroup driver 자동 감지 기능 설명

### 내부 문서

- [Containerd Getting Started Guide](https://github.com/containerd/containerd/blob/main/docs/getting-started.md) - containerd v2.x 업그레이드 가이드
- Ansible Playbook: `setup-k8s-cluster.yml` - 자동화된 클러스터 구성