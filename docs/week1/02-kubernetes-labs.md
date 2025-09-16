# Kubernetes 아키텍처 파악: 실습

## 실습

### 실습 1: Pod 생성 및 관리

```bash
# 1. Pod 정의 파일 생성 (pod.yaml)
cat <<EOF > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
EOF

# 2. Pod 생성
kubectl apply -f pod.yaml

# 3. Pod 상태 확인
kubectl get pods
kubectl describe pod nginx-pod

# 4. Pod 로그 확인
kubectl logs nginx-pod

# 5. Pod에 접속
kubectl exec -it nginx-pod -- /bin/bash

# 6. Pod 삭제
kubectl delete -f pod.yaml
```

### 실습 2: Deployment와 Service 생성

```bash
# 1. Deployment 생성
kubectl create deployment webapp --image=nginx:latest --replicas=3

# 2. Deployment 확인
kubectl get deployments
kubectl get pods -l app=webapp

# 3. Service 생성 (LoadBalancer 타입)
kubectl expose deployment webapp --type=LoadBalancer --port=80

# 4. Service 확인
kubectl get services
kubectl describe service webapp

# 5. 스케일링
kubectl scale deployment webapp --replicas=5
kubectl get pods -w  # 실시간 모니터링

# 6. 이미지 업데이트
kubectl set image deployment/webapp nginx=nginx:1.21

# 7. 롤아웃 상태 확인
kubectl rollout status deployment/webapp

# 8. 롤백
kubectl rollout undo deployment/webapp

# 9. 정리
kubectl delete deployment webapp
kubectl delete service webapp
```

### 실습 3: Namespace와 ResourceQuota

```bash
# 1. Namespace 생성
kubectl create namespace dev
kubectl create namespace prod

# 2. Namespace 확인
kubectl get namespaces

# 3. 특정 Namespace에 리소스 생성
kubectl create deployment nginx --image=nginx -n dev

# 4. ResourceQuota 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: dev
spec:
  hard:
    pods: "2"
    requests.cpu: "1"
    requests.memory: 1Gi
EOF

# 5. ResourceQuota 확인
kubectl describe resourcequota compute-quota -n dev

# 6. 한계 테스트 (3개 Pod 생성 시도)
kubectl scale deployment nginx --replicas=3 -n dev

# 7. 정리
kubectl delete namespace dev
kubectl delete namespace prod
```

### 실습 4: ConfigMap과 Secret 사용

```bash
# 1. ConfigMap 생성
kubectl create configmap app-config \
  --from-literal=database_url=mysql://localhost:3306/mydb \
  --from-literal=api_key=public-key-12345

# 2. Secret 생성
kubectl create secret generic app-secret \
  --from-literal=username=admin \
  --from-literal=password=secretpassword

# 3. ConfigMap과 Secret을 사용하는 Pod 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ['sh', '-c', 'echo "DB: \$DATABASE_URL, User: \$USERNAME" && sleep 3600']
    env:
    - name: DATABASE_URL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: database_url
    - name: USERNAME
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: username
EOF

# 4. Pod 로그 확인
kubectl logs app-pod

# 5. 정리
kubectl delete pod app-pod
kubectl delete configmap app-config
kubectl delete secret app-secret
```

---

## 체크리스트

- [ ] Kubernetes의 필요성과 주요 기능 이해
- [ ] Master/Worker 노드 구조 이해
- [ ] Control Plane 구성 요소 역할 이해
- [ ] Worker Node 구성 요소 역할 이해
- [ ] Pod 개념과 생명주기 이해
- [ ] Service 타입별 차이점 이해
- [ ] Deployment를 통한 애플리케이션 관리
- [ ] Namespace를 통한 리소스 격리
- [ ] ConfigMap과 Secret 활용
- [ ] 레이블과 셀렉터 사용법 이해
- [ ] kubectl 명령어 숙련도

---

## 참고 자료

- [Kubernetes 공식 문서](https://kubernetes.io/ko/docs/)
- [Kubernetes API 레퍼런스](https://kubernetes.io/docs/reference/kubernetes-api/)
- [kubectl 치트시트](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Kubernetes 베스트 프랙티스](https://kubernetes.io/docs/concepts/configuration/overview/)