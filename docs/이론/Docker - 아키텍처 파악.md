## 목차

1. [컨테이너란?](#컨테이너란)
2. [Docker 기본](#docker-기본)
3. [Docker Best Practices](#docker-best-practices)

---

## 컨테이너란?

### 정의

컨테이너는 애플리케이션과 그 실행에 필요한 모든 종속성을 패키징한 경량화된 실행 환경입니다.

### 주요 특징

- **격리성**: 프로세스와 파일 시스템이 호스트와 분리됨
- **이식성**: 어떤 환경에서도 동일하게 실행 가능
- **경량성**: VM보다 리소스 사용량이 적음
- **빠른 시작**: 초 단위로 시작 가능

### 가상머신(VM) vs 컨테이너

| 구분      | 가상머신    | 컨테이너     |
|---------|---------|----------|
| 가상화 수준  | 하드웨어 수준 | OS 수준    |
| 게스트 OS  | 필요      | 불필요      |
| 크기      | GB 단위   | MB 단위    |
| 시작 시간   | 분 단위    | 초 단위     |
| 리소스 효율성 | 낮음      | 높음       |
| 격리 수준   | 강함      | 상대적으로 약함 |

### 컨테이너 기술의 핵심 개념

#### Linux 네임스페이스 (Namespaces)

- **PID 네임스페이스**: 프로세스 격리
- **Network 네임스페이스**: 네트워크 인터페이스 격리
- **Mount 네임스페이스**: 파일 시스템 마운트 포인트 격리
- **UTS 네임스페이스**: 호스트명과 도메인명 격리
- **IPC 네임스페이스**: 프로세스 간 통신 격리
- **User 네임스페이스**: 사용자와 그룹 ID 격리

#### Control Groups (cgroups)

- CPU, 메모리, 디스크 I/O 등 리소스 사용량 제한
- 리소스 사용량 모니터링
- 프로세스 그룹의 우선순위 설정

---

## Docker 기본

### Docker 아키텍처

```
┌─────────────────────────────────────────┐
│            Docker Client                │
│         (docker build, run, pull)       │
└────────────────┬────────────────────────┘
                 │ REST API
┌────────────────▼────────────────────────┐
│            Docker Daemon                │
│              (dockerd)                  │
├─────────────────────────────────────────┤
│   Images  │  Containers  │  Networks    │
│           │              │  Volumes     │
└─────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│          Container Runtime              │
│            (containerd)                 │
└─────────────────────────────────────────┘
```    

### Docker 구성 요소

#### 1. Docker Client

- 사용자가 Docker와 상호작용하는 주요 방법
- `docker` 명령어를 통해 Docker daemon과 통신
- Docker API를 사용하여 Docker daemon과 통신

#### 2. Docker Daemon (dockerd)

- Docker API 요청을 수신하고 처리
- 이미지, 컨테이너, 네트워크, 볼륨 등 Docker 객체 관리
- 다른 daemon과도 통신 가능

#### 3. Docker Registry

- Docker 이미지를 저장하는 저장소
- Docker Hub: 공식 퍼블릭 레지스트리
- Private Registry: 조직 내부용 레지스트리 구축 가능

### 핵심 개념

#### Docker Image

- 컨테이너 실행에 필요한 파일과 설정을 담은 읽기 전용 템플릿
- 레이어 구조로 효율적인 저장 및 전송
- Dockerfile로 정의

**이미지 레이어 구조:**

```
┌─────────────────────┐
│   애플리케이션 코드      │ ← 최상위 레이어
├─────────────────────┤
│    라이브러리/의존성     │
├─────────────────────┤
│    런타임 환경        │
├─────────────────────┤
│    베이스 OS          │ ← 베이스 레이어
└─────────────────────┘
```

#### Docker Container

- 이미지의 실행 가능한 인스턴스
- 격리된 프로세스로 실행
- 생성, 시작, 중지, 삭제 가능
- 컨테이너 레이어(쓰기 가능)를 이미지 위에 추가

#### Docker Volume

- 컨테이너에서 생성하고 사용하는 데이터를 유지
- 컨테이너 생명주기와 독립적
- 여러 컨테이너 간 공유 가능

#### Docker Network

- 컨테이너 간 통신을 가능하게 함
- 다양한 네트워크 드라이버 지원:
    - **bridge**: 기본 네트워크 드라이버
    - **host**: 호스트 네트워크 직접 사용
    - **overlay**: 여러 Docker daemon 연결
    - **none**: 네트워크 비활성화

### 기본 Docker 명령어

#### 이미지 관련 명령어

```bash
# 이미지 검색
docker search nginx

# 이미지 다운로드
docker pull nginx:latest

# 이미지 목록 확인
docker images
docker image ls

# 이미지 상세 정보
docker image inspect nginx:latest

# 이미지 삭제
docker rmi nginx:latest
docker image rm nginx:latest

# 이미지 빌드
docker build -t myapp:1.0 .
docker build -f Dockerfile.dev -t myapp:dev .

# 이미지 태그 지정
docker tag myapp:1.0 myrepo/myapp:1.0

# 이미지 업로드
docker push myrepo/myapp:1.0

# 이미지 히스토리 확인
docker history nginx:latest
```

#### 컨테이너 관련 명령어

```bash
# 컨테이너 실행
docker run nginx
docker run -d nginx                    # 백그라운드 실행
docker run -it ubuntu bash             # 대화형 모드
docker run -p 8080:80 nginx           # 포트 매핑
docker run --name webserver nginx      # 이름 지정
docker run -v /host/path:/container/path nginx  # 볼륨 마운트
docker run --rm nginx                  # 종료 시 자동 삭제

# 실행 중인 컨테이너 확인
docker ps
docker ps -a                          # 모든 컨테이너 표시

# 컨테이너 상세 정보
docker inspect <container-id>

# 컨테이너 중지/시작/재시작
docker stop <container-id>
docker start <container-id>
docker restart <container-id>

# 컨테이너 삭제
docker rm <container-id>
docker rm -f <container-id>           # 강제 삭제

# 컨테이너 로그 확인
docker logs <container-id>
docker logs -f <container-id>         # 실시간 로그
docker logs --tail 50 <container-id>  # 마지막 50줄

# 실행 중인 컨테이너 접속
docker exec -it <container-id> bash
docker exec <container-id> ls -la

# 컨테이너와 호스트 간 파일 복사
docker cp <container-id>:/path/to/file /host/path
docker cp /host/path <container-id>:/path/to/file

# 컨테이너 리소스 사용량 확인
docker stats
docker stats <container-id>

# 컨테이너에서 이미지 생성
docker commit <container-id> myimage:tag
```

### Dockerfile 작성

#### 기본 구조

```dockerfile
# 베이스 이미지 지정
FROM node:14-alpine

# 메타데이터 추가
LABEL maintainer="your-email@example.com"
LABEL version="1.0"
LABEL description="Sample Node.js application"

# 작업 디렉토리 설정
WORKDIR /app

# 환경 변수 설정
ENV NODE_ENV=production
ENV PORT=3000

# 의존성 파일 복사 및 설치
COPY package*.json ./
RUN npm ci --only=production

# 애플리케이션 소스 복사
COPY . .

# 포트 노출
EXPOSE 3000

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js

# 실행 명령
CMD ["node", "server.js"]
```

#### Dockerfile 명령어 설명

| 명령어         | 설명                    | 예시                                          |
|-------------|-----------------------|---------------------------------------------|
| FROM        | 베이스 이미지 지정            | `FROM ubuntu:20.04`                         |
| RUN         | 빌드 중 명령 실행            | `RUN apt-get update`                        |
| CMD         | 컨테이너 실행 시 기본 명령       | `CMD ["nginx", "-g", "daemon off;"]`        |
| ENTRYPOINT  | 컨테이너 실행 시 진입점         | `ENTRYPOINT ["docker-entrypoint.sh"]`       |
| COPY        | 파일/디렉토리 복사            | `COPY src/ /app/src/`                       |
| ADD         | 파일/디렉토리 복사 (압축 해제 지원) | `ADD app.tar.gz /app/`                      |
| WORKDIR     | 작업 디렉토리 설정            | `WORKDIR /app`                              |
| ENV         | 환경 변수 설정              | `ENV NODE_ENV=production`                   |
| EXPOSE      | 포트 문서화                | `EXPOSE 80 443`                             |
| VOLUME      | 볼륨 마운트 포인트 생성         | `VOLUME ["/data"]`                          |
| USER        | 사용자 설정                | `USER node`                                 |
| ARG         | 빌드 시 인자 정의            | `ARG VERSION=latest`                        |
| LABEL       | 메타데이터 추가              | `LABEL version="1.0"`                       |
| HEALTHCHECK | 헬스체크 설정               | `HEALTHCHECK CMD curl -f http://localhost/` |

#### Multi-stage Build 예제

```dockerfile
# Stage 1: Build
FROM node:14-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:14-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY --from=builder /app/dist ./dist
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

### Docker Compose

#### docker-compose.yml 예제

```yaml
version: '3.8'

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    image: myapp:latest
    container_name: myapp-web
    ports:
      - "80:3000"
    environment:
      - NODE_ENV=production
      - DB_HOST=db
    volumes:
      - ./app:/app
      - node_modules:/app/node_modules
    depends_on:
      - db
      - redis
    networks:
      - app-network
    restart: unless-stopped

  db:
    image: postgres:13
    container_name: myapp-db
    environment:
      - POSTGRES_DB=myapp
      - POSTGRES_USER=admin
      - POSTGRES_PASSWORD=secret
    volumes:
      - db-data:/var/lib/postgresql/data
    networks:
      - app-network
    restart: always

  redis:
    image: redis:6-alpine
    container_name: myapp-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - app-network
    restart: always

volumes:
  node_modules:
  db-data:
  redis-data:

networks:
  app-network:
    driver: bridge
```

#### Docker Compose 명령어

```bash
# 서비스 시작
docker-compose up
docker-compose up -d              # 백그라운드 실행
docker-compose up --build         # 이미지 재빌드

# 서비스 중지
docker-compose down
docker-compose down -v            # 볼륨도 함께 삭제

# 서비스 상태 확인
docker-compose ps
docker-compose logs
docker-compose logs -f web        # 특정 서비스 로그

# 서비스 재시작
docker-compose restart
docker-compose restart web        # 특정 서비스만

# 서비스 스케일링
docker-compose up -d --scale web=3
```

---

## Docker Best Practices

### 1. 이미지

- 공식 이미지 또는 신뢰할 수 있는 베이스 이미지 사용
- 최소한의 베이스 이미지 사용 (alpine, distroless)
- 정기적으로 이미지 업데이트
- 이미지 스캔 도구 사용 (Trivy, Clair 등)

### 2. Dockerfile 보안

```dockerfile
# 좋은 예: non-root 사용자로 실행
FROM node:14-alpine
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
USER nodejs
WORKDIR /app
COPY --chown=nodejs:nodejs . .
```

### 3. 런타임 보안

- 최소 권한 원칙 적용
- 읽기 전용 파일 시스템 사용: `docker run --read-only`
- 네트워크 분리 및 제한
- 시크릿 관리 도구 사용 (Docker Secrets, Vault 등)

### 4. 리소스 제한

```bash
docker run -d \
  --memory="512m" \
  --cpus="0.5" \
  --pids-limit=100 \
  nginx
```

---

## 참고 자료

- [Docker 공식 문서](https://docs.docker.com/)
- [Docker Hub](https://hub.docker.com/)
- [Docker 베스트 프랙티스](https://docs.docker.com/develop/dev-best-practices/)
- [Dockerfile 레퍼런스](https://docs.docker.com/engine/reference/builder/)
- [Docker Compose 문서](https://docs.docker.com/compose/)
