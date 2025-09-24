
## 환경 정보  
  
- **Kubernetes 클러스터**: GCP VM 기반  
- **노드 구성**: Master 1개, Worker 3개  
- **OS**: Ubuntu 20.04/22.04  
- **NFS 서버**: 218.55.125.24 (NFSv4 전용)  
  
---  
  
## 문제 상황 분석  
  
### 초기 증상  
  
- **발견 시점**: 2025-09-24 12:25:29 UTC  
- **문제 Pod**: nfs-direct-test  
- **증상**: Pod가 Pending 상태에서 ContainerCreating으로 진행되지 않음  
- **영향 범위**: NFS 볼륨을 사용하는 모든 Pod  
  
### 에러 메시지  
  
```bash  
# kubectl describe pod nfs-direct-test 출력  
Events:  
  Type     Reason       Age               From               Message  
  ----     ------       ----              ----               -------  
  Normal   Scheduled    38s               default-scheduler  Successfully assigned practice/nfs-direct-test to k8s-node-3  
  Warning  FailedMount  7s (x7 over 38s)  kubelet            MountVolume.SetUp failed for volume "nfs-volume" : mount failed: exit status 32  
Mounting command: mount  
Mounting arguments: -t nfs 218.55.125.24:/shared/data /var/lib/kubelet/pods/19775e5f-4b9a-4663-a129-0d8c393b62b9/volumes/kubernetes.io~nfs/nfs-volume  
Output: mount: /var/lib/kubelet/pods/19775e5f-4b9a-4663-a129-0d8c393b62b9/volumes/kubernetes.io~nfs/nfs-volume: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program.  
```  
  
### 예상 동작 vs 실제 동작  
  
- **예상**: Pod가 정상적으로 NFS 볼륨을 마운트하고 Running 상태로 전환  
- **실제**: MountVolume.SetUp 실패로 인한 무한 재시도, ContainerCreating 상태 지속  
  
---  
  
## 원인 조사 과정  
  
### 1. 초기 진단  
  
#### 로그 분석  
  
핵심 에러 메시지 분석:  
```  
Output: mount: /var/lib/kubelet/pods/.../nfs-volume: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program.  
```  
  
*발견사항*: `"need a /sbin/mount.<type> helper program"` 메시지는 NFS 클라이언트 도구 부재를 의미  
  
#### 시스템 상태 확인  
  
컨트롤 플레인에서 직접 NFS 마운트 테스트:  

```bash  
ubuntu@k8s-control-plane-1:~/volume$ sudo mkdir -p /mnt/test  
ubuntu@k8s-control-plane-1:~/volume$ sudo mount -t nfs4 218.55.125.24:/shared/data /mnt/test  
mount: /mnt/test: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program.  
```  
  
*확인사항*: 컨트롤 플레인 노드에서도 동일한 에러 발생  
  
#### 패키지 상태 확인  
  
```bash  
# nfs-common 패키지 설치 여부 확인  
dpkg -l | grep nfs-common  
# 출력 없음 → 패키지 미설치 확인  
```  
  
### 2. 근본 원인 도출  
  
**근본 원인**: 쿠버네티스 클러스터의 모든 노드에 `nfs-common` 패키지가 설치되지 않음  
  
#### 공식 문서 참조  
  
> Ubuntu/Debian 시스템에서 NFS 클라이언트로 작동하려면 `nfs-common` 패키지가 필요합니다. 이 패키지는 NFS 파일시스템을 마운트하는 데 필요한 도구들을 제공합니다.  
  
**해석**: Kubernetes Pod가 NFS 볼륨을 마운트하려면 해당 워커 노드에 NFS 클라이언트 도구가 설치되어 있어야 하며, 이는 `nfs-common` 패키지로 제공됩니다.  
  
---  
  
## 해결 방안 적용  
  
### 근본 해결  
  
#### 해결 방안  
  
모든 클러스터 노드에 `nfs-common` 패키지 설치  
  
#### 구현 단계  
  
**1단계: 컨트롤 플레인 노드에서 설치**  
```bash  
sudo apt-get update  
sudo apt-get install -y nfs-common  
```  
  
**2단계: 모든 워커 노드에서 설치**  
```bash  
# 각 워커 노드에 SSH 접속하여 실행  
# 또는 다음과 같이 일괄 실행 (노드 이름에 맞게 수정)  
for node in k8s-node-1 k8s-node-2 k8s-node-3; do  
  ssh ubuntu@$node "sudo apt-get update && sudo apt-get install -y nfs-common"  
done  
```  
  
**3단계: NFS 마운트 테스트**  
```bash  
# 컨트롤 플레인에서 테스트  
sudo mount -t nfs4 218.55.125.24:/srv/k8s /mnt/test  
ls -la /mnt/test  
sudo umount /mnt/test  
```  
  
**4단계: Pod 재생성**  
```bash  
kubectl delete pod nfs-direct-test  
kubectl apply -f nfs-direct-pod.yaml  
```  
  
#### 검증 결과  
  
```bash  
# Pod 상태 확인  
kubectl get pods  
NAME              READY   STATUS    RESTARTS   AGE  
nfs-direct-test   1/1     Running   0          30s  
  
# NFS 마운트 확인  
kubectl exec nfs-direct-test -- ls -la /usr/share/nginx/html  
total 8  
drwxrwxrwx 2 nobody nogroup 4096 Sep 24 12:48 .  
drwxr-xr-x 3 root   root    4096 Sep  8 21:14 ..  
-rw-rw-r-- 1   1000    1000    0 Sep 24 12:48 share  
```  
  
*검증 완료*: Pod가 정상적으로 Running 상태가 되고 NFS 볼륨이 올바르게 마운트됨  
  
---  
  
## 사후 분석 및 개선  
  
### 핵심 교훈  
  
- **기술적 교훈**:  
  - Kubernetes는 워커 노드의 시스템 패키지에 의존하여 볼륨을 마운트함  
  - NFS 볼륨 사용 시 모든 노드에 `nfs-common` 패키지 사전 설치 필수  
  - NFSv4 전용 서버여도 기본 NFS 클라이언트 도구 필요  
  
- **프로세스 교훈**:  
  - Pod 상태 확인 시 Events 섹션의 상세 에러 메시지 분석이 핵심  
  - 컨테이너 레벨 문제가 아닌 노드 레벨 문제일 가능성도 고려 필요  
  
### 예방 방안  
  
#### Infrastructure as Code 적용  
  
Terraform이나 Ansible 등을 사용하여 노드 프로비저닝 시 필수 패키지 자동 설치  
  
### 모니터링 강화  
  
#### 노드 상태 모니터링  
  
```bash  
# 각 노드의 필수 패키지 설치 상태 확인 스크립트  
kubectl get nodes -o wide  
kubectl describe nodes | grep -E "nfs-common|cifs-utils"  
```  
  
#### Pod 마운트 실패 알림  
  
Pod Events에서 `FailedMount` 이벤트 발생 시 알림 설정  
  
---  
  
## 참고 자료  
  
### 공식 문서  
  
- [Kubernetes NFS Volume](https://kubernetes.io/docs/concepts/storage/volumes/#nfs) - NFS 볼륨 사용 가이드  
- [Ubuntu nfs-common Package](https://packages.ubuntu.com/search?keywords=nfs-common) - 패키지 정보  
  
### 내부 문서  
  
- [Storage 실습 가이드](docs/week2/07-storage-labs.md) - NFS Volume 실습 섹션  
- [클러스터 초기 설정 가이드](docs/setup/) - 노드 프로비저닝 절차