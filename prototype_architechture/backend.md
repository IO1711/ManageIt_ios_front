### 4.1 Server and database

| Technology | Purpose |
| --- | --- |
| `Java 21 LTS` | Stable long-term runtime for the backend |
| `Spring Boot 4.x` | Main backend framework |
| `Spring Web MVC` | REST JSON API layer |
| `Spring Security` | Admin password auth, device auth, role checks |
| `Spring Data JPA` | Database access through repositories |
| `Hibernate` | JPA implementation / ORM |
| `Flyway` | Versioned database migrations |
| `PostgreSQL 18` | Main relational database |
| `Maven` | Backend build tool |
| `springdoc-openapi` | Generates OpenAPI spec and Swagger UI for development/testing |
| `Docker Compose` | Cross-platform local deployment |
| `Caddy 2.x` | Reverse proxy and static frontend server |

## 8. Backend Architecture

### 8.1 Overall style

Use a modular monolith:

- one Spring Boot application
- one codebase
- one deployment unit
- one database
- clearly separated internal modules

This is the right fit for the scope. Microservices would add complexity without real benefit here.

### 8.2 Backend modules

Recommended modules:

- `settings`
  - onboarding
  - organization name
  - admin password change
- `auth`
  - JWT issuing/refresh
  - session validation
  - role enforcement
- `devices`
  - registered devices
  - web access requests
  - mobile pairing sessions
  - revoke/change role
- `items`
  - item CRUD
  - planning updates
  - duplicate main number checks
- `authors`
  - lookup
  - create during item flows
- `locations`
  - list active
  - add/archive
  - admin-only management
- `organizations`
  - lookup
  - create during planning/rental flows
- `history`
  - movement/rental event creation
  - item history queries

### 8.3 Layered package structure

Inside each module, use:

- `controller`
- `service`
- `repository`
- `entity`
- `dto`

Recommended backend package example:

```text
backend/src/main/java/com/manageit
  /settings
    /controller
    /service
    /repository
    /entity
    /dto
  /auth
  /devices
  /items
  /authors
  /locations
  /organizations
  /history
  /shared
    /config
    /security
    /exception
```

### 8.4 Main backend responsibilities

The backend should:

- own all business rules
- own all uniqueness checks
- own all role checks
- own all history-closing logic
- own all archive behavior
- issue tokens
- revoke tokens
- expose one shared REST contract for both clients

## 15. OpenAPI and Swagger

Use `springdoc-openapi` in the backend.

Purpose:

- generate machine-readable API contract
- provide Swagger UI for testing during development
- help both the React app and iPhone app stay aligned with backend changes

Recommended use:

- enabled in development
- optionally restricted to host/admin use in later production setup

Useful routes in development:

- `/v3/api-docs`
- `/swagger-ui.html`
