## 실습 환경  

- GCP VM 기반 Kubernetes 클러스터  
- Master Node: 1개, Worker Node: 3개  
  
---  
  
## 1. ConfigMap 기본 실습  
  
### 1.1 리터럴 값으로 ConfigMap 생성  
  
```bash  
# 명령어로 ConfigMap 생성  
kubectl create configmap app-config \  
  --from-literal=database_host=mysql.example.com \  
  --from-literal=database_port=3306 \  
  --from-literal=feature_flag=enabled  
  
# ConfigMap 확인  
kubectl get configmap app-config  
kubectl describe configmap app-config  
  
# YAML 형식으로 확인  
kubectl get configmap app-config -o yaml  
```  
  
### 1.2 파일로 ConfigMap 생성  
  
```bash  
# 설정 파일 생성  
cat > app.properties <<EOF  
# Application Configuration  
app.name=MyApplication  
app.version=1.0.0  
app.environment=development  
debug.enabled=true  
max.connections=100  
EOF  
  
# 파일로부터 ConfigMap 생성  
kubectl create configmap app-properties --from-file=app.properties  
  
# 여러 파일로 ConfigMap 생성  
cat > database.conf <<EOF  
[database]  
host = localhost  
port = 3306  
name = myapp  
EOF  
  
kubectl create configmap multi-config \  
  --from-file=app.properties \  
  --from-file=database.conf  
  
# 확인  
kubectl describe configmap multi-config  
```  
  
### 1.3 YAML 파일로 ConfigMap 생성  
  
```yaml  
# configmap-yaml.yaml  
apiVersion: v1  
kind: ConfigMap  
metadata:  
  name: game-config  
data:  
  # 단순 키-값 쌍  
  player_initial_lives: "3"  
  ui_properties_file_name: "user-interface.properties"  
  
  # 파일 형태의 데이터  
  game.properties: |  
    enemies=aliens  
    lives=3  
    enemies.cheat=true  
    enemies.cheat.level=noGoodRotten  
    secret.code.passphrase=UUDDLRLRBABAS  
    secret.code.allowed=true  
  
  user-interface.properties: |  
    color.good=purple  
    color.bad=yellow  
    allow.textmode=true  
    how.nice.to.look=fairlyNice  
```  
  
```bash  
# 적용  
kubectl apply -f configmap-yaml.yaml  
  
# 확인  
kubectl get configmap game-config -o yaml  
```  
  
---  
  
## 2. ConfigMap 사용 패턴  
  
### 2.1 환경 변수로 주입  
  
```yaml  
# configmap-env.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: configmap-env-pod  
spec:  
  containers:  
  - name: test-container  
    image: busybox  
    command: ['sh', '-c', 'env | grep -E "DATABASE_|FEATURE_" && sleep 3600']  
    env:  
    # 개별 키 매핑  
    - name: DATABASE_HOST  
      valueFrom:  
        configMapKeyRef:  
          name: app-config  
          key: database_host  
    - name: DATABASE_PORT  
      valueFrom:  
        configMapKeyRef:  
          name: app-config  
          key: database_port  
    - name: FEATURE_FLAG  
      valueFrom:  
        configMapKeyRef:  
          name: app-config  
          key: feature_flag  
```  
  
```bash  
# Pod 생성  
kubectl apply -f configmap-env.yaml  
  
# 환경 변수 확인  
kubectl logs configmap-env-pod  
#DATABASE_PORT=3306  
#FEATURE_FLAG=enabled  
#DATABASE_HOST=mysql.example.com  
  
# 상세 확인  
kubectl exec configmap-env-pod -- env | sort  
```  
  
### 2.2 전체 ConfigMap을 환경 변수로 주입  
  
```yaml  
# configmap-envfrom.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: configmap-envfrom-pod  
spec:  
  containers:  
  - name: test-container  
    image: busybox  
    command: ['sh', '-c', 'env && sleep 3600']  
    envFrom:  
    - configMapRef:  
        name: app-config  
      prefix: CONFIG_  # 선택적 접두사  
```  
  
`app-config`의 config 들을 전부 `CONFIG_` 프리픽스를 붙여 주입  
  
```bash  
# 적용 및 확인  
kubectl apply -f configmap-envfrom.yaml  
  
kubectl logs configmap-envfrom-pod | grep CONFIG_  
#CONFIG_database_host=mysql.example.com  
#CONFIG_database_port=3306  
#CONFIG_feature_flag=enabled  
```  
  
### 2.3 볼륨으로 마운트  
  
```yaml  
# configmap-volume.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: configmap-volume-pod  
spec:  
  containers:  
  - name: test-container  
    image: nginx  
    volumeMounts:  
    - name: config-volume  
      mountPath: /etc/config  
  volumes:  
  - name: config-volume  
    configMap:  
      name: game-config  
```  
  
```bash  
# Pod 생성  
kubectl apply -f configmap-volume.yaml  
  
# 마운트된 파일 확인  
kubectl exec configmap-volume-pod -- ls -la /etc/config/  
kubectl exec configmap-volume-pod -- cat /etc/config/game.properties  
  
ubuntu@k8s-control-plane-1:~/configmap$ kubectl exec configmap-volume-pod -- cat /etc/config/game.properties  
#enemies=aliens  
#lives=3  
#enemies.cheat=true  
#enemies.cheat.level=noGoodRotten  
#secret.code.passphrase=UUDDLRLRBABAS  
#secret.code.allowed=true  
  
# 실시간 업데이트 테스트  
kubectl edit configmap game-config  
# player_initial_lives를 "5"로 변경  
  
# 약 1분 후 확인  
ubuntu@k8s-control-plane-1:~/configmap$ kubectl exec configmap-volume-pod -- cat /etc/config/player_initial_lives  
#5  
```  
  
### 2.4 선택적 파일 마운트  
  
```yaml  
# configmap-selective.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: configmap-selective-pod  
spec:  
  containers:  
  - name: test-container  
    image: nginx  
    volumeMounts:  
    - name: config-volume  
      mountPath: /etc/game  
  volumes:  
  - name: config-volume  
    configMap:  
      name: game-config  
      items:  
      - key: game.properties  
        path: game.conf  # 다른 이름으로 마운트  
      - key: user-interface.properties  
        path: ui.conf  
```  
  
```bash  
# 적용 및 확인  
kubectl apply -f configmap-selective.yaml  
kubectl exec configmap-selective-pod -- ls -la /etc/game/  
#lrwxrwxrwx 1 root root   16 Sep 24 11:25 game.conf -> ..data/game.conf  
#lrwxrwxrwx 1 root root   14 Sep 24 11:25 ui.conf -> ..data/ui.conf  
  
kubectl exec configmap-selective-pod -- cat /etc/game/game.conf  
#enemies=aliens  
#lives=3  
#enemies.cheat=true  
#enemies.cheat.level=noGoodRotten  
#secret.code.passphrase=UUDDLRLRBABAS  
#secret.code.allowed=true  
```  
  
---  
  
## 3. Secret 기본 실습  
  
### 3.1 Generic Secret 생성  
  
```bash  
# 리터럴 값으로 Secret 생성  
kubectl create secret generic db-secret \  
  --from-literal=username=dbuser \  
  --from-literal=password='S3cur3P@ssw0rd!'  
  
# Secret 확인  
kubectl get secrets  
kubectl describe secret db-secret  
  
# Base64 인코딩된 값 확인  
kubectl get secret db-secret -o yaml  
  
# 디코딩하여 확인  
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d  
```  
  
### 3.2 파일로 Secret 생성  
  
```bash  
# 인증 파일 생성  
echo -n 'admin' > username.txt  
echo -n 'admin123!@#' > password.txt  
  
# Secret 생성  
kubectl create secret generic user-pass \  
  --from-file=username.txt \  
  --from-file=password.txt  
  
# 정리  
rm username.txt password.txt  
  
# 확인  
kubectl get secret user-pass -o yaml  
```  
  
### 3.3 YAML로 Secret 생성  
  
```yaml  
# secret-yaml.yaml  
apiVersion: v1  
kind: Secret  
metadata:  
  name: api-secret  
type: Opaque  
data: # base64 인코딩 된 값만 넣을 수 있다.  
  # echo -n 'myapi' | base64  
  api-key: bXlhcGk=  
  # echo -n 'mysecret' | base64  
  api-secret: bXlzZWNyZXQ=  
stringData:  # 자동 base64 인코딩  
  plain-text: "This will be encoded automatically"  
```  
  
```bash  
# 적용  
kubectl apply -f secret-yaml.yaml  
  
# 확인  
kubectl get secret api-secret -o yaml  
```  
  
---  
  
## 4. Secret 사용 패턴  
  
### 4.1 환경 변수로 Secret 사용  
  
```yaml  
# secret-env.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: secret-env-pod  
spec:  
  containers:  
  - name: mycontainer  
    image: mysql:5.7  
    env:  
    - name: MYSQL_ROOT_PASSWORD  
      valueFrom:  
        secretKeyRef:  
          name: db-secret  
          key: password  
    - name: MYSQL_USER  
      valueFrom:  
        secretKeyRef:  
          name: db-secret  
          key: username  
    - name: MYSQL_PASSWORD  
      valueFrom:  
        secretKeyRef:  
          name: db-secret  
          key: password  
```  
  
```bash  
# Pod 생성  
kubectl apply -f secret-env.yaml  
  
# 환경 변수 확인 (주의: 실제로는 Secret 값을 로그에 남기면 안됨)  
kubectl exec secret-env-pod -- env | grep MYSQL_  
#MYSQL_MAJOR=5.7  
#MYSQL_VERSION=5.7.44-1.el7  
#MYSQL_SHELL_VERSION=8.0.35-1.el7  
#MYSQL_ROOT_PASSWORD=S3cur3P@ssw0rd!  
#MYSQL_USER=dbuser  
#MYSQL_PASSWORD=S3cur3P@ssw0rd!  
```  
  
### 4.2 볼륨으로 Secret 마운트  
  
```yaml  
# secret-volume.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: secret-volume-pod  
spec:  
  containers:  
  - name: test-container  
    image: nginx  
    volumeMounts:  
    - name: secret-volume  
      mountPath: /etc/secret  
      readOnly: true  
  volumes:  
  - name: secret-volume  
    secret:  
      secretName: user-pass  
      defaultMode: 0400  # 파일 권한 설정  
```  
  
```bash  
# Pod 생성  
kubectl apply -f secret-volume.yaml  
  
# 마운트된 Secret 확인  
kubectl exec secret-volume-pod -- ls -la /etc/secret/  
kubectl exec secret-volume-pod -- cat /etc/secret/username.txt  
```  
  
---  
  
## 5. 특수 Secret 타입  
  
### 5.1 Docker Registry Secret  
  
```bash  
# Docker Hub 인증 정보 Secret 생성  
kubectl create secret docker-registry docker-hub-secret \  
  --docker-server=docker.io \  
  --docker-username=<your-username> \  
  --docker-password=<your-password> \  
  --docker-email=<your-email>  
  
# 확인  
kubectl get secret docker-hub-secret -o yaml  
```  
  
```yaml  
# private-image-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: private-image-pod  
spec:  
  containers:  
  - name: private-container  
    image: <private-registry>/<image>:<tag>  
  imagePullSecrets:  
  - name: docker-hub-secret  
```  
  
### 5.2 TLS Secret  
  
```bash  
# 자체 서명 인증서 생성  
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \  
  -keyout tls.key -out tls.crt \  
  -subj "/CN=myapp.example.com/O=example"  
  
# TLS Secret 생성  
kubectl create secret tls tls-secret \  
  --cert=tls.crt \  
  --key=tls.key  
  
# 확인  
kubectl describe secret tls-secret  
```  
  
```yaml  
# tls-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: tls-pod  
spec:  
  containers:  
  - name: nginx  
    image: nginx  
    volumeMounts:  
    - name: tls  
      mountPath: /etc/nginx/ssl  
      readOnly: true  
  volumes:  
  - name: tls  
    secret:  
      secretName: tls-secret  
      items:  
      - key: tls.crt  
        path: server.crt  
      - key: tls.key  
        path: server.key  
```  
  
---  
  
## 6. ConfigMap과 Secret 결합 사용  
  
### 6.1 애플리케이션 완전 구성  
  
```yaml  
# complete-app.yaml  
apiVersion: v1  
kind: ConfigMap  
metadata:  
  name: app-config  
data:  
  app.conf: |  
    server {  
        listen 80;  
        server_name example.com;  
        location / {  
            proxy_pass http://backend:8080;  
        }  
    }  
---  
apiVersion: v1  
kind: Secret  
metadata:  
  name: app-secret  
type: Opaque  
stringData:  
  db-password: "VerySecurePassword123!"  
  api-key: "sk_test_1234567890"  
---  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: webapp  
spec:  
  replicas: 2  
  selector:  
    matchLabels:  
      app: webapp  
  template:  
    metadata:  
      labels:  
        app: webapp  
    spec:  
      containers:  
      - name: app  
        image: nginx  
        env:  
        - name: DB_PASSWORD  
          valueFrom:  
            secretKeyRef:  
              name: app-secret  
              key: db-password  
        - name: API_KEY  
          valueFrom:  
            secretKeyRef:  
              name: app-secret  
              key: api-key  
        volumeMounts:  
        - name: config  
          mountPath: /etc/nginx/conf.d  
        - name: secrets  
          mountPath: /etc/secrets  
          readOnly: true  
      volumes:  
      - name: config  
        configMap:  
          name: app-config  
      - name: secrets  
        secret:  
          secretName: app-secret  
          defaultMode: 0400  
```  
  
```bash  
# 적용  
kubectl apply -f complete-app.yaml  
  
# 확인  
kubectl get pods -l app=webapp  
kubectl exec -it $(kubectl get pod -l app=webapp -o jsonpath='{.items[0].metadata.name}') -- bash  
  
# Pod 내부에서 확인  
cat /etc/nginx/conf.d/app.conf  
ls -la /etc/secrets/  
env | grep -E "DB_PASSWORD|API_KEY"  
```  
  
---  
  
## 7. 보안 Best Practices  
  
### 7.1 RBAC로 Secret 접근 제어  
  
```yaml  
# secret-rbac.yaml  
# Secret 생성  
apiVersion: v1  
kind: Secret  
metadata:  
  name: sensitive-secret  
type: Opaque  
stringData:  
  sensitive-data: "very-sensitive-information"  
---  
# ServiceAccount  
apiVersion: v1  
kind: ServiceAccount  
metadata:  
  name: secret-reader  
---  
# Role - Secret 읽기 권한  
apiVersion: rbac.authorization.k8s.io/v1  
kind: Role  
metadata:  
  name: secret-reader-role  
rules:  
- apiGroups: [""]  
  resources: ["secrets"]  
  resourceNames: ["sensitive-secret"]  
  verbs: ["get", "list"]  
---  
# RoleBinding  
apiVersion: rbac.authorization.k8s.io/v1  
kind: RoleBinding  
metadata:  
  name: secret-reader-binding  
roleRef:  
  apiGroup: rbac.authorization.k8s.io  
  kind: Role  
  name: secret-reader-role  
subjects:  
- kind: ServiceAccount  
  name: secret-reader  
```  
  
```bash  
# 적용  
kubectl apply -f secret-rbac.yaml  
  
# Pod에서 ServiceAccount 사용  
cat > secret-reader-pod.yaml <<EOF  
apiVersion: v1  
kind: Pod  
metadata:  
  name: secret-reader-pod  
spec:  
  serviceAccountName: secret-reader  
  containers:  
  - name: reader  
    image: bitnami/kubectl  
    command: ['sh', '-c', 'sleep 3600']  
EOF  
  
kubectl apply -f secret-reader-pod.yaml  
  
# ServiceAccount로 Secret 접근 테스트  
kubectl exec secret-reader-pod -- kubectl get secret sensitive-secret  
#NAME               TYPE     DATA   AGE  
#sensitive-secret   Opaque   1      24s  
kubectl exec secret-reader-pod -- kubectl get secret other-secret  # 실패  
#Error from server (Forbidden): secrets "user-pass" is forbidden: User "system:serviceaccount:practice:secret-reader" cannot get resource "secrets" in API group "" in the namespace "practice"  
#command terminated with exit code 1  
```  
  
---  
  
## 8 동적 설정 업데이트  
  
### 8.1 ConfigMap Hot Reload 패턴  
  
```yaml  
# hot-reload-app.yaml  
apiVersion: v1  
kind: ConfigMap  
metadata:  
  name: reload-config  
data:  
  config.yaml: |  
    feature_flags:  
      new_feature: false  
      beta_mode: false  
    settings:  
      cache_timeout: 60  
---  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: config-watcher  
spec:  
  replicas: 1  
  selector:  
    matchLabels:  
      app: config-watcher  
  template:  
    metadata:  
      labels:  
        app: config-watcher  
    spec:  
      containers:  
      - name: app  
        image: busybox  
        command:  
        - sh  
        - -c  
        - |  
          while true; do  
            echo "=== Config at $(date) ==="  
            cat /config/config.yaml  
            sleep 10  
          done  
        volumeMounts:  
        - name: config  
          mountPath: /config  
      volumes:  
      - name: config  
        configMap:  
          name: reload-config  
```  
  
```bash  
# 배포  
kubectl apply -f hot-reload-app.yaml  
  
# 로그 확인  
kubectl logs -f deployment/config-watcher  
  
# 다른 터미널에서 ConfigMap 업데이트  
kubectl edit configmap reload-config  
# new_feature를 true로 변경  
  
# 약 1분 후 로그에서 변경 확인  
```  
  
---  
  
## 9. 트러블슈팅  
  
### 9.1 ConfigMap/Secret 문제 해결  
  
```bash  
# ConfigMap이 Pod에 적용되지 않을 때  
# 1. ConfigMap 존재 확인  
kubectl get configmap  
  
# 2. Pod의 Volume/Env 설정 확인  
kubectl describe pod <pod-name>  
  
# 3. 네임스페이스 확인  
kubectl get configmap -n <namespace>  
  
# 4. Pod 이벤트 확인  
kubectl get events --sort-by='.lastTimestamp'  
```  
  
### 9.2 Secret 디버깅  
  
```bash  
# Secret 데이터 확인 (Base64 디코딩)  
kubectl get secret <secret-name> -o jsonpath='{.data}' | jq '.'  
  
# 특정 키 디코딩  
kubectl get secret <secret-name> -o jsonpath='{.data.<key>}' | base64 -d  
  
# Pod에서 Secret 마운트 확인  
kubectl exec <pod-name> -- ls -la /path/to/secret  
  
# Secret 권한 문제  
kubectl exec <pod-name> -- stat /path/to/secret/file  
```  
  
### 9.3 업데이트 지연 문제  
  
```bash  
# ConfigMap 업데이트 후 반영 확인  
# 1. ConfigMap 수정 시간 확인  
kubectl get configmap <name> -o jsonpath='{.metadata.resourceVersion}'  
  
# 2. Pod 내부 파일 확인 (약 1분 대기)  
kubectl exec <pod> -- cat /path/to/config  
  
# 3. 즉시 반영이 필요한 경우 Pod 재시작  
kubectl rollout restart deployment/<name>  
```  
  
---  
  
## 주의사항  
  
1. **Secret 보안**: Secret 값을 로그나 환경 변수로 출력하지 않도록 주의  
2. **Base64는 암호화가 아님**: Base64는 단순 인코딩이므로 실제 보안이 필요한 경우 암호화 솔루션 사용  
3. **볼륨 업데이트 지연**: ConfigMap/Secret 볼륨은 약 1분의 동기화 지연 존재  
4. **리소스 제한**: ConfigMap과 Secret은 1MB 크기 제한  
5. **네임스페이스 격리**: ConfigMap과 Secret은 네임스페이스 범위 리소스  
6. **버전 관리**: 민감한 정보는 Git에 커밋하지 않도록 주의