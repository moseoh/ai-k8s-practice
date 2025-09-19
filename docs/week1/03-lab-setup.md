# Kubernetes 실습환경 명세 - Ubuntu 22.04 + GCP + kubeadm

## 개요

이 문서는 **Kubernetes 클러스터 구축을 위한 기술 명세**를 제공합니다. 실제 구성은 [Terraform](../../infra/terraform/README.md)
과 [Ansible](../../infra/ansible/README.md)을 통해 자동화되어 있습니다.

## 목차

1. [시스템 요구사항](#시스템-요구사항)
2. [아키텍처 구성](#아키텍처-구성)
3. [소프트웨어 명세](#소프트웨어-명세)
4. [네트워크 명세](#네트워크-명세)
5. [보안 명세](#보안-명세)

---

## 시스템 요구사항

### 하드웨어 요구사항

[Kubernetes 공식 요구사항](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)
에 따른 최소 사양:

| 구성 요소   | Control Plane | Worker Node | 공식 문서 기준                                                                                                                       |
|---------|---------------|-------------|--------------------------------------------------------------------------------------------------------------------------------|
| **CPU** | 2 cores 이상    | 1 core 이상   | [System requirements](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin) |
| **메모리** | 2GB 이상        | 1GB 이상      | 실제 워크로드에 따라 추가 필요                                                                                                              |
| **디스크** | 20GB 이상       | 10GB 이상     | OS + container images + logs                                                                                                   |

### 실습 환경 구성 (GCP Compute Engine)

| 노드 타입             | 머신 타입    | CPU    | 메모리 | 디스크      | 수량 | 역할                 |
|-------------------|----------|--------|-----|----------|----|--------------------|
| **Control Plane** | e2-small | 2 vCPU | 2GB | 30GB SSD | 1개 | API 서버, etcd, 스케줄러 |
| **Worker**        | e2-small | 2 vCPU | 2GB | 30GB SSD | 3개 | Pod 실행             |

> **참고**: [GCP 머신 타입 문서](https://cloud.google.com/compute/docs/machine-types)

### 운영체제 요구사항

| 항목        | 사양                                 | 공식 문서                                                                                                                                         |
|-----------|------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| **OS**    | Ubuntu 22.04 LTS (Jammy Jellyfish) | [Supported OS](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl) |
| **아키텍처**  | x86_64 (amd64)                     | [Architecture support](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)               |
| **커널 버전** | 3.10+ 권장                           | Container runtime 호환성                                                                                                                         |

---

## 아키텍처 구성

### 클러스터 토폴로지

```
┌─────────────────────────────────────────────────────────────┐
│                    VPC: k8s-network                        │
│                 Subnet: 10.240.0.0/24                      │
├─────────────────────────────────────────────────────────────┤
│  Control Plane Node                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ k8s-master (10.240.0.10)                               ││
│  │ - kube-apiserver (6443)                                ││
│  │ - etcd (2379-2380)                                     ││
│  │ - kube-scheduler (10259)                               ││
│  │ - kube-controller-manager (10257)                      ││
│  │ - kubelet (10250)                                      ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  Worker Nodes                                               │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐│
│  │ k8s-worker-0    │ │ k8s-worker-1    │ │ k8s-worker-2    ││
│  │ (10.240.0.20)   │ │ (10.240.0.21)   │ │ (10.240.0.22)   ││
│  │ - kubelet       │ │ - kubelet       │ │ - kubelet       ││
│  │ - kube-proxy    │ │ - kube-proxy    │ │ - kube-proxy    ││
│  │ - containerd    │ │ - containerd    │ │ - containerd    ││
│  └─────────────────┘ └─────────────────┘ └─────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 구성 요소별 역할

#### Control Plane Components

- **kube-apiserver**: 모든 REST API 요청 처리 및 클러스터 상태 관리
- **etcd**: 클러스터 데이터 저장소 (key-value store)
- **kube-scheduler**: Pod 스케줄링 결정
- **kube-controller-manager**: 클러스터 수준 제어 기능

> **참고**: [Control Plane Components](https://kubernetes.io/docs/concepts/overview/components/#control-plane-components)

#### Worker Node Components

- **kubelet**: 각 노드에서 실행되는 기본 노드 에이전트
- **kube-proxy**: 네트워크 프록시 및 로드 밸런서
- **Container Runtime**: containerd (Docker 대체)

> **참고**: [Node Components](https://kubernetes.io/docs/concepts/overview/components/#node-components)

---

## 소프트웨어 명세

### 컨테이너 런타임

| 구성 요소          | 버전    | 설치 방식       | 공식 문서                                                                                                    |
|----------------|-------|-------------|----------------------------------------------------------------------------------------------------------|
| **containerd** | 2.1.4 | Binary 설치   | [containerd Getting Started](https://github.com/containerd/containerd/blob/main/docs/getting-started.md) |
| **runc**       | 1.2.5 | apt package | [Container Runtime Interface](https://kubernetes.io/docs/concepts/architecture/cri/)                     |

### Kubernetes 구성 요소

| 구성 요소       | 버전      | 설치 방식       | 공식 문서                                                                                                        |
|-------------|---------|-------------|--------------------------------------------------------------------------------------------------------------|
| **kubeadm** | v1.34.1 | apt package | [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) |
| **kubelet** | v1.34.1 | apt package | [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)                        |
| **kubectl** | v1.34.1 | apt package | [kubectl](https://kubernetes.io/docs/reference/kubectl/)                                                     |

### CNI 네트워크 플러그인

| 플러그인       | 버전      | CIDR          | 공식 문서                                                   |
|------------|---------|---------------|---------------------------------------------------------|
| **Calico** | v3.30.3 | 10.244.0.0/16 | [Calico Documentation](https://docs.projectcalico.org/) |

### 시스템 설정

| 항목                                     | 설정값  | 공식 문서 기준                                                                                                                            |
|----------------------------------------|------|-------------------------------------------------------------------------------------------------------------------------------------|
| **Swap**                               | 비활성화 | [Required: Disable swap](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#swap-configuration) |
| **br_netfilter**                       | 로드됨  |                                                                                                                                     |
| **net.bridge.bridge-nf-call-iptables** | 1    | iptables 브릿지 트래픽 처리                                                                                                                 |
| **net.ipv4.ip_forward**                | 1    | IP 포워딩 활성화                                                                                                                          |

---

## 네트워크 명세

### 필수 포트 요구사항

#### Control Plane Node

| 포트 범위     | 프로토콜 | 용도                      | 공식 문서                                                                                           |
|-----------|------|-------------------------|-------------------------------------------------------------------------------------------------|
| 6443      | TCP  | Kubernetes API server   | [Check required ports](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)    |
| 2379-2380 | TCP  | etcd server client API  | [etcd ports](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)              |
| 10250     | TCP  | Kubelet API             | [Kubelet port](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)            |
| 10259     | TCP  | kube-scheduler          | [Scheduler port](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)          |
| 10257     | TCP  | kube-controller-manager | [Controller manager port](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |

#### Worker Nodes

| 포트 범위       | 프로토콜 | 용도                | 공식 문서                                                                                  |
|-------------|------|-------------------|----------------------------------------------------------------------------------------|
| 10250       | TCP  | Kubelet API       | [Kubelet port](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)   |
| 30000-32767 | TCP  | NodePort Services | [NodePort range](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |

### 네트워크 구성

| 항목                  | CIDR/설정        | 용도                | 공식 문서                                                                                                           |
|---------------------|----------------|-------------------|-----------------------------------------------------------------------------------------------------------------|
| **Node Network**    | 10.240.0.0/24  | 노드 간 통신           | [Cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)                    |
| **Pod Network**     | 192.168.0.0/16 | Pod 간 통신 (Calico) | [Pod networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/#pod-to-pod)             |
| **Service Network** | 10.96.0.0/12   | Service ClusterIP | [Service networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/#service-to-backend) |

---

## 보안 명세

### 인증 및 권한

| 구성 요소          | 인증 방식              | 공식 문서                                                                                                  |
|----------------|--------------------|--------------------------------------------------------------------------------------------------------|
| **API Server** | X.509 Client Certs | [Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)              |
| **kubelet**    | X.509 Client Certs | [kubelet authentication](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-authn-authz/) |
| **RBAC**       | 활성화                | [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)                    |

### TLS 암호화

| 통신 경로                    | TLS 버전   | 공식 문서                                                                                                               |
|--------------------------|----------|---------------------------------------------------------------------------------------------------------------------|
| **API Server ↔ etcd**    | TLS 1.2+ | [Securing etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#securing-communication) |
| **API Server ↔ kubelet** | TLS 1.2+ | [kubelet TLS](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/)                   |
| **kubectl ↔ API Server** | TLS 1.2+ | [API server TLS](https://kubernetes.io/docs/concepts/security/controlling-access/)                                  |

### 방화벽 규칙 (GCP)

| 규칙명                | 포트      | 소스            | 용도          |
|--------------------|---------|---------------|-------------|
| k8s-allow-internal | all     | 10.240.0.0/24 | 내부 통신       |
| k8s-allow-external | 22,6443 | 0.0.0.0/0     | SSH, API 서버 |

---

## 참고 문서

### Kubernetes 공식 문서

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)

### 컨테이너 런타임

- [containerd Getting Started](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)
- [containerd Configuration](https://github.com/containerd/containerd/blob/main/docs/man/containerd-config.toml.5.md)

### CNI 네트워크

- [Calico Documentation](https://docs.projectcalico.org/)
- [Calico Kubernetes Guide](https://docs.projectcalico.org/getting-started/kubernetes/)

### GCP 관련

- [Google Cloud Compute Engine](https://cloud.google.com/compute/docs)
- [GCP Machine Types](https://cloud.google.com/compute/docs/machine-types)
- [GCP Firewall Rules](https://cloud.google.com/vpc/docs/firewalls)

---

## 구성 자동화

실제 환경 구성은 다음 도구들을 통해 자동화됩니다:

- **인프라 구성**: [Terraform](../../infra/terraform/README.md) - GCP 리소스 생성
- **소프트웨어 구성**: [Ansible](../../infra/ansible/README.md) - Kubernetes 클러스터 구성