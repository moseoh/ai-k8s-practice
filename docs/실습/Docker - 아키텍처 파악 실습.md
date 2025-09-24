## 실습 1: 첫 번째 Docker 컨테이너 실행

```bash
# 1. Hello World 컨테이너 실행
docker run hello-world

# 2. Ubuntu 컨테이너에서 명령 실행
docker run ubuntu echo "Hello from Ubuntu"

# 3. 대화형 Ubuntu 컨테이너 실행
docker run -it ubuntu bash
# 컨테이너 내부에서
apt update
apt install -y curl
curl --version
exit

# 4. 백그라운드로 Nginx 실행
docker run -d -p 8080:80 --name my-nginx nginx

# 5. 웹 브라우저에서 http://localhost:8080 접속

# 6. 컨테이너 정리
docker stop my-nginx
docker rm my-nginx
```

## 실습 2: Dockerfile로 이미지 빌드

**app.js 파일 생성:**

```javascript
const http = require('http');

const server = http.createServer((req, res) => {
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end('<h1>Hello from Docker Container!</h1>');
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
```

**package.json 파일 생성:**

```json
{
  "name": "docker-node-app",
  "version": "1.0.0",
  "description": "Simple Node.js app for Docker",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {}
}
```

**Dockerfile 생성:**

```dockerfile
FROM node:14-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
```

**이미지 빌드 및 실행:**

```bash
# 이미지 빌드
docker build -t my-node-app:1.0 .

# 컨테이너 실행
docker run -d -p 3000:3000 --name node-app my-node-app:1.0

# 로그 확인
docker logs node-app

# 웹 브라우저에서 http://localhost:3000 접속

# 정리
docker stop node-app
docker rm node-app
```

## 실습 3: Docker Compose로 멀티 컨테이너 애플리케이션 실행

**docker-compose.yml 생성:**

```yaml
version: '3.8'

services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
    depends_on:
      - api

  api:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development

  db:
    image: mysql:5.7
    environment:
      - MYSQL_ROOT_PASSWORD=secret
      - MYSQL_DATABASE=myapp
    volumes:
      - db-data:/var/lib/mysql

volumes:
  db-data:
```

**실행 및 관리:**

```bash
# 서비스 시작
docker-compose up -d

# 상태 확인
docker-compose ps

# 로그 확인
docker-compose logs -f

# 서비스 중지
docker-compose down
```

