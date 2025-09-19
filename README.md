# AI-K8s Practice Repository

GCP 환경에서 kubeadm을 사용한 Kubernetes 클러스터 구축 및 학습 프로젝트

## 기술 스택

### Kubernetes 환경

- **운영체제**: Ubuntu 22.04 LTS
- **Kubernetes**: v1.34.1
- **Container Runtime**: containerd v2.1.4
- **클러스터 부트스트랩**: kubeadm v1.34.1
- **CLI 도구**: kubectl v1.34.1
- **CNI 플러그인**: Calico v3.30.3

### 개발 도구

- **Python 의존성 관리**: uv
- **버전 관리**: Git
- **명령어 관리**: Just
- **인프라 자동화**: Terraform v1.13.2
- **구성 관리**: Ansible v2.19.2

## 아키텍처

```mermaid
flowchart TB
    subgraph LOCAL["Local Infrastructure"]
        NFS["NFS Server<br/>Internal: 192.168.0.101<br/>External: 218.55.125.24<br/>Open Ports: 2049<br/>Allowed IPs: GCP Nodes"]

        GPU["gpu-worker<br/>Internal: 192.168.0.102<br/>External: 218.55.125.24<br/>Open Ports: 22<br/>GPU: NVIDIA RTX 4070TI"]
    end

    subgraph GCP["GCP Infrastructure - VPC: k8s-network"]
        ControlPlan["k8s-control-plan<br/>Internal: 10.240.0.10<br/>External: x.x.x.x<br/>Open Ports: 22, 6443"]

        Worker1["k8s-worker-0<br/>Internal: 10.240.0.20<br/>External: x.x.x.x<br/>Open Ports: 22"]

        Worker2["k8s-worker-1<br/>Internal: 10.240.0.21<br/>External: x.x.x.x<br/>Open Ports: 22"]

        Worker3["k8s-worker-2<br/>Internal: 10.240.0.22<br/>External: x.x.x.x<br/>Open Ports: 22"]
    end

    ControlPlan --> Worker1
    ControlPlan --> Worker2
    ControlPlan --> Worker3
    ControlPlan --> GPU

    Worker1 --> NFS
    Worker2 --> NFS
    Worker3 --> NFS
    GPU --> NFS

    classDef control-plan fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef worker fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef nfs fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef gpu fill:#fff3e0,stroke:#e65100,stroke-width:2px

    class ControlPlan control-plan
    class Worker1,Worker2,Worker3 worker
    class NFS nfs
    class GPU gpu
```

## 프로젝트 구조

```
ai-k8s/
├── docs/                           # 학습 문서
├── infra/                          # Infrastructure as Code
│   ├── terraform/                  # GCP 인프라 자동화
│   └── ansible/                    # Kubernetes 구성 자동화
└── README.md                       # 프로젝트 개요 (현재 파일)
```

## 학습 목차

### 1주차: 컨테이너와 Kubernetes 기초

- [컨테이너 이해 - Docker](./docs/week1/01-docker.md)
- [Kubernetes 아키텍처 파악](./docs/week1/02-kubernetes.md)
- [실습환경 기술 명세](./docs/week1/03-lab-setup.md)

## 이슈

- [cgroup 설정 문제](./docs/issue/cgroup.md)
