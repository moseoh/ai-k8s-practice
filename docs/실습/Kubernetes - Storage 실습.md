## 실습 환경  
  
- GCP VM 기반 Kubernetes 클러스터  
- Master Node: 1개, Worker Node: 3개  
- NFS Server: 218.55.125.24 (NFSv4 전용)  
  
---  
  
## 1. 기본 Volume 실습  
  
### 1.1 emptyDir Volume  
  
```yaml  
# emptydir-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: emptydir-test  
spec:  
  containers:  
  - name: writer  
    image: busybox  
    command: ['sh', '-c', 'while true; do echo "$(date) - Writing" >> /data/log.txt; sleep 5; done']  
    volumeMounts:  
    - name: shared-data  
      mountPath: /data  
  - name: reader  
    image: busybox  
    command: ['sh', '-c', 'tail -f /data/log.txt']  
    volumeMounts:  
    - name: shared-data  
      mountPath: /data  
  volumes:  
  - name: shared-data  
    emptyDir: {}  
```  
  
```bash  
# 적용 및 확인  
kubectl apply -f emptydir-pod.yaml  
  
# Reader 컨테이너 로그 확인  
kubectl logs emptydir-test -c reader  
  
# Pod 재시작 시 데이터 손실 확인  
kubectl delete pod emptydir-test  
kubectl apply -f emptydir-pod.yaml  
kubectl logs emptydir-test -c reader  # 이전 데이터 없음  
```  
  
### 1.2 메모리 기반 emptyDir  
  
```yaml  
# emptydir-memory.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: emptydir-memory  
spec:  
  containers:  
  - name: cache-app  
    image: busybox  
    command: ['sh', '-c', 'while true; do date >> /cache/data.txt; sleep 2; done']  
    volumeMounts:  
    - name: cache-volume  
      mountPath: /cache  
    resources:  
      limits:  
        memory: "256Mi"  
  volumes:  
  - name: cache-volume  
    emptyDir:  
      medium: Memory  
      sizeLimit: 100Mi  
```  
  
```bash  
# 적용  
kubectl apply -f emptydir-memory.yaml  
  
# 메모리 사용량 확인  
kubectl exec emptydir-memory -- df -h /cache  
kubectl exec emptydir-memory -- cat /cache/data.txt  
```  
  
---  
  
## 2. NFS Volume 직접 사용  
  
### 2.1 단순 NFS Volume  
  
```yaml  
# nfs-direct-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: nfs-direct-test  
spec:  
  containers:  
  - name: app  
    image: nginx  
    volumeMounts:  
    - name: nfs-volume  
      mountPath: /usr/share/nginx/html  
  volumes:  
  - name: nfs-volume  
    nfs:  
      server: 218.55.125.24  
      path: /srv/k8s  
      readOnly: false  
```  
  
```bash  
# 적용  
kubectl apply -f nfs-direct-pod.yaml  
  
# NFS 마운트 확인  
kubectl exec nfs-direct-test -- ls -la /usr/share/nginx/html  
#total 8  
#drwxrwxrwx 2 nobody nogroup 4096 Sep 24 12:48 .  
#drwxr-xr-x 3 root   root    4096 Sep  8 21:14 ..  
#-rw-rw-r-- 1   1000    1000    0 Sep 24 12:48 share <-- 공유 파일  
```  
  
### 2.2 여러 Pod에서 NFS 공유  
  
```yaml  
# nfs-shared-pods.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: nfs-writer  
spec:  
  containers:  
  - name: writer  
    image: busybox  
    command: ['sh', '-c', 'while true; do echo "Writer: $(date)" >> /shared/log.txt; sleep 5; done']  
    volumeMounts:  
    - name: nfs-volume  
      mountPath: /shared  
  volumes:  
  - name: nfs-volume  
    nfs:  
      server: 218.55.125.24  
      path: /srv/k8s  
---  
apiVersion: v1  
kind: Pod  
metadata:  
  name: nfs-reader  
spec:  
  containers:  
  - name: reader  
    image: busybox  
    command: ['sh', '-c', 'tail -f /shared/log.txt']  
    volumeMounts:  
    - name: nfs-volume  
      mountPath: /shared  
  volumes:  
  - name: nfs-volume  
    nfs:  
      server: 218.55.125.24  
      path: /srv/k8s  
```  
  
```bash  
# 적용  
kubectl apply -f nfs-shared-pods.yaml  
  
# Writer가 쓰는 내용을 Reader에서 확인  
kubectl logs nfs-reader  
#Writer: Wed Sep 24 12:50:17 UTC 2025  
  
# NFS shared dir  
#total 12  
#drwxrwxrwx 2 nobody nogroup 4096 Sep 24 21:50 ./  
#drwxr-xr-x 3 root   root    4096 Sep 17 20:25 ../  
#-rw-r--r-- 1 root   root     111 Sep 24 21:50 log.txt <-- 로그 파일  
#-rw-rw-r-- 1 moseoh moseoh     0 Sep 24 21:48 share  
```  
  
---  
  
## 3. PersistentVolume과 PersistentVolumeClaim  
  
### 3.1 NFS PersistentVolume 생성  
  
```yaml  
# nfs-pv.yaml  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-1  
spec:  
  capacity:  
    storage: 5Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/pv1  
---  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-2  
spec:  
  capacity:  
    storage: 10Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/pv2  
---  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-3  
spec:  
  capacity:  
    storage: 2Gi  
  accessModes:  
    - ReadWriteOnce  
  persistentVolumeReclaimPolicy: Delete  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/pv3  
```  
  
```bash  
# PV 생성 및 확인  
kubectl apply -f nfs-pv.yaml  
ubuntu@k8s-control-plane-1:~/volume$ kg pv  
#NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE  
#nfs-pv-1   5Gi        RWX            Retain           Available                          <unset>                          26s  
#nfs-pv-2   10Gi       RWX            Retain           Available                          <unset>                          26s  
#nfs-pv-3   2Gi        RWO            Delete           Available                          <unset>                          26s  
  
ubuntu@k8s-control-plane-1:~/volume$ kubectl describe pv nfs-pv-1  
#Name:            nfs-pv-1  
#Labels:          <none>  
#Annotations:     <none>  
#Finalizers:      [kubernetes.io/pv-protection]  
#StorageClass:      
#Status:          Available  
#Claim:             
#Reclaim Policy:  Retain  
#Access Modes:    RWX  
#VolumeMode:      Filesystem  
#Capacity:        5Gi  
#Node Affinity:   <none>  
#Message:           
#Source:  
#    Type:      NFS (an NFS mount that lasts the lifetime of a pod)  
#    Server:    218.55.125.24  
#    Path:      /srv/k8s/pv1  
#    ReadOnly:  false  
#Events:        <none>  
```  
  
### 3.2 PersistentVolumeClaim 생성  
  
```yaml  
# nfs-pvc.yaml  
apiVersion: v1  
kind: PersistentVolumeClaim  
metadata:  
  name: nfs-claim-1  
spec:  
  accessModes:  
    - ReadWriteMany  
  resources:  
    requests:  
      storage: 3Gi  
---  
apiVersion: v1  
kind: PersistentVolumeClaim  
metadata:  
  name: nfs-claim-2  
spec:  
  accessModes:  
    - ReadWriteMany  
  resources:  
    requests:  
      storage: 8Gi  
```  
  
결과: storageClassName을 지정하지 않아서 적절한 pv에 자동할당된다.  
  
```bash  
# PVC 생성 및 바인딩 확인  
kubectl apply -f nfs-pvc.yaml  
  
# PVC 상태 확인  
kubectl get pvc  
#NAME          STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE  
#nfs-claim-1   Bound    nfs-pv-1   5Gi        RWX                           <unset>                 5s  
#nfs-claim-2   Bound    nfs-pv-2   10Gi       RWX                           <unset>                 5s  
  
kubectl describe pvc nfs-claim-1  
#Name:          nfs-claim-1  
#Namespace:     practice  
#StorageClass:    
#Status:        Bound  
#Volume:        nfs-pv-1  
#Labels:        <none>  
#Annotations:   pv.kubernetes.io/bind-completed: yes  
#               pv.kubernetes.io/bound-by-controller: yes  
#Finalizers:    [kubernetes.io/pvc-protection]  
#Capacity:      5Gi  
#Access Modes:  RWX  
#VolumeMode:    Filesystem  
#Used By:       <none>  
#Events:        <none>  
  
# PV 바인딩 상태 확인  
kubectl get pv  
#NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM                  STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE  
#nfs-pv-1   5Gi        RWX            Retain           Bound       practice/nfs-claim-1                  <unset>                          2m19s  
#nfs-pv-2   10Gi       RWX            Retain           Bound       practice/nfs-claim-2                  <unset>                          2m19s  
#nfs-pv-3   2Gi        RWO            Delete           Available                                         <unset>                          2m19s  
```  
  
### 3.3 PVC를 사용하는 Pod  
  
```yaml  
# pod-with-pvc.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: app-with-pvc  
spec:  
  containers:  
  - name: app  
    image: nginx  
    volumeMounts:  
    - name: persistent-storage  
      mountPath: /usr/share/nginx/html  
  volumes:  
  - name: persistent-storage  
    persistentVolumeClaim:  
      claimName: nfs-claim-1  
```  
  
```bash  
# Pod 생성  
kubectl apply -f pod-with-pvc.yaml  
  
# 마운트 확인  
kubectl describe pod app-with-pvc  
#Volumes:  
#  persistent-storage:  
#    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)  
#    ClaimName:  nfs-claim-1  
#    ReadOnly:   false  
  
# nfs-claim-1은 pv1  
kubectl describe pv  
#Name:            nfs-pv-1  
#Labels:          <none>  
#Annotations:     pv.kubernetes.io/bound-by-controller: yes  
#Finalizers:      [kubernetes.io/pv-protection]  
#StorageClass:      
#Status:          Bound  
#Claim:           practice/nfs-claim-1  
#Reclaim Policy:  Retain  
#Access Modes:    RWX  
#VolumeMode:      Filesystem  
#Capacity:        5Gi  
#Node Affinity:   <none>  
#Message:           
#Source:  
#    Type:      NFS (an NFS mount that lasts the lifetime of a pod)  
#    Server:    218.55.125.24  
#    Path:      /srv/k8s/pv1  
#    ReadOnly:  false  
#Events:        <none>  
  
# NFS 서버에서 파일 생성 (/srv/k8s/pv1)  
touch share  
  
kubectl exec app-with-pvc -- ls -la /usr/share/nginx/html  
#total 8  
#drwxrwxr-x 2 1000 1000 4096 Sep 24 13:01 .  
#drwxr-xr-x 3 root root 4096 Sep  8 21:14 ..  
#-rw-rw-r-- 1 1000 1000    0 Sep 24 13:01 share  
```  
  
---  
  
## 4. StatefulSet과 영구 스토리지  
  
### 4.1 StatefulSet with VolumeClaimTemplate  
  
```yaml  
# statefulset-nfs.yaml  
apiVersion: v1  
kind: Service  
metadata:  
  name: nginx-headless  
spec:  
  clusterIP: None  
  selector:  
    app: nginx-sts  
  ports:  
  - port: 80  
    targetPort: 80  
---  
apiVersion: apps/v1  
kind: StatefulSet  
metadata:  
  name: web  
spec:  
  serviceName: nginx-headless  
  replicas: 3  
  selector:  
    matchLabels:  
      app: nginx-sts  
  template:  
    metadata:  
      labels:  
        app: nginx-sts  
    spec:  
      containers:  
      - name: nginx  
        image: nginx  
        ports:  
        - containerPort: 80  
        volumeMounts:  
        - name: www  
          mountPath: /usr/share/nginx/html  
  volumeClaimTemplates:  
  - metadata:  
      name: www  
    spec:  
      accessModes: [ "ReadWriteMany" ]  
      resources:  
        requests:  
          storage: 1Gi  
---  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-sts-0  
spec:  
  capacity:  
    storage: 1Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/sts1  
---  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-sts-1  
spec:  
  capacity:  
    storage: 1Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/sts2  
---  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-sts-2  
spec:  
  capacity:  
    storage: 1Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/sts3  
```  
  
StatefulSet 은 각 pod 마다 pvc를 생성한다. 위 예시에서 replica 3으로 3개의 pv가 준비되어야한다.  
  
```bash  
# StatefulSet 생성  
kubectl apply -f statefulset-nfs.yaml  
  
# Pod와 PVC 확인  
kubectl get pods -l app=nginx-sts  
# 3개의 PVC가 생성됨.  
kubectl get pvc  
#www-web-0     Bound    nfs-pv-sts-0   1Gi        RWX                           <unset>                 4m32s  
#www-web-1     Bound    nfs-pv-sts-1   1Gi        RWX                           <unset>                 20s  
#www-web-2     Bound    nfs-pv-sts-2   1Gi        RWX                           <unset>                 16s  
  
# 각 Pod의 스토리지 확인  
for i in 0 1 2; do  
  kubectl exec web-$i -- sh -c "echo 'Pod web-$i' > /usr/share/nginx/html/index.html"  
done  
  
# 각 Pod의 데이터 확인  
for i in 0 1 2; do  
  kubectl exec web-$i -- cat /usr/share/nginx/html/index.html  
done  
#Pod web-0  
#Pod web-1  
#Pod web-2  
  
# NFS 서버에서  
#ll sts1  
#total 12  
#drwxrwxr-x 2 moseoh moseoh  4096 Sep 24 22:08 ./  
#drwxrwxrwx 8 nobody nogroup 4096 Sep 24 22:05 ../  
#-rw-r--r-- 1 root   root      10 Sep 24 22:08 index.html  
```  
  
---  
  
## 5. 애플리케이션 시나리오  
  
### 5.1 WordPress with MySQL (NFS Storage)  
  
```yaml  
# wordpress-mysql.yaml  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-1  
spec:  
  capacity:  
    storage: 5Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/pv1  
---  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-2  
spec:  
  capacity:  
    storage: 10Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/pv2  
---  
# MySQL PVC  
apiVersion: v1  
kind: PersistentVolumeClaim  
metadata:  
  name: mysql-pvc  
spec:  
  accessModes:  
    - ReadWriteMany  
  resources:  
    requests:  
      storage: 5Gi  
---  
# WordPress PVC  
apiVersion: v1  
kind: PersistentVolumeClaim  
metadata:  
  name: wordpress-pvc  
spec:  
  accessModes:  
    - ReadWriteMany  
  resources:  
    requests:  
      storage: 5Gi  
---  
# MySQL Deployment  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: mysql  
spec:  
  replicas: 1  
  selector:  
    matchLabels:  
      app: mysql  
  template:  
    metadata:  
      labels:  
        app: mysql  
    spec:  
      containers:  
      - name: mysql  
        image: mysql:5.7  
        env:  
        - name: MYSQL_ROOT_PASSWORD  
          value: rootpass  
        - name: MYSQL_DATABASE  
          value: wordpress  
        - name: MYSQL_USER  
          value: wpuser  
        - name: MYSQL_PASSWORD  
          value: wppass  
        ports:  
        - containerPort: 3306  
        volumeMounts:  
        - name: mysql-storage  
          mountPath: /var/lib/mysql  
      volumes:  
      - name: mysql-storage  
        persistentVolumeClaim:  
          claimName: mysql-pvc  
---  
# MySQL Service  
apiVersion: v1  
kind: Service  
metadata:  
  name: mysql  
spec:  
  selector:  
    app: mysql  
  ports:  
  - port: 3306  
---  
# WordPress Deployment  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: wordpress  
spec:  
  replicas: 2  
  selector:  
    matchLabels:  
      app: wordpress  
  template:  
    metadata:  
      labels:  
        app: wordpress  
    spec:  
      containers:  
      - name: wordpress  
        image: wordpress:5.8  
        env:  
        - name: WORDPRESS_DB_HOST  
          value: mysql:3306  
        - name: WORDPRESS_DB_USER  
          value: wpuser  
        - name: WORDPRESS_DB_PASSWORD  
          value: wppass  
        - name: WORDPRESS_DB_NAME  
          value: wordpress  
        ports:  
        - containerPort: 80  
        volumeMounts:  
        - name: wordpress-storage  
          mountPath: /var/www/html  
      volumes:  
      - name: wordpress-storage  
        persistentVolumeClaim:  
          claimName: wordpress-pvc  
---  
# WordPress Service  
apiVersion: v1  
kind: Service  
metadata:  
  name: wordpress  
spec:  
  type: NodePort  
  selector:  
    app: wordpress  
  ports:  
  - port: 80  
    targetPort: 80  
    nodePort: 30080  
```  
  
```bash  
# 배포  
kubectl apply -f wordpress-mysql.yaml  
  
# 확인  
kubectl get pods  
kubectl get pvc  
kubectl get svc  
  
# WordPress 접속  
# http://<NODE_IP>:30080  
```  
  
  ![file:/Users/seongha.moon/code/practice/ai-k8s/docs/week2/wordpress.png](file:///Users/seongha.moon/code/practice/ai-k8s/docs/week2/wordpress.png)
### 5.2 로그 수집 시스템  
  
```yaml  
# log-collection.yaml  
apiVersion: v1  
kind: PersistentVolume  
metadata:  
  name: nfs-pv-1  
spec:  
  capacity:  
    storage: 10Gi  
  accessModes:  
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain  
  nfs:  
    server: 218.55.125.24  
    path: /srv/k8s/pv1  
---  
# 로그 수집용 PVC  
apiVersion: v1  
kind: PersistentVolumeClaim  
metadata:  
  name: logs-pvc  
spec:  
  accessModes:  
    - ReadWriteMany  
  resources:  
    requests:  
      storage: 10Gi  
---  
# 애플리케이션 Pod (로그 생성)  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: app-logger  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: logger  
  template:  
    metadata:  
      labels:  
        app: logger  
    spec:  
      containers:  
      - name: app  
        image: busybox  
        command: ['sh', '-c', 'while true; do echo "[$(date)] App $(hostname) - Processing request" >> /logs/app.log; sleep 3; done']  
        volumeMounts:  
        - name: logs  
          mountPath: /logs  
      volumes:  
      - name: logs  
        persistentVolumeClaim:  
          claimName: logs-pvc  
---  
# 로그 수집기 Pod  
apiVersion: v1  
kind: Pod  
metadata:  
  name: log-collector  
spec:  
  containers:  
  - name: collector  
    image: busybox  
    command: ['sh', '-c', 'tail -f /logs/app.log | while read line; do echo "[COLLECTOR] $line"; done']  
    volumeMounts:  
    - name: logs  
      mountPath: /logs  
  volumes:  
  - name: logs  
    persistentVolumeClaim:  
      claimName: logs-pvc  
```  
  
```bash  
# 배포  
kubectl apply -f log-collection.yaml  
  
# 로그 확인  
kubectl logs log-collector  
#[COLLECTOR]   
#[COLLECTOR]   
#[COLLECTOR]   
  
# 로그 파일 크기 확인  
kubectl exec log-collector -- ls -lh /logs/  
#total 4K      
#-rw-r--r--    1 root     root        1.8K Sep 24 13:28 app.log  
```  
  
---  
  
## 6. 백업 및 복구  
  
### 6.1 데이터 백업 Job  
  
```yaml  
# backup-job.yaml  
apiVersion: batch/v1  
kind: Job  
metadata:  
  name: backup-job  
spec:  
  template:  
    spec:  
      containers:  
      - name: backup  
        image: busybox  
        command:  
        - sh  
        - -c  
        - |  
          echo "Starting backup at $(date)"  
          SOURCE=/source  
          BACKUP=/backup/backup-$(date +%Y%m%d-%H%M%S)  
          mkdir -p $BACKUP  
          cp -r $SOURCE/* $BACKUP/  
          echo "Backup completed at $(date)"  
          ls -la /backup/  
        volumeMounts:  
        - name: source-data  
          mountPath: /source  
          readOnly: true  
        - name: backup-data  
          mountPath: /backup  
      restartPolicy: Never  
      volumes:  
      - name: source-data  
        persistentVolumeClaim:  
          claimName: wordpress-pvc  
      - name: backup-data  
        nfs:  
          server: 218.55.125.24  
          path: /srv/k8s/backups  
```  
  
```bash  
# 백업 실행  
kubectl apply -f backup-job.yaml  
  
# Job 상태 확인  
ubuntu@k8s-control-plane-1:~/volume$ kubectl get jobs  
#NAME         STATUS     COMPLETIONS   DURATION   AGE  
#backup-job   Complete   1/1           2m9s       2m51s  
  
ubuntu@k8s-control-plane-1:~/volume$ kubectl logs job/backup-job  
Starting backup at Wed Sep 24 13:37:26 UTC 2025  
Backup completed at Wed Sep 24 13:39:29 UTC 2025  
total 12  
drwxrwxr-x    3 1000     1000          4096 Sep 24 13:37 .  
drwxr-xr-x    1 root     root          4096 Sep 24 13:37 ..  
drwxr-xr-x    5 root     root          4096 Sep 24 13:39 backup-20250924-133726  
```  
  
---  
  
## 7. 트러블슈팅  
  
### 7.1 PVC 상태 확인  
  
```yaml  
# debug-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: debug-storage  
spec:  
  containers:  
  - name: debug  
    image: busybox  
    command: ['sleep', '3600']  
    volumeMounts:  
    - name: test-volume  
      mountPath: /mnt/test  
  volumes:  
  - name: test-volume  
    persistentVolumeClaim:  
      claimName: nfs-claim-1  
```  
  
```bash  
# 디버그 Pod 생성  
kubectl apply -f debug-pod.yaml  
  
# NFS 마운트 확인  
kubectl exec debug-storage -- mount | grep nfs  
kubectl exec debug-storage -- df -h /mnt/test  
  
# 권한 확인  
kubectl exec debug-storage -- ls -la /mnt/test  
  
# 쓰기 테스트  
kubectl exec debug-storage -- touch /mnt/test/test-file  
kubectl exec debug-storage -- echo "test" > /mnt/test/test.txt  
```  
  
### 7.2 NFS 연결 테스트  
  
```yaml  
# nfs-test-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: nfs-test  
spec:  
  containers:  
  - name: test  
    image: busybox  
    command:  
    - sh  
    - -c  
    - |  
      echo "Testing NFS mount..."  
      mount -t nfs4 218.55.125.24:/shared/data /mnt  
      if [ $? -eq 0 ]; then  
        echo "NFS mount successful"  
        ls -la /mnt  
      else  
        echo "NFS mount failed"  
      fi  
      sleep 3600  
    securityContext:  
      privileged: true  
    volumeMounts:  
    - name: nfs  
      mountPath: /test  
  volumes:  
  - name: nfs  
    nfs:  
      server: 218.55.125.24  
      path: /shared/data  
```  
  
```bash  
# 테스트 Pod 실행  
kubectl apply -f nfs-test-pod.yaml  
  
# 로그 확인  
kubectl logs nfs-test  
```  
  
---  
  
## 주의사항  
  
1. **NFS 버전**: 제공된 NFS 서버는 NFSv4 전용이므로 마운트 옵션 주의  
2. **권한 문제**: NFS 마운트 시 권한 문제가 발생할 수 있으므로 securityContext 설정 확인  
3. **데이터 영구성**: PV의 ReclaimPolicy에 따라 PVC 삭제 시 데이터 손실 가능  
4. **성능**: NFS는 네트워크 스토리지이므로 로컬 스토리지보다 성능이 낮을 수 있음  
5. **동시 접근**: ReadWriteMany 모드에서도 애플리케이션 레벨 동시성 제어 필요  
6. **백업**: 중요한 데이터는 정기적인 백업 필수