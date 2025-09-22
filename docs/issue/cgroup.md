# cgroup 설정 이슈

## 1. 환경 정보

### 시스템 환경
- **OS**: Ubuntu 22.04 LTS (GCP VM)
- **Kubernetes**: v1.34.1
- **Container Runtime**: containerd v1.x
- **CRI Socket**: `/run/containerd/containerd.sock`
- **Pod Network CIDR**: 10.244.0.0/16

### 인프라 구성
- Control Plane: 1대 (k8s-control-plane-1)
- Worker Node: 3대 (k8s-node-1, k8s-node-2, k8s-node-3)

## 2. 문제 상황

### 2.1 초기 증상
`kubeadm init` 실행 시 control plane 컴포넌트 health check 단계에서 진행이 멈추는 현상 발생:

```
[control-plane-check] Waiting for healthy control plane components. This can take up to 4m0s
[control-plane-check] Checking kube-apiserver at https://10.240.0.10:6443/livez
[control-plane-check] Checking kube-controller-manager at https://127.0.0.1:10257/healthz
[control-plane-check] Checking kube-scheduler at https://127.0.0.1:10259/livez
[control-plane-check] kube-apiserver is not healthy after 4m0.000263022s
[control-plane-check] kube-controller-manager is not healthy after 4m0.000358394s
[control-plane-check] kube-scheduler is not healthy after 4m0.000758212s
```

### 2.2 근본 원인 분석

#### 컨테이너 미생성 확인
Static Pod 매니페스트는 생성되었으나 실제 컨테이너가 하나도 시작되지 않음:

```bash
ubuntu@k8s-control-plane-1:~$ ls -la /etc/kubernetes/manifests/
total 24
drwxrwxr-x 2 root root 4096 Sep 18 15:44 .
drwxrwxr-x 4 root root 4096 Sep 18 15:44 ..
-rw------- 1 root root 2612 Sep 18 15:44 etcd.yaml
-rw------- 1 root root 3949 Sep 18 15:44 kube-apiserver.yaml
-rw------- 1 root root 3458 Sep 18 15:44 kube-controller-manager.yaml
-rw------- 1 root root 1726 Sep 18 15:44 kube-scheduler.yaml

ubuntu@k8s-control-plane-1:~$ sudo crictl ps -a
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID
```

#### CGroup Driver 불일치
kubelet 로그에서 cgroup driver 관련 문제 확인:

```
E0918 15:44:04.244173   57437 log.go:32] "RuntimeConfig from runtime service failed" err="rpc error: code = Unimplemented"
I0918 15:44:04.244283   57437 kubelet.go:1400] "CRI implementation should be updated to support RuntimeConfig. Falling back"
```

kubelet 설정 확인 시 `cgroupfs`로 설정됨:
```json
"CgroupDriver":"cgroupfs"
```

반면 containerd는 `SystemdCgroup = true`로 설정되어 있어 불일치 발생.

## 3. 원인 분석

### 3.1 Kubernetes 1.34의 CGroup Driver 자동 감지 메커니즘

Kubernetes 공식 문서에 따르면:

> Kubernetes 1.34에서는 `KubeletCgroupDriverFromCRI` 기능 게이트가 활성화되어 있고 CRI RPC를 지원하는 컨테이너 런타임이 있는 경우 `RuntimeConfig`, kubelet이 런타임에서 적절한 cgroup 드라이버를 자동으로 감지하고 `cgroupDriver` kubelet 구성 내의 설정을 무시합니다.

### 3.2 Containerd v1.x의 제약사항

> 그러나 이전 버전의 컨테이너 런타임(특히 containerd 1.y 이하)은 `RuntimeConfig` CRI RPC를 지원하지 않으며 이 쿼리에 올바르게 응답하지 않을 수 있습니다. 따라서 Kubelet은 자체 플래그의 값을 사용합니다 `--cgroup-driver`.

### 3.3 향후 버전의 변경사항

> Kubernetes 1.36에서는 이러한 대체 동작이 삭제되고, 이전 버전의 containerd는 최신 kubelet에서 실패하게 됩니다.

## 4. 해결 방안

### 4.1 단기 해결방안 (Containerd v1.x 환경)

kubeadm 설정 파일을 통한 명시적 cgroup driver 지정:

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

실행 명령:
```bash
sudo kubeadm init --config=kubeadm-config.yaml
```

### 4.2 장기 해결방안 (Containerd v2.x 업그레이드)

Kubernetes 1.36 이상 버전 호환성을 위해 containerd v2.x로 업그레이드 권장.\
본 환경에서는 공식 문서 가이드를 참고해 containerd를 바이너리로 설치했고, runc 까지는 필요해여 `apt`로 추가 설치한다. (CNI는 추후 Calico 사용)

```bash
# Containerd 2.x 바이너리 설치 (curl 사용)
VER=2.1.4
ARCH=amd64
curl -LO https://github.com/containerd/containerd/releases/download/v${VER}/containerd-${VER}-linux-${ARCH}.tar.gz
sudo tar Cxzvf /usr/local containerd-${VER}-linux-${ARCH}.tar.gz

# systemd 서비스 유닛 등록
sudo curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service \
  -o /etc/systemd/system/containerd.service
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

# runc 설치 (apt 사용)
sudo apt-get update
sudo apt-get install -y runc

# 확인
containerd --version
runc --version
```

## 5. 적용된 해결 방법

### 5.1 Ansible Playbook 수정

`setup-k8s-cluster.yml`에 kubeadm 설정 파일 생성 단계 추가:

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

### 5.2 결과

설정 파일을 통한 명시적 cgroup driver 지정 후 클러스터 초기화 성공:
- containerd와 kubelet 모두 systemd cgroup driver 사용
- Control plane 컴포넌트 정상 시작
- 클러스터 초기화 완료

## 참고 자료

- [Kubernetes 공식 문서 - Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Containerd Getting Started Guide](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)
- [Kubernetes 1.34 Release Notes - CGroup Driver](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers)

---
