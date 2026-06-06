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
  - validate leaf-only internal location targets
- `exhibitions`
  - create/edit exhibitions
  - assign item groups
  - list planned/active/ended exhibitions
  - exhibition history queries
  - expose reminder source data for clients
- `authors`
  - lookup
  - create during item flows
- `locations`
  - list active hierarchy
  - add root or child locations
  - rename/archive
  - admin-only hierarchy management
  - validate hierarchy integrity
- `organizations`
  - lookup
  - create during planning/rental flows
- `history`
  - movement/rental event creation
  - item history queries
  - resolve movement actor device summaries
  - expose open external rental reminder source data

Location and exhibition rules:

- internal locations are stored as a parent-child tree
- root locations have no parent
- child locations can nest recursively
- location names only need to be unique among siblings under the same parent
- item create/move/return flows may reference only leaf locations
- re-parenting an existing location is not part of the prototype contract
- location APIs should expose enough metadata for clients to render hierarchy and leaf-only selectors
- each exhibition points to one internal leaf location
- the same item cannot belong to two exhibitions whose date ranges overlap
- during an active exhibition, included items must remain `INTERNAL` and their `current_location_id` must exactly equal the exhibition location
- ended exhibitions and linked items remain queryable as exhibition history
- iPhone and web clients schedule local exhibition-end reminders from backend exhibition dates; the backend does not send reminder notifications in the prototype
- iPhone and web clients also schedule local rental-return reminders 3 days before `expected_return_date` on open external rental rows; the backend does not send reminder notifications in the prototype
- history APIs should expose the registered device actor for each movement row, including the device's host-set `friendly_name`
- iPhone offline movement replay should be treated as a normal movement write with an extra expected-source-placement precondition from the queued mobile payload
- if a replayed iPhone offline movement no longer matches the item's current database placement, the backend should reject it as stale instead of overwriting newer state

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
  /exhibitions
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
- own all location-tree validation and leaf-location enforcement
- own all exhibition overlap and active-location validation
- own stale-source validation for replayed iPhone offline movements
- expose the latest exhibition date range data clients need for local reminder rescheduling
- expose the latest open external rental return-date and organization data clients need for 3-day local reminder scheduling and rescheduling
- expose movement actor device summaries for history entries
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
