## 실습 환경  
  
- GCP VM 기반 Kubernetes 클러스터  
- Master Node: 1개, Worker Node: 3개  
  
## Pod 실습  
  
### 생성  
  
```yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: nginx-pod  
  labels:  
    app: nginx  
spec:  
  containers:  
    - name: nginx  
      image: nginx:1.21  
      ports:  
        - containerPort: 80  
```  
  
### Pod 삭제 관찰  
  
k8s 는 선언형 구조로 항상 pod를 유지하는 것으로 알고 있었는데, `kind: Pod` 인경우 컨트롤러가 없어서 제어를 안해준다.  
  
```shell  
# Pod 생성  
ubuntu@k8s-control-plane-1:~$ k apply -f pod.yaml  
pod/nginx-pod created  
  
ubuntu@k8s-control-plane-1:~$ k get all -o wide  
NAME            READY   STATUS    RESTARTS   AGE   IP              NODE         NOMINATED NODE   READINESS GATES  
pod/nginx-pod   1/1     Running   0          37s   10.244.140.66   k8s-node-2   <none>           <none>  
  
# Pod 삭제  
ubuntu@k8s-control-plane-1:~$ k delete pod/nginx-pod  
pod "nginx-pod" deleted from practice namespace  
  
# 바로 삭제됨  
ubuntu@k8s-control-plane-1:~$ k get all -o wide  
No resources found in practice namespace.  
```  
  
Pod 가 삭제되고 복구가 안되는 모습  
  
### Node drain  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k get pod -o wide  
NAME        READY   STATUS    RESTARTS   AGE   IP              NODE         NOMINATED NODE   READINESS GATES  
nginx-pod   1/1     Running   0          61s   10.244.140.68   k8s-node-2   <none>           <none>  
  
ubuntu@k8s-control-plane-1:~$ kubectl drain k8s-node-2 --ignore-daemonsets --delete-emptydir-data  
error: unable to drain node "k8s-node-2" due to error: cannot delete cannot delete Pods that declare no controller (use --force to override): practice/nginx-pod, continuing command...  
  
# 강제 drain  
ubuntu@k8s-control-plane-1:~$ kubectl drain k8s-node-2 --ignore-daemonsets --delete-emptydir-data --force  
node/k8s-node-2 already cordoned  
Warning: ignoring DaemonSet-managed Pods: calico-system/calico-node-4c9zv, calico-system/csi-node-driver-qsp4p, kube-system/kube-proxy-f6ff9; deleting Pods that declare no controller: practice/nginx-pod  
evicting pod practice/nginx-pod  
pod/nginx-pod evicted  
node/k8s-node-2 drained  
```  
  
`k8s-node-2` 에 pod 가 생성되지 않게 설정하면 에러가 발생한다. controller 로 관리되지 않는 pods이 있다는 경고.  
강제로 명령을 적용하는경우 Pod이 삭제되고 마찬가지로 복구가 안된다.  
  
## ReplicaSet 실습  
  
### 생성  
  
```yaml  
apiVersion: apps/v1  
kind: ReplicaSet  
metadata:  
  name: nginx-rs  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: nginx-rs  
  template:  
    metadata:  
      labels:  
        app: nginx-rs  
    spec:  
      containers:  
      - name: nginx  
        image: nginx:1.29  
```  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k apply -f ./replicas.yaml  
replicaset.apps/nginx-rs created  
  
ubuntu@k8s-control-plane-1:~$ k get all -o wide  
NAME                 READY   STATUS    RESTARTS   AGE   IP              NODE         NOMINATED NODE   READINESS GATES  
pod/nginx-rs-7zfj7   1/1     Running   0          26s   10.244.109.67   k8s-node-1   <none>           <none>  
pod/nginx-rs-9bpvx   1/1     Running   0          26s   10.244.76.130   k8s-node-3   <none>           <none>  
pod/nginx-rs-v7942   1/1     Running   0          26s   10.244.140.69   k8s-node-2   <none>           <none>  
  
NAME                       DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES       SELECTOR  
replicaset.apps/nginx-rs   3         3         3       26s   nginx        nginx:1.29   app=nginx-rs  
```  
  
replicas 를 3개 지정해서 실행. pod 과 다르게 replicaset이 추가되어 배포된다.  
  
### Pod 삭제  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k delete pod/nginx-rs-v7942  
pod "nginx-rs-v7942" deleted from practice namespace  
  
ubuntu@k8s-control-plane-1:~$ k get all -o wide  
NAME                 READY   STATUS    RESTARTS   AGE     IP              NODE         NOMINATED NODE   READINESS GATES  
pod/nginx-rs-7zfj7   1/1     Running   0          2m27s   10.244.109.67   k8s-node-1   <none>           <none>  
pod/nginx-rs-9bpvx   1/1     Running   0          2m27s   10.244.76.130   k8s-node-3   <none>           <none>  
pod/nginx-rs-b2gdk   1/1     Running   0          2s      10.244.140.70   k8s-node-2   <none>           <none>  
  
NAME                       DESIRED   CURRENT   READY   AGE     CONTAINERS   IMAGES       SELECTOR  
replicaset.apps/nginx-rs   3         3         3       2m27s   nginx        nginx:1.29   app=nginx-rs  
ubuntu@k8s-control-plane-1:~$  
```  
  
`nginx-rs-v7942` 파드를 삭제했지만 즉시 `pod/nginx-rs-b2gdk` 가 복구 되었다.  
  
### Node drain  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k drain k8s-node-2 --ignore-daemonsets  
node/k8s-node-2 already cordoned  
Warning: ignoring DaemonSet-managed Pods: calico-system/calico-node-4c9zv, calico-system/csi-node-driver-qsp4p, kube-system/kube-proxy-f6ff9  
evicting pod practice/nginx-rs-b2gdk  
pod/nginx-rs-b2gdk evicted  
node/k8s-node-2 drained  
  
ubuntu@k8s-control-plane-1:~$ k get all -o wide  
NAME                 READY   STATUS    RESTARTS   AGE     IP              NODE         NOMINATED NODE   READINESS GATES  
pod/nginx-rs-7zfj7   1/1     Running   0          4m36s   10.244.109.67   k8s-node-1   <none>           <none>  
pod/nginx-rs-9bpvx   1/1     Running   0          4m36s   10.244.76.130   k8s-node-3   <none>           <none>  
pod/nginx-rs-wb8dk   1/1     Running   0          12s     10.244.76.131   k8s-node-3   <none>           <none>  
  
NAME                       DESIRED   CURRENT   READY   AGE     CONTAINERS   IMAGES       SELECTOR  
replicaset.apps/nginx-rs   3         3         3       4m36s   nginx        nginx:1.29   app=nginx-rs  
```  
  
Pod와 다르게 `k8s-node-2`를 drain 하자 3개를 유지하기 위해 `k8s-node-3`에 Pod가 추가되었다.  
  
### 업데이트  
  
```shell  
kubectl patch replicaset nginx-rs -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"nginx:1.22"}]}}}}'  
replicaset.apps/nginx-rs patched  
  
ubuntu@k8s-control-plane-1:~$ kubectl get pods -l app=nginx-rs -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'  
nginx-rs-7zfj7  nginx:1.29  
nginx-rs-9bpvx  nginx:1.29  
nginx-rs-wb8dk  nginx:1.29  
```  
  
패치 이후 자동으로 업데이트 되지 않는다.  
  
```shell  
ubuntu@k8s-control-plane-1:~$ kubectl delete pods -l app=nginx-rs  
pod "nginx-rs-7zfj7" deleted from practice namespace  
pod "nginx-rs-9bpvx" deleted from practice namespace  
pod "nginx-rs-wb8dk" deleted from practice namespace  
  
ubuntu@k8s-control-plane-1:~$ kubectl get pods -l app=nginx-rs -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'  
nginx-rs-58jkl  nginx:1.22  
nginx-rs-b8qdv  nginx:1.22  
nginx-rs-kc7n5  nginx:1.22  
```  
  
기존 Pod를 제거하면 rs이 Pod를 새로 생성하면서 업데이트된 이미지를 적용한다.  
  
### 삭제  
  
Pod만 삭제하면 다시 생겨난다. RepicaSet을 삭제해서 리소스를 정리한다.  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k delete replicaset.apps/nginx-rs  
replicaset.apps "nginx-rs" deleted from practice namespace  
  
ubuntu@k8s-control-plane-1:~$ k get all  
No resources found in practice namespace.  
ubuntu@k8s-control-plane-1:~$  
```  
  
## Deployment 실습  
  
### 생성  
  
```yaml  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: nginx-deployment  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: nginx-deploy  
  template:  
    metadata:  
      labels:  
        app: nginx-deploy  
    spec:  
      containers:  
        - name: nginx  
          image: nginx:1.29  
```  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k apply -f ./deployment.yaml   
deployment.apps/nginx-deployment created  
  
ubuntu@k8s-control-plane-1:~$ k get all  
NAME                                   READY   STATUS    RESTARTS   AGE  
pod/nginx-deployment-878fd66b8-qgp66   1/1     Running   0          81s  
pod/nginx-deployment-878fd66b8-vvn4z   1/1     Running   0          81s  
pod/nginx-deployment-878fd66b8-z2677   1/1     Running   0          81s  
  
NAME                               READY   UP-TO-DATE   AVAILABLE   AGE  
deployment.apps/nginx-deployment   3/3     3            3           82s  
  
NAME                                         DESIRED   CURRENT   READY   AGE  
replicaset.apps/nginx-deployment-878fd66b8   3         3         3       82s  
```  
  
replicaset에 이어서 deployment 리소스까지 생성되었다.  
  
### Pod 삭제  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k delete pod/nginx-deployment-878fd66b8-z2677  
pod "nginx-deployment-878fd66b8-z2677" deleted from practice namespace  
  
ubuntu@k8s-control-plane-1:~$ k get all  
NAME                                   READY   STATUS    RESTARTS   AGE  
pod/nginx-deployment-878fd66b8-qgp66   1/1     Running   0          2m6s  
pod/nginx-deployment-878fd66b8-vvn4z   1/1     Running   0          2m6s  
pod/nginx-deployment-878fd66b8-wzvlb   1/1     Running   0          4s  
  
NAME                               READY   UP-TO-DATE   AVAILABLE   AGE  
deployment.apps/nginx-deployment   3/3     3            3           2m7s  
  
NAME                                         DESIRED   CURRENT   READY   AGE  
replicaset.apps/nginx-deployment-878fd66b8   3         3         3       2m7s  
ubuntu@k8s-control-plane-1:~$   
```  
  
`nginx-deployment-878fd66b8-z2677` 파드를 삭제했지만 즉식 `pod/nginx-deployment-878fd66b8-wzvlb`가 복구 되었다.\  
deployment는 replicaset을 포함하기 때문에 replicaset과 동일하게 동작한다.\  
따라서 Node drain은 스킵한다.  
  
### 업데이트  
  
```shell  
#  kubectl set image deployment/nginx-deployment nginx=nginx:1.22  
ubuntu@k8s-control-plane-1:~$ kubectl patch deployment nginx-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"nginx:1.22"}]}}}}'  
deployment.apps/nginx-deployment patched  
  
ubuntu@k8s-control-plane-1:~$ kubectl get pods -l app=nginx-deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'  
nginx-deployment-775bd8665f-2xcz5   nginx:1.22  
nginx-deployment-775bd8665f-cmw48   nginx:1.22  
nginx-deployment-775bd8665f-xrcxm   nginx:1.22  
```  
  
replicaset과 다르게 패치 이후 자동으로 업데이트가 완료된 모습.\  
아래 명령어들로 업데이트 기록을 확인할 수 있다.  
  
  
```shell  
ubuntu@k8s-control-plane-1:~$ kubectl rollout status deployment/nginx-deployment  
deployment "nginx-deployment" successfully rolled out  
  
---  
ubuntu@k8s-control-plane-1:~$ kubectl get all  
NAME                                    READY   STATUS    RESTARTS   AGE  
pod/nginx-deployment-775bd8665f-2xcz5   1/1     Running   0          3m11s  
pod/nginx-deployment-775bd8665f-cmw48   1/1     Running   0          3m7s  
pod/nginx-deployment-775bd8665f-xrcxm   1/1     Running   0          3m9s  
  
NAME                               READY   UP-TO-DATE   AVAILABLE   AGE  
deployment.apps/nginx-deployment   3/3     3            3           4m17s  
  
NAME                                          DESIRED   CURRENT   READY   AGE  
replicaset.apps/nginx-deployment-546d459948   0         0         0       4m17s  
replicaset.apps/nginx-deployment-775bd8665f   3         3         3       3m12s  
  
---  
ubuntu@k8s-control-plane-1:~$ kubectl rollout history deployment/nginx-deployment  
deployment.apps/nginx-deployment REVISION  CHANGE-CAUSE  
1         <none>  
2         <none>  
```  
  
### 롤백  
  
업데이트기록을 보존하기 때문에 이전 상태로도 돌아갈 수 있다.  
  
```shell  
# 이전 버전으로 롤백  
kubectl rollout undo deployment/nginx-deployment  
  
# 특정 리비전으로 롤백  
kubectl rollout undo deployment/nginx-deployment --to-revision=1  
  
---  
ubuntu@k8s-control-plane-1:~$ kubectl rollout undo deployment/nginx-deployment  
deployment.apps/nginx-deployment rolled back  
  
ubuntu@k8s-control-plane-1:~$ kubectl rollout history deployment/nginx-deployment  
deployment.apps/nginx-deployment REVISION  CHANGE-CAUSE  
2         <none>  
3         <none>  
  
ubuntu@k8s-control-plane-1:~$ kubectl get all  
NAME                                    READY   STATUS    RESTARTS   AGE  
pod/nginx-deployment-546d459948-lw79v   1/1     Running   0          58s  
pod/nginx-deployment-546d459948-t9vnz   1/1     Running   0          60s  
pod/nginx-deployment-546d459948-wfbz4   1/1     Running   0          61s  
  
NAME                               READY   UP-TO-DATE   AVAILABLE   AGE  
deployment.apps/nginx-deployment   3/3     3            3           7m37s  
  
NAME                                          DESIRED   CURRENT   READY   AGE  
replicaset.apps/nginx-deployment-546d459948   3         3         3       7m37s  
replicaset.apps/nginx-deployment-775bd8665f   0         0         0       6m32s  
ubuntu@k8s-control-plane-1:~$   
```  
  
이전 버전으로 롤백을 통해:  
- `Revision 1` -> `Revision 3` 로 갱신  
- replicaset 은 `Revision 1` 을 재사용  
  
### 고급  
  
체인지 메세지를 작성할 수 있다.  
  
```shell  
# 배포 후 메세지 작성  
kubectl annotate deployment nginx-deployment kubernetes.io/change-cause="nginx 1.21로 롤백"  
  
# 또는 배포 시 --record 플래그 사용  
kubectl set image deployment/nginx-deployment nginx=nginx:1.23 --record  
  
ubuntu@k8s-control-plane-1:~$ kubectl rollout history deployment/nginx-deployment  
deployment.apps/nginx-deployment REVISION  CHANGE-CAUSE  
2         kubectl set image deployment/nginx-deployment nginx=nginx:1.22  
3         nginx 1.21로 롤백  
```  
  
### 여러 변경사항 한번에 적용  
  
```shell  
# Deployment 일시정지 (변경사항이 즉시 반영되지 않음)  
kubectl rollout pause deployment/nginx-deployment  
  
# 여러 변경사항 적용  
kubectl set image deployment/nginx-deployment nginx=nginx:1.23  
kubectl set resources deployment/nginx-deployment -c nginx --limits=cpu=200m,memory=128Mi  
kubectl patch deployment nginx-deployment -p '{"spec":{"replicas":5}}'  
  
# 현재 상태 확인 (아직 변경 안됨)  
kubectl get pods -l app=nginx-deploy  
kubectl rollout status deployment/nginx-deployment  
  
# 재개하면 모든 변경사항이 한번에 적용됨  
kubectl rollout resume deployment/nginx-deployment  
```  
  
```shell  
cat <<EOF > deployment.yaml  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: nginx-deployment  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: nginx-deploy  
  template:  
    metadata:  
      labels:  
        app: nginx-deploy  
    spec:  
      containers:  
        - name: nginx  
          image: nginx:1.29  
EOF  
```