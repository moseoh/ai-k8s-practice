## 실습 환경  
  
- GCP VM 기반 Kubernetes 클러스터  
- Master Node: 1개, Worker Node: 3개  
  
---  
  
## 1. Service 기본 실습  
  
### 1.1 ClusterIP Service 실습  
  
#### 테스트 애플리케이션 배포  
  
```bash  
# nginx deployment 생성  
kubectl create deployment nginx --image=nginx:latest --replicas=3  
  
# deployment 확인  
kubectl get deployments  
kubectl get pods -o wide  
```  
  
#### ClusterIP Service 생성  
  
```yaml  
# clusterip-service.yaml  
apiVersion: v1  
kind: Service  
metadata:  
  name: nginx-clusterip  
spec:  
  type: ClusterIP  
  selector:  
    app: nginx-deploy  
  ports:  
    - port: 80  
      targetPort: 80  
      protocol: TCP  
```  
  
```bash  
# Service 적용  
kubectl apply -f clusterip-service.yaml  
  
# Service 확인  
kubectl get svc nginx-clusterip  
kubectl describe svc nginx-clusterip  
  
# 클러스터 내부에서 테스트  
kubectl run test-pod --image=busybox -it --rm -- wget -qO- nginx-clusterip  
```  
  
### 1.2 NodePort Service 실습  
  
#### NodePort Service 생성  
  
```yaml  
# nodeport-service.yaml  
apiVersion: v1  
kind: Service  
metadata:  
  name: nginx-nodeport  
spec:  
  type: NodePort  
  selector:  
    app: nginx-deploy  
  ports:  
    - port: 80  
      targetPort: 80  
      nodePort: 30080  # 30000-32767 범위  
```  
  
![img.png](img.png)  
  
control-plan, worker 어떤 노드에서도 접근 가능하다.  
노드에 kube-proxy가 떠있다면 NodePort를 통해 적절한 Pod로 이동된다.  
  
- http://34.64.180.195:30080/  
- http://34.64.127.73:30080/  
  
```bash  
# Service 적용  
kubectl apply -f nodeport-service.yaml  
  
# Service 확인  
kubectl get svc nginx-nodeport  
  
# 노드 IP 확인  
kubectl get nodes -o wideㅇ  
  
# 외부에서 테스트 (GCP VM의 외부 IP 사용)  
curl http://<NODE_EXTERNAL_IP>:30080  
```  
  
### 1.3 LoadBalancer Service 실습 (GCP)  
  
#### LoadBalancer Service 생성  
  
```yaml  
# loadbalancer-service.yaml  
apiVersion: v1  
kind: Service  
metadata:  
  name: nginx-loadbalancer  
spec:  
  type: LoadBalancer  
  selector:  
    app: nginx-deploy  
  ports:  
    - port: 80  
      targetPort: 80  
```  
  
```bash  
# Service 적용  
kubectl apply -f loadbalancer-service.yaml  
  
# External IP 할당 대기 (1-2분)  
kubectl get svc nginx-loadbalancer -w  
  
# 외부에서 테스트  
curl http://<EXTERNAL_IP>  
```  
  
현재 구성으로 GKE 가 아닌 일반 VM으로 LoadBalancer에 IP를 자동으로 할당해주지 않는다. MetalLB와 같은 추가적인 기술 필요  
  
---  
  
## 2. Service Discovery 실습  
  
### 2.1 DNS 기반 Service Discovery  
  
```bash  
# backend 서비스 생성  
kubectl create deployment backend --image=hashicorp/http-echo --port=5678 -n practice -- /http-echo -text="Backend Service"  
kubectl expose deployment backend --port=5678  
  
# frontend Pod에서 DNS 테스트  
kubectl run frontend --image=busybox -it --rm -- sh  
  
# Pod 내부에서 실행:  
nslookup backend # 같은 네임스페이스 인 경우 생략 가능  
nslookup backend.practice.svc.cluster.local  
#Server:    10.96.0.10  
#Address:   10.96.0.10:53  
#  
#Name:  backend.practice.svc.cluster.local  
#Address: 10.107.42.66  
  
wget -qO- backend:5678  
wget -qO- backend.practice.svc.cluster.local:5678  
#/ # wget -qO- backend:5678  
#Backend Service  
#/ # wget -qO- backend.practice.svc.cluster.local:5678  
#Backend Service  
```  
  
### 2.2 환경 변수 기반 Discovery  
  
```yaml  
# test-env-pod.yaml  
apiVersion: v1  
kind: Pod  
metadata:  
  name: env-test  
spec:  
  containers:  
    - name: test  
      image: busybox  
      command: [ 'sh', '-c', 'env | grep BACKEND; sleep 3600' ]  
```  
  
```bash  
# Pod 생성 및 환경 변수 확인  
kubectl apply -f test-env-pod.yaml  
kubectl logs env-test  
  
#/ # env | grep BACKEND  
#BACKEND_SERVICE_HOST=10.107.42.66  
#BACKEND_SERVICE_PORT=5678  
#BACKEND_PORT=tcp://10.107.42.66:5678  
#BACKEND_PORT_5678_TCP_ADDR=10.107.42.66  
#BACKEND_PORT_5678_TCP_PORT=5678  
#BACKEND_PORT_5678_TCP_PROTO=tcp  
#BACKEND_PORT_5678_TCP=tcp://10.107.42.66:5678  
```  
  
---  
  
## 3. Headless Service 실습  
  
### 3.1 Headless Service 생성  
  
```yaml  
# headless-service.yaml  
apiVersion: v1  
kind: Service  
metadata:  
  name: nginx-headless  
spec:  
  clusterIP: None  # Headless 설정  
  selector:  
    app: nginx-deploy  
  ports:  
    - port: 80  
      targetPort: 80  
---  
apiVersion: v1  
kind: Service  
metadata:  
  name: nginx-normal  
spec:  
  selector:  
    app: nginx-deploy  
  ports:  
    - port: 80  
      targetPort: 80  
```  
  
```bash  
# Service 생성  
kubectl apply -f headless-service.yaml  
  
# DNS 조회 비교  
kubectl run test --image=busybox -it --rm -- sh  
# Pod 내부에서:  
nslookup nginx-normal    # Service IP 반환  
nslookup nginx-headless  # Pod IP들 반환  
```  
  
#### 결과  
  
```shell  
ubuntu@k8s-control-plane-1:~$ k get svc -o wide  
NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE   SELECTOR  
nginx-normal     ClusterIP   10.96.115.133   <none>        80/TCP         68s   app=nginx-deploy  
  
/ # nslookup nginx-normal  
Server:    10.96.0.10  
Address:    10.96.0.10:53  
  
Name:   nginx-normal.practice.svc.cluster.local  
Address: 10.96.115.133  
  
  
ubuntu@k8s-control-plane-1:~$ k get pods -o wide  
NAME                                READY   STATUS    RESTARTS   AGE     IP              NODE         NOMINATED NODE   READINESS GATES  
nginx-deployment-546d459948-lw79v   1/1     Running   0          29h     10.244.109.73   k8s-node-1   <none>           <none>  
nginx-deployment-546d459948-t9vnz   1/1     Running   0          29h     10.244.140.77   k8s-node-2   <none>           <none>  
nginx-deployment-546d459948-wfbz4   1/1     Running   0          29h     10.244.76.137   k8s-node-3   <none>           <none>  
  
/ # nslookup nginx-headless  
Server:    10.96.0.10  
Address:    10.96.0.10:53  
  
Name:   nginx-headless.practice.svc.cluster.local  
Address: 10.244.76.137  
Name:   nginx-headless.practice.svc.cluster.local  
Address: 10.244.140.77  
Name:   nginx-headless.practice.svc.cluster.local  
Address: 10.244.109.73   
```  
  
---  
  
## 4. Session Affinity 실습  
  
### 4.1 ClientIP 기반 세션 고정  
  
```yaml  
# session-affinity.yaml  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: echo  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: echo  
  template:  
    metadata:  
      labels:  
        app: echo  
    spec:  
      containers:  
        - name: echo  
          image: hashicorp/http-echo  
          args:  
            - "-text=Pod: $(POD_NAME)"  
          env:  
            - name: POD_NAME  
              valueFrom:  
                fieldRef:  
                  fieldPath: metadata.name  
---  
apiVersion: v1  
kind: Service  
metadata:  
  name: echo-affinity  
spec:  
  sessionAffinity: ClientIP  
  sessionAffinityConfig:  
    clientIP:  
      timeoutSeconds: 10800  
  selector:  
    app: echo  
  ports:  
    - port: 5678  
      targetPort: 5678  
```  
  
```bash  
# 적용 및 테스트  
kubectl apply -f session-affinity.yaml  
  
# 여러 번 요청하면 같은 Pod로 라우팅됨  
kubectl run test --image=busybox -it --rm -- sh  
# Pod 내부에서:  
for i in $(seq 1 5); do wget -qO- echo-affinity:5678; done  
```  
  
#### 결과  
  
affinity service는 3개의 팟을 보유하고 있지만 고정된 pod으로 이동  
  
```shell  
ubuntu@k8s-control-plane-1:~/service$ k get all  
NAME                        READY   STATUS    RESTARTS   AGE  
pod/echo-6648d5c67b-gzj89   1/1     Running   0          13m  
pod/echo-6648d5c67b-hn96v   1/1     Running   0          13m  
pod/echo-6648d5c67b-wj8dh   1/1     Running   0          13m  
pod/test                    1/1     Running   0          13m  
  
NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE  
service/echo-affinity   ClusterIP   10.110.127.189   <none>        5678/TCP   13m  
  
NAME                   READY   UP-TO-DATE   AVAILABLE   AGE  
deployment.apps/echo   3/3     3            3           13m  
  
NAME                              DESIRED   CURRENT   READY   AGE  
replicaset.apps/echo-6648d5c67b   3         3         3       13m  
  
/ # for i in $(seq 1 5); do wget -qO- echo-affinity:5678; done  
Pod: echo-6648d5c67b-wj8dh  
Pod: echo-6648d5c67b-wj8dh  
Pod: echo-6648d5c67b-wj8dh  
Pod: echo-6648d5c67b-wj8dh  
Pod: echo-6648d5c67b-wj8dh  
```  
  
---  
  
## 5. Ingress Controller 설치 및 구성  
  
### 5.1 NGINX Ingress Controller 설치  
  
```bash  
# NGINX Ingress Controller 설치  
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.2/deploy/static/provider/cloud/deploy.yaml  
# 기본설정은 LoadBalancer. 실습 환경에서는 GKE 가 아니므로 IP 를 할당받을 수 없음  
kubectl patch svc ingress-nginx-controller -n ingress-nginx \  
      -p '{"spec":{"type":"NodePort","externalTrafficPolicy":"Local","ports":[{"name":"http","port":80,"targetPort":"http","nodePort":32080},{"name":"https","port":443,"targetPort":"https","nodePort":32443}]}}'  
        
# 설치 확인  
kubectl get pods -n ingress-nginx  
kubectl get svc -n ingress-nginx  
```  
  
---  
  
## 6. Ingress 리소스 실습  
  
### 6.1 호스트 기반 라우팅  
  
```yaml  
# host-routing.yaml  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: app1  
spec:  
  replicas: 2  
  selector:  
    matchLabels:  
      app: app1  
  template:  
    metadata:  
      labels:  
        app: app1  
    spec:  
      containers:  
        - name: app1  
          image: hashicorp/http-echo  
          args: [ "-text=App1" ]  
---  
apiVersion: v1  
kind: Service  
metadata:  
  name: app1-svc  
spec:  
  selector:  
    app: app1  
  ports:  
    - port: 5678  
---  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: app2  
spec:  
  replicas: 2  
  selector:  
    matchLabels:  
      app: app2  
  template:  
    metadata:  
      labels:  
        app: app2  
    spec:  
      containers:  
        - name: app2  
          image: hashicorp/http-echo  
          args: [ "-text=App2" ]  
---  
apiVersion: v1  
kind: Service  
metadata:  
  name: app2-svc  
spec:  
  selector:  
    app: app2  
  ports:  
    - port: 5678  
---  
apiVersion: networking.k8s.io/v1  
kind: Ingress  
metadata:  
  name: host-based-ingress  
  annotations:  
    nginx.ingress.kubernetes.io/rewrite-target: /  
spec:  
  ingressClassName: nginx  
  rules:  
    - host: app1.example.com  
      http:  
        paths:  
          - path: /  
            pathType: Prefix  
            backend:  
              service:  
                name: app1-svc  
                port:  
                  number: 5678  
    - host: app2.example.com  
      http:  
        paths:  
          - path: /  
            pathType: Prefix  
            backend:  
              service:  
                name: app2-svc  
                port:  
                  number: 5678  
```  
  
```bash  
# 적용  
kubectl apply -f host-routing.yaml  
  
# Ingress 확인  
kubectl get ingress  
kubectl describe ingress host-based-ingress  
```  
  
#### 결과:  
  
```shell  
# 내부 아이피  
curl -H "Host: app1.example.com" http://10.240.0.21:32080  
# App1  
curl -H "Host: app2.example.com" http://10.240.0.21:32080  
# App2  
  
# 외부 아이피  
curl -H "Host: app1.example.com" http://34.47.105.155:32080  
# App1  
curl -H "Host: app2.example.com" http://34.47.105.155:32080  
# App2  
```  
  
### 6.2 경로 기반 라우팅  
  
```yaml  
# path-routing.yaml  
apiVersion: networking.k8s.io/v1  
kind: Ingress  
metadata:  
  name: path-based-ingress  
  annotations:  
    nginx.ingress.kubernetes.io/rewrite-target: /$2  
    nginx.ingress.kubernetes.io/use-regex: "true"  
spec:  
  ingressClassName: nginx  
  rules:  
    - host: api.example.com  
      http:  
        paths:  
          - path: /app1(/|$)(.*)  
            pathType: ImplementationSpecific  
            backend:  
              service:  
                name: app1-svc  
                port:  
                  number: 5678  
          - path: /app2(/|$)(.*)  
            pathType: ImplementationSpecific  
            backend:  
              service:  
                name: app2-svc  
                port:  
                  number: 5678  
```  
  
```bash  
# 적용  
kubectl apply -f path-routing.yaml  
```  
  
#### 결과:  
  
```shell  
# 내부 아이피  
curl -H "Host: api.example.com" http://10.240.0.21:32080/app1  
# App1  
curl -H "Host: api.example.com" http://10.240.0.21:32080/app2  
# App2  
  
# 외부 아이피  
curl -H "Host: api.example.com" http://34.47.105.155:32080/app1  
# App1  
curl -H "Host: api.example.com" http://34.47.105.155:32080/app2  
# App2  
```  
  
---  
  
## 7. TLS/SSL 설정 실습  
  
### 7.1 자체 서명 인증서 생성  
  
```bash  
# 인증서 생성  
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \  
  -keyout tls.key -out tls.crt \  
  -subj "/CN=secure.example.com/O=example"  
  
# Secret 생성  
kubectl create secret tls tls-secret --key tls.key --cert tls.crt  
  
# Secret 확인  
kubectl get secret tls-secret  
kubectl describe secret tls-secret  
```  
  
### 7.2 TLS Ingress 구성  
  
```yaml  
# tls-ingress.yaml  
apiVersion: networking.k8s.io/v1  
kind: Ingress  
metadata:  
  name: tls-ingress  
  annotations:  
    nginx.ingress.kubernetes.io/ssl-redirect: "true"  
spec:  
  ingressClassName: nginx  
  tls:  
    - hosts:  
        - secure.example.com  
      secretName: tls-secret  
  rules:  
    - host: secure.example.com  
      http:  
        paths:  
          - path: /  
            pathType: Prefix  
            backend:  
              service:  
                name: app1-svc  
                port:  
                  number: 5678  
```  
  
```bash  
# 적용  
kubectl apply -f tls-ingress.yaml  
  
# HTTPS 테스트  
curl -k --resolve secure.example.com:443:$INGRESS_IP https://secure.example.com  
```  
  
#### 결과:  
  
```shell  
# 내부 아이피  
curl -k -H "Host: secure.example.com" https://10.240.0.21:32443  
# App1  
  
# 외부 아이피  
curl -k -H "Host: secure.example.com" https://34.47.105.155:32443  
# App1  
```  
  
---  
  
## 8. Ingress 고급 기능  
  
### 8.1 Rate Limiting  
  
```yaml  
# rate-limit.yaml  
apiVersion: networking.k8s.io/v1  
kind: Ingress  
metadata:  
  name: rate-limit-ingress  
  annotations:  
    nginx.ingress.kubernetes.io/limit-rps: "1"  
    nginx.ingress.kubernetes.io/limit-burst: "1"  
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "1"  
    nginx.ingress.kubernetes.io/limit-rpm: "30"  
spec:  
  ingressClassName: nginx  
  rules:  
    - host: limited.example.com  
      http:  
        paths:  
          - path: /  
            pathType: Prefix  
            backend:  
              service:  
                name: app1-svc  
                port:  
                  number: 5678  
```  
  
```bash  
# 적용 및 테스트  
kubectl apply -f rate-limit.yaml  
```  
  
#### 결과  
  
```shell  
# 빠른 연속 요청으로 rate limit 테스트  
for i in {1..3}; do  
  curl -H "Host: limited.example.com" http://10.240.0.21:32080  
  echo  
done  
  
#App1  
#  
#App1  
#  
#App1  
#  
#App1  
#  
#App1  
#  
#App1  
#  
#<html>  
#<head><title>503 Service Temporarily Unavailable</title></head>  
#<body>  
#<center><h1>503 Service Temporarily Unavailable</h1></center>  
#<hr><center>nginx</center>  
#</body>  
#</html>  
```  
  
- `limit-rps`는 초당 처리량, `limit-burst`는 순간적으로 허용할 추가 버퍼  
- `limit-burst-multiplier` 기본값이 5라서 `limit-burst`를 지정하지 않으면 `limit-rps x 5`만큼 버스트 허용  
- 첫 요청이 통과하는 건 버킷이 기본적으로 가득 차 있기 때문이라 정상 동작. 완전히 차단하려면 애초에 Burst 값이 있는 다른 알고리즘을 써야 한다.  
  
### 8.2 Basic Authentication  
  
```bash  
# 인증 파일 생성  
htpasswd -c auth user1  
# 패스워드 입력  
  
# Secret 생성  
kubectl create secret generic basic-auth --from-file=auth  
```  
  
```yaml  
# basic-auth-ingress.yaml  
apiVersion: networking.k8s.io/v1  
kind: Ingress  
metadata:  
  name: auth-ingress  
  annotations:  
    nginx.ingress.kubernetes.io/auth-type: basic  
    nginx.ingress.kubernetes.io/auth-secret: basic-auth  
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'  
spec:  
  ingressClassName: nginx  
  rules:  
    - host: protected.example.com  
      http:  
        paths:  
          - path: /  
            pathType: Prefix  
            backend:  
              service:  
                name: app1-svc  
                port:  
                  number: 5678  
```  
  
결과:  
  
ID, PW 를 지정하지 않으면 401 에러 발생.  
  
```bash  
# 테스트  
curl --resolve protected.example.com:32080:10.240.0.21 http://protected.example.com:32080  
curl -u user1:qwe123 --resolve protected.example.com:32080:10.240.0.21 http://protected.example.com:32080  
  
curl --resolve protected.example.com:32080:34.47.105.155 http://protected.example.com:32080  
#<html>  
#<head><title>401 Authorization Required</title></head>  
#<body>  
#<center><h1>401 Authorization Required</h1></center>  
#<hr><center>nginx</center>  
#</body>  
#</html>  
curl -u user1:qwe123 --resolve protected.example.com:32080:34.47.105.155 http://protected.example.com:32080  
#App1  
```  
  
---  
  
## 9. Blue-Green 배포 실습  
  
### 9.1 Blue-Green 환경 구성  
  
```yaml  
# blue-green.yaml  
# Blue Deployment  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: app-blue  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: myapp  
      version: blue  
  template:  
    metadata:  
      labels:  
        app: myapp  
        version: blue  
    spec:  
      containers:  
        - name: app  
          image: hashicorp/http-echo  
          args: [ "-text=Blue Version" ]  
---  
# Green Deployment  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: app-green  
spec:  
  replicas: 3  
  selector:  
    matchLabels:  
      app: myapp  
      version: green  
  template:  
    metadata:  
      labels:  
        app: myapp  
        version: green  
    spec:  
      containers:  
        - name: app  
          image: hashicorp/http-echo  
          args: [ "-text=Green Version" ]  
---  
# Service (Blue 초기 설정)  
apiVersion: v1  
kind: Service  
metadata:  
  name: myapp-service  
spec:  
  selector:  
    app: myapp  
    version: blue  # 초기에는 Blue로 라우팅  
  ports:  
    - port: 5678  
```  
  
결과:  
  
```bash  
# 배포  
kubectl apply -f blue-green.yaml  
  
# ingress controller 없이 임시 확인용 포트 포워딩.  
kubectl port-forward svc/myapp-service 8080:5678  
  
# Blue, Green 버전 둘다 실행중  
ubuntu@k8s-control-plane-1:~$ k get all  
NAME                             READY   STATUS    RESTARTS   AGE  
pod/app-blue-6967b848b6-96cb4    1/1     Running   0          3m29s  
pod/app-blue-6967b848b6-dq2ql    1/1     Running   0          3m29s  
pod/app-blue-6967b848b6-z9hjv    1/1     Running   0          3m29s  
pod/app-green-85f644f986-2g57p   1/1     Running   0          3m29s  
pod/app-green-85f644f986-5fc72   1/1     Running   0          3m29s  
pod/app-green-85f644f986-7bglk   1/1     Running   0          3m29s  
  
NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE  
service/myapp-service   ClusterIP   10.106.14.51   <none>        5678/TCP   3m30s  
  
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE  
deployment.apps/app-blue    3/3     3            3           3m30s  
deployment.apps/app-green   3/3     3            3           3m30s  
  
NAME                                   DESIRED   CURRENT   READY   AGE  
replicaset.apps/app-blue-6967b848b6    3         3         3       3m29s  
replicaset.apps/app-green-85f644f986   3         3         3       3m29s  
  
# 현재 Blue Version으로 라우팅  
ubuntu@k8s-control-plane-1:~$ curl http://localhost:8080  
#Blue Version  
ubuntu@k8s-control-plane-1:~$ curl http://localhost:8080  
#Blue Version  
  
# Blue에서 Green으로 전환  
kubectl patch service myapp-service -p '{"spec":{"selector":{"version":"green"}}}'  
  
# Green Version으로 라우팅  
ubuntu@k8s-control-plane-1:~$ curl http://localhost:8080  
#Green Version  
ubuntu@k8s-control-plane-1:~$ curl http://localhost:8080  
#Green Version  
ubuntu@k8s-control-plane-1:~$   
  
# 다시 Blue로 롤백  
kubectl patch service myapp-service -p '{"spec":{"selector":{"version":"blue"}}}'  
```  
  
---  
  
## 10. 트러블슈팅  
  
### 10.1 Service Endpoint 확인  
  
```bash  
# Endpoint 확인  
kubectl get endpoints  
kubectl describe endpoints nginx-clusterip  
  
# Service와 Pod Label 매칭 확인  
kubectl get pods --show-labels  
kubectl get svc nginx-clusterip -o yaml | grep -A5 selector  
```  
  
### 10.2 DNS 문제 해결  
  
```bash  
# CoreDNS 상태 확인  
kubectl get pods -n kube-system -l k8s-app=kube-dns  
  
# DNS 해석 테스트  
kubectl run dns-test --image=busybox -it --rm -- nslookup kubernetes.default  
  
# CoreDNS 로그 확인  
kubectl logs -n kube-system -l k8s-app=kube-dns  
```  
  
### 10.3 Ingress 디버깅  
  
```bash  
# Ingress Controller 로그  
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx  
  
# Ingress 상태 확인  
kubectl describe ingress  
  
# Backend 상태 확인  
kubectl get pods -l app=nginx  
kubectl get svc  
kubectl get endpoints  
```  
  
### 10.4 네트워크 연결성 테스트  
  
```bash  
# Pod 간 연결성  
kubectl run test --image=nicolaka/netshoot -it --rm -- bash  
# 내부에서:  
curl nginx-clusterip  
nslookup nginx-clusterip  
traceroute nginx-clusterip  
```  
  
---  
  
## 주의사항  
  
1. **GCP 방화벽**: NodePort나 LoadBalancer 사용 시 GCP 방화벽 규칙 확인  
2. **비용**: LoadBalancer 타입 Service는 GCP Load Balancer를 생성하여 비용 발생  
3. **DNS**: 실제 도메인이 없을 경우 `/etc/hosts` 파일 수정이나 `curl --resolve` 사용  
4. **인증서**: 프로덕션에서는 Let's Encrypt 등 공인 인증서 사용 권장  
5. **리소스 정리**: 실습 후 불필요한 리소스 삭제로 비용 절감