## 3. High-Level Architecture

### Prototype demo setup

For the prototype demo:

- your computer acts as the server
- PostgreSQL runs on that computer
- Spring Boot runs on that computer
- Caddy runs on that computer
- the React app is built and served by Caddy
- your iPhone connects over the same Wi-Fi using your computer's LAN IP
- the host-only admin UI is opened only on `localhost` on the computer

Prototype URLs:

- regular client app: `http://<computer-lan-ip>/`
- regular client API: `http://<computer-lan-ip>/api/...`
- host-only admin UI: `http://localhost/`
- host-only admin API: `http://localhost/api/...`

Important note:

- For the prototype demo, use plain `HTTP` for simplicity.
- Full PWA installability should be treated as a long-term `HTTPS` feature.
- When the backend runs behind Docker or a reverse proxy, set `MANAGEIT_MOBILE_PAIRING_PUBLIC_BASE_URL=http://<computer-lan-ip>` so generated iPhone pairing QR codes embed the LAN URL instead of a container-only or loopback address.

### Longer-term production direction

The long-term production target is:

- `https://app.<domain>` for regular desktop web/PWA clients and iPhone API traffic
- `https://admin.<domain>` for the host-only admin UI
- internal DNS resolves those names to the museum server's local IP
- `admin.<domain>` is restricted to the host machine by proxy rules and/or firewall rules
- `Caddy` handles HTTPS and routes traffic to the correct backend/frontend parts

Important production note:

- Using a real domain plus internal DNS does not mean item data travels through the public internet.
- If the domain resolves to the local server IP inside the museum network, the app traffic stays local.

## 13. Caddy: What It Does and Why It Is Here

`Caddy` is separate software.

It is not part of Spring Boot.

Its job in this architecture is:

- receive browser/app requests
- serve the built React app as static files
- forward `/api/...` requests to Spring Boot
- expose one clean entry point
- handle long-term HTTPS later

### 13.1 Request flow in the prototype

Regular client:

- request comes to `http://<computer-lan-ip>/`
- Caddy serves React static files from `/srv/app`
- when the React app calls `/api/...`, Caddy forwards that request to Spring Boot

Host admin:

- request comes to `http://localhost/`
- Caddy serves the same React build
- the React app detects host mode and shows host admin routes
- `/api/...` calls are forwarded to Spring Boot

### 13.2 Why Caddy is useful here

- cleaner than exposing raw backend ports to users
- keeps frontend and backend under one entry point
- easy path to long-term HTTPS
- simpler than introducing both `Nginx` and another frontend runtime server

## 14. Docker Compose and Caddy Examples

### 14.1 Compose overview

Even though the frontend is a separate codebase, the prototype runtime can stay simple:

- `postgres` container
- `backend` container
- `caddy` container

The built React frontend is copied into the `caddy` image and served directly by Caddy.

### 14.2 Example `docker-compose.yml`

```yaml
services:
  postgres:
    image: postgres:18
    container_name: manageit-postgres
    environment:
      POSTGRES_DB: manageit
      POSTGRES_USER: manageit
      POSTGRES_PASSWORD: change-me
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U manageit -d manageit"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend:
    build:
      context: ./backend
    container_name: manageit-backend
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/manageit
      SPRING_DATASOURCE_USERNAME: manageit
      SPRING_DATASOURCE_PASSWORD: change-me
      SPRING_PROFILES_ACTIVE: docker
      MANAGEIT_MOBILE_PAIRING_PUBLIC_BASE_URL: http://192.168.1.50
    depends_on:
      postgres:
        condition: service_healthy

  caddy:
    build:
      context: .
      dockerfile: infra/caddy/Dockerfile
    container_name: manageit-caddy
    ports:
      - "80:80"
    depends_on:
      - backend
    volumes:
      - caddy_data:/data
      - caddy_config:/config

volumes:
  postgres_data:
  caddy_data:
  caddy_config:
```

### 14.3 Example `infra/caddy/Dockerfile`

```dockerfile
FROM node:22-alpine AS frontend-build

WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM caddy:2-alpine
COPY infra/Caddyfile /etc/caddy/Caddyfile
COPY --from=frontend-build /app/frontend/dist /srv/app
COPY --from=frontend-build /app/frontend/dist /srv/admin
```

### 14.4 Example prototype `infra/Caddyfile`

```caddyfile
{
  auto_https off
}

http://localhost {
  root * /srv/admin
  encode zstd gzip

  handle /api/* {
    reverse_proxy backend:8080
  }

  try_files {path} /index.html
  file_server
}

http://192.168.1.50 {
  root * /srv/app
  encode zstd gzip

  handle /api/* {
    reverse_proxy backend:8080
  }

  try_files {path} /index.html
  file_server
}
```

Notes:

- Replace `192.168.1.50` with the actual LAN IP of the demo computer.
- For the prototype, this keeps `localhost` for the host-only admin UI and LAN IP for the regular client app.
- In the long-term production setup, replace these with `app.<domain>` and `admin.<domain>`.

### 14.5 Long-term production Caddy direction

Later, the same idea becomes:

```caddyfile
app.example.org {
  root * /srv/app
  encode zstd gzip

  handle /api/* {
    reverse_proxy backend:8080
  }

  try_files {path} /index.html
  file_server
}

admin.example.org {
  @notLocal not remote_ip 127.0.0.1/32 ::1
  respond @notLocal 403

  root * /srv/admin
  encode zstd gzip

  handle /api/* {
    reverse_proxy backend:8080
  }

  try_files {path} /index.html
  file_server
}
```

That production version assumes:

- real domain
- internal DNS
- HTTPS enabled
- host restriction for `admin.<domain>`
