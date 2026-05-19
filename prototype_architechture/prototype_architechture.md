# Prototype Architecture Build Guide

This document is the practical build guide for the first working prototype of the museum inventory system.

It covers:

- database design
- Java/Spring server architecture
- iPhone app architecture
- desktop web/PWA architecture
- host-only admin UI
- Docker/Caddy deployment
- prototype demo setup
- short note about the longer-term production direction

## 1. Prototype Scope

This prototype includes:

- one server installation for one organization at a time
- one PostgreSQL database
- one Java/Spring Boot backend
- one modular React web app used in two modes:
  - regular client app
  - host-only admin UI
- one native SwiftUI iPhone app
- device-based access for iPhone and regular web clients
- password-based access for the host-only admin UI

This prototype does not include:

- offline sync
- Android native app
- multiple organizations in one installation
- per-user accounts
- internet/public-cloud hosting as a requirement

## 2. Core Product Rules

- Each installation belongs to exactly one organization.
- The organization name is set during onboarding.
- Locations are a flat list such as `Room 1`, `Storage 1`, `Hall A`.
- An item is always in exactly one current place:
  - inside the museum at one internal location
  - or outside at one external organization
- An item can never be both in an internal location and at an external organization at the same time.
- Every item must have:
  - a unique main inventory number
  - a title
  - at least one author
  - an initial internal location when created
- Secondary inventory numbers:
  - can be multiple
  - are not unique
- Full movement/rental history is kept permanently.
- History is append-driven:
  - users create a new move/rental event
  - the previous active history row is closed automatically by setting its `move_out_date`
- Business dates are `DATE` values, not timestamps.
- Archived records stay in the database and are hidden by default.
- Archived items keep their main inventory numbers permanently reserved.

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

## 4. Chosen Technology Stack

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

### 4.2 Desktop web/PWA

| Technology | Purpose |
| --- | --- |
| `React 19` | UI framework |
| `JavaScript` | Frontend language choice for this prototype |
| `Vite 8` | Fast frontend build/dev tooling |
| `React Router` | Route handling for client routes and host admin routes |
| `TanStack Query` | Server state, caching, refetching, mutation handling |
| `React Hook Form` | Forms for item editing, planning, onboarding, approvals |
| `Zod` | Frontend validation schemas |
| `TanStack Table` | Rich inventory table with sorting/filtering/pagination UI |
| `date-fns` | Lightweight date formatting/parsing helpers |
| `vite-plugin-pwa` | Manifest, icons, install metadata for long-term PWA support |

No heavy UI/component library is used in the prototype. The UI stays custom and lightweight.

### 4.3 iPhone app

| Technology / Framework | Purpose |
| --- | --- |
| `SwiftUI` | Native iPhone UI |
| `Observation` | State management in the SwiftUI app |
| `URLSession` | HTTP networking |
| `Keychain Services` | Secure storage for refresh token, device credentials, and stable installation identity |
| `AVFoundation` | QR code scanning |
| `Foundation` | Models, dates, formatting, decoding |

### 4.4 Why this stack

- `Spring Boot + PostgreSQL` gives a strong, practical server foundation.
- `React + Vite` is fast to build and easy to demo.
- `SwiftUI` is the right native choice for the iPhone app and fits the TestFlight/App Store path.
- `Caddy` keeps the deployment simpler than introducing `Nginx` plus another frontend runtime server.
- `Docker Compose` keeps the stack usable on macOS, Windows, and Linux.

## 5. Authentication and Access Model

### 5.1 Core approach

There are no normal per-user accounts for regular client devices.

Regular client access is device-based:

- a device is registered once
- the admin assigns the role at registration time
- that device is then trusted until revoked

Roles:

- `ADMIN`
- `EDITOR`

### 5.2 Host admin UI auth

The host-only admin UI is different from client devices:

- it is inherently trusted because it exists on the host machine only
- it requires an installation-wide admin password
- the password is created during onboarding
- the password is stored as a secure hash in the database
- the host admin UI uses a secure session cookie

### 5.3 Regular client web auth

Regular web/PWA clients use:

- access token:
  - short-lived
  - kept only in memory
- refresh token:
  - stored in an `HttpOnly Secure` cookie in the long-term HTTPS setup
  - database-backed for revocation

### 5.4 iPhone app auth

The iPhone app uses:

- access token:
  - short-lived
  - kept only in memory
- refresh token:
  - stored in the iOS Keychain
- installation identity:
  - a stable UUID stored in the iOS Keychain
  - sent during pairing so the backend can recognize the same app install later
- device credentials:
  - stored in the iOS Keychain

### 5.5 Session model

- refresh tokens are database-backed, not stateless
- one active refresh session per registered device
- repeated pairing from the same iPhone app install reuses the same registered device row through the stable Keychain `installationId`
- if a device re-registers or a new session replaces an old one, the previous one is revoked
- revoking a device also revokes its active session

## 6. Main Flows

### 6.1 First installation onboarding

1. Open host-only admin UI on `localhost`.
2. Set organization name.
3. Set installation-wide admin password.
4. Add the initial list of locations.
5. Mark onboarding complete.

The system is not considered ready until the initial location list exists.

### 6.2 iPhone registration flow

1. Host admin opens the host-only admin UI.
2. Host admin chooses role:
   - `ADMIN`
   - `EDITOR`
3. Host admin generates a QR code.
4. The QR contains a short-lived pairing token plus the LAN-reachable backend base URL for the iPhone.
5. iPhone app scans the QR.
6. iPhone app loads or creates a stable `installationId` in Keychain and sends it with the token plus device metadata to the backend.
7. Host admin UI shows a final step:
   - use generated generic device name
   - or enter a custom friendly name
8. The backend saves the registered device, or reuses the existing `IOS_APP` device row for that same `installationId`.
9. The iPhone app receives credentials/tokens and becomes active.

There is no second approval decision for the phone. The QR generation itself is the approval step.

### 6.3 Regular desktop web/PWA approval flow

1. Browser opens regular client app.
2. If browser is not approved, show a small startup screen.
3. Browser requests access.
4. Backend creates a pending access request with:
   - short approval code
   - browser/platform metadata
5. Host admin enters/approves that code in the host-only admin UI.
6. Host admin chooses:
   - `Approve as Admin`
   - `Approve as Editor`
7. Host admin optionally sets a friendly device name.
8. Browser exchanges the approved request for device session tokens.
9. Future visits from that browser profile go straight into the app unless revoked.

Desktop access requests do not auto-expire in the prototype. They stay pending until approved or rejected.

### 6.4 Item creation flow

1. User enters item metadata.
2. User selects or creates authors.
3. User adds optional secondary inventory numbers.
4. User selects the initial internal location.
5. Backend creates:
   - the item row
   - author links
   - secondary numbers
   - the first open `item_history` row
6. `items.current_presence_type` becomes `INTERNAL`.
7. `items.current_location_id` is set.

### 6.5 Item move/rental flow

When moving an item:

1. User creates a new event.
2. Backend validates there is exactly one currently open history row.
3. Backend updates the previous row's `move_out_date` to the same date as the new event's `move_in_date`.
4. Backend inserts the new history row.
5. Backend updates the `items` current-state fields.

For internal movement:

- new history row points to a `location_id`
- `expected_return_date` stays `null`

For external rental:

- new history row points to an `organization_id`
- `expected_return_date` can be filled
- `items.current_presence_type` becomes `EXTERNAL`
- `items.current_organization_id` is set
- `items.current_location_id` becomes `null`
- `items.promised_organization_id` is cleared
- `items.expected_leave_date` is cleared

### 6.6 Item return flow

When an item returns from an external organization:

1. User creates a normal new internal movement event.
2. User selects the location where the item is placed again.
3. Backend closes the external history row automatically.
4. Backend creates a new internal history row.
5. Backend updates `items.current_location_id`.

## 7. Database Design

## 7.1 ID strategy

Use a mixed ID strategy:

- `BIGSERIAL` or `BIGINT` auto-increment IDs for core business tables
- `UUID` for device/security-facing tables

Reason:

- business tables stay simple and readable
- external device/security identifiers are opaque and safer

### 7.2 Table list

The prototype database should include these main tables:

- `app_settings`
- `registered_devices`
- `device_sessions`
- `mobile_pairing_sessions`
- `web_access_requests`
- `authors`
- `locations`
- `organizations`
- `items`
- `item_secondary_numbers`
- `item_authors`
- `item_history`

### 7.3 Common audit columns

Use these audit fields on mutable business tables when relevant:

- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `created_by_device_id UUID NULL`
- `updated_by_device_id UUID NULL`
- `is_archived BOOLEAN NOT NULL DEFAULT FALSE`
- `archived_at TIMESTAMPTZ NULL`
- `archived_by_device_id UUID NULL`

`created_by_device_id` and `updated_by_device_id` reference `registered_devices(id)`.

Host-only admin UI operations are not device-based. Those actions are controlled by the host admin password/session.

### 7.4 Table definitions

#### `app_settings`

Stores installation-wide settings for the one organization hosted by this installation.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Single-row table in practice |
| `organization_name` | `VARCHAR(255) NOT NULL` | Museum/organization name |
| `admin_password_hash` | `TEXT NOT NULL` | Secure password hash |
| `onboarding_completed` | `BOOLEAN NOT NULL DEFAULT FALSE` | Whether installation is ready |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

#### `registered_devices`

Stores approved iPhone devices and approved web browser profiles.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `UUID PRIMARY KEY` | Public-safe device identifier |
| `device_type` | `VARCHAR(20) NOT NULL` | `IOS_APP`, `WEB_BROWSER` |
| `role` | `VARCHAR(10) NOT NULL` | `ADMIN`, `EDITOR` |
| `status` | `VARCHAR(20) NOT NULL` | `ACTIVE`, `REVOKED` |
| `friendly_name` | `VARCHAR(255) NOT NULL` | Admin-entered or generated |
| `suggested_name` | `VARCHAR(255) NULL` | Client-reported suggested name |
| `platform_name` | `VARCHAR(100) NULL` | e.g. iOS, macOS, Windows |
| `platform_version` | `VARCHAR(100) NULL` | OS version |
| `model_name` | `VARCHAR(100) NULL` | e.g. iPhone model |
| `browser_name` | `VARCHAR(100) NULL` | For web clients |
| `browser_version` | `VARCHAR(100) NULL` | For web clients |
| `last_seen_at` | `TIMESTAMPTZ NULL` | Last successful activity |
| `revoked_at` | `TIMESTAMPTZ NULL` | Revocation moment |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

Notes:

- Each browser profile becomes its own registered device.
- Chrome and Safari on the same machine count as different devices.

#### `device_sessions`

Stores one active refresh-session per registered device.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `UUID PRIMARY KEY` | Session id |
| `device_id` | `UUID NOT NULL REFERENCES registered_devices(id)` | Owning device |
| `refresh_token_hash` | `TEXT NOT NULL` | Store a hash, not raw token |
| `refresh_token_expires_at` | `TIMESTAMPTZ NOT NULL` | Expiry |
| `revoked_at` | `TIMESTAMPTZ NULL` | Set when session is revoked |
| `last_used_at` | `TIMESTAMPTZ NULL` | Last refresh/use |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

Rule:

- at most one active session per device

#### `mobile_pairing_sessions`

Tracks QR-based iPhone registration.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `UUID PRIMARY KEY` | Pairing session id |
| `pairing_token` | `UUID NOT NULL UNIQUE` | Short-lived token embedded in QR |
| `role_to_assign` | `VARCHAR(10) NOT NULL` | `ADMIN` or `EDITOR` |
| `status` | `VARCHAR(30) NOT NULL` | `GENERATED`, `SCANNED`, `COMPLETED`, `CANCELLED` |
| `suggested_name` | `VARCHAR(255) NULL` | Device-provided suggested name |
| `platform_name` | `VARCHAR(100) NULL` | e.g. iOS |
| `platform_version` | `VARCHAR(100) NULL` | iOS version |
| `model_name` | `VARCHAR(100) NULL` | iPhone model |
| `registered_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Filled on completion |
| `expires_at` | `TIMESTAMPTZ NOT NULL` | QR token expiry |
| `scanned_at` | `TIMESTAMPTZ NULL` | Scan timestamp |
| `completed_at` | `TIMESTAMPTZ NULL` | Final activation time |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

#### `web_access_requests`

Tracks pending browser approval requests.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `UUID PRIMARY KEY` | Access request id |
| `approval_code` | `VARCHAR(32) NOT NULL UNIQUE` | Human-entered short code |
| `status` | `VARCHAR(20) NOT NULL` | `PENDING`, `APPROVED`, `REJECTED` |
| `friendly_name` | `VARCHAR(255) NULL` | Optional admin-entered name |
| `suggested_name` | `VARCHAR(255) NULL` | Browser-provided label |
| `platform_name` | `VARCHAR(100) NULL` | OS |
| `platform_version` | `VARCHAR(100) NULL` | OS version |
| `browser_name` | `VARCHAR(100) NULL` | Browser |
| `browser_version` | `VARCHAR(100) NULL` | Browser version |
| `role_to_assign` | `VARCHAR(10) NULL` | Set on approval |
| `registered_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Filled on approval |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

#### `authors`

Stores unique authors. Authors are created during item create/edit flow.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `name` | `VARCHAR(255) NOT NULL` | Unique, case-insensitive |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `is_archived` | `BOOLEAN NOT NULL DEFAULT FALSE` | Soft delete |
| `archived_at` | `TIMESTAMPTZ NULL` | Archive time |
| `archived_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |

#### `locations`

Stores flat internal museum locations.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `name` | `VARCHAR(255) NOT NULL` | Unique, case-insensitive |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `is_archived` | `BOOLEAN NOT NULL DEFAULT FALSE` | Soft delete |
| `archived_at` | `TIMESTAMPTZ NULL` | Archive time |
| `archived_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |

Locations with history should never be hard-deleted.

#### `organizations`

Stores external organizations used for rentals and promised destinations.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `name` | `VARCHAR(255) NOT NULL` | Unique, case-insensitive |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `is_archived` | `BOOLEAN NOT NULL DEFAULT FALSE` | Soft delete |
| `archived_at` | `TIMESTAMPTZ NULL` | Archive time |
| `archived_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |

Organizations are mainly created from rental/planning flows and then reused from suggestions/history.

#### `items`

Stores the current state and planning state for each item.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `main_inventory_number` | `VARCHAR(100) NOT NULL` | Unique, case-insensitive |
| `title` | `VARCHAR(255) NOT NULL` | Required |
| `current_presence_type` | `VARCHAR(20) NOT NULL` | `INTERNAL`, `EXTERNAL` |
| `current_location_id` | `BIGINT NULL REFERENCES locations(id)` | Used when internal |
| `current_organization_id` | `BIGINT NULL REFERENCES organizations(id)` | Used when external |
| `promised_organization_id` | `BIGINT NULL REFERENCES organizations(id)` | Planning field |
| `expected_leave_date` | `DATE NULL` | Planning field |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `is_archived` | `BOOLEAN NOT NULL DEFAULT FALSE` | Soft delete |
| `archived_at` | `TIMESTAMPTZ NULL` | Archive time |
| `archived_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |

Rules:

- when `current_presence_type = INTERNAL`, `current_location_id` must be set and `current_organization_id` must be null
- when `current_presence_type = EXTERNAL`, `current_organization_id` must be set and `current_location_id` must be null

#### `item_secondary_numbers`

Stores zero or more secondary inventory numbers per item.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `item_id` | `BIGINT NOT NULL REFERENCES items(id)` | Parent item |
| `secondary_inventory_number` | `VARCHAR(100) NOT NULL` | Not unique |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

#### `item_authors`

Join table between items and authors.

| Column | Type | Notes |
| --- | --- | --- |
| `item_id` | `BIGINT NOT NULL REFERENCES items(id)` | Parent item |
| `author_id` | `BIGINT NOT NULL REFERENCES authors(id)` | Linked author |

Primary key:

- `(item_id, author_id)`

Rule:

- every item must have at least one linked author
- enforce in service-layer validation during create/update transaction

#### `item_history`

Single history table for both internal locations and external organizations.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `item_id` | `BIGINT NOT NULL REFERENCES items(id)` | Parent item |
| `presence_type` | `VARCHAR(20) NOT NULL` | `INTERNAL`, `EXTERNAL` |
| `location_id` | `BIGINT NULL REFERENCES locations(id)` | Used for internal rows |
| `organization_id` | `BIGINT NULL REFERENCES organizations(id)` | Used for external rows |
| `move_in_date` | `DATE NOT NULL` | Start of that placement period |
| `expected_return_date` | `DATE NULL` | Only for external rows |
| `move_out_date` | `DATE NULL` | Null while this row is the current open row |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Who created the row |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Who closed/edited it |

Rules:

- exactly one currently open row per item
- open row means `move_out_date IS NULL`
- internal rows:
  - `location_id` set
  - `organization_id` null
  - `expected_return_date` null
- external rows:
  - `organization_id` set
  - `location_id` null
  - `expected_return_date` optional

### 7.5 Recommended constraints

- Case-insensitive uniqueness:
  - `items.main_inventory_number`
  - `authors.name`
  - `locations.name`
  - `organizations.name`
- Check constraints:
  - valid `role`
  - valid `device_type`
  - valid `presence_type`
  - valid current-state combinations on `items`
  - valid target combinations on `item_history`
- One active history row per item:
  - partial unique index on `item_history(item_id)` where `move_out_date IS NULL`
- One active session per device:
  - partial unique index on `device_sessions(device_id)` where `revoked_at IS NULL`

### 7.6 Recommended indexes

Use these indexes from the beginning:

- unique index on `LOWER(items.main_inventory_number)`
- index on `items.current_location_id`
- index on `items.current_organization_id`
- index on `items.promised_organization_id`
- unique index on `LOWER(authors.name)`
- unique index on `LOWER(locations.name)`
- unique index on `LOWER(organizations.name)`
- index on `item_secondary_numbers(item_id)`
- index on `LOWER(item_secondary_numbers.secondary_inventory_number)`
- index on `item_authors(author_id)`
- index on `item_history(item_id, move_in_date DESC)`
- partial unique index on `item_history(item_id)` where `move_out_date IS NULL`
- unique index on `web_access_requests.approval_code`
- unique index on `mobile_pairing_sessions.pairing_token`

Search note:

- For the prototype, simple indexed `ILIKE` queries are enough.
- If the dataset grows a lot, add PostgreSQL `pg_trgm` indexes later for faster partial text search on title/numbers/names.

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

## 9. Frontend Architecture: React Web/PWA

### 9.1 One codebase, two host modes

Use one modular React application served under two hosts:

- prototype demo:
  - regular client app on `http://<computer-lan-ip>/`
  - host-only admin UI on `http://localhost/`
- long-term:
  - `app.<domain>`
  - `admin.<domain>`

The same React codebase is used for both.

Behavior changes by host:

- regular client host shows normal inventory routes
- host admin host shows onboarding, approvals, device management, installation settings

### 9.2 Frontend module breakdown

Recommended feature modules:

- `app-shell`
  - layout
  - navigation
  - auth bootstrap
- `inventory`
  - list/search/table
  - item detail
  - item edit
- `history`
  - per-item chronological history view
- `planning`
  - promised organization
  - expected leave date
- `locations-admin`
  - add location
  - rename location
  - archive location
- `device-startup`
  - small startup screen for unapproved browsers
  - request access
  - poll pending state
- `host-admin`
  - onboarding
  - mobile QR generation/finalization
  - web approval queue
  - registered devices
  - password change
  - installation settings

### 9.3 Frontend folder structure

```text
frontend/src
  /routes
  /pages
  /features
    /inventory
    /history
    /planning
    /locations-admin
    /device-startup
    /host-admin
  /components
  /api
  /lib
  /hooks
  /validation
  /assets
```

### 9.4 Frontend responsibilities

- route users to the correct host-mode UI
- keep the access token in memory only
- use TanStack Query for server state
- use server-side pagination/filtering/sorting
- show suggestions for authors and organizations
- do not auto-assume an exact typed author/org is an existing one
- show duplicate main number conflict details if backend returns them

### 9.5 PWA notes

Include:

- manifest
- app icons
- standalone window metadata
- install metadata

Do not rely on in the prototype demo:

- offline data
- offline writes
- background sync

## 10. iPhone App Architecture: SwiftUI

### 10.1 Main screen/module breakdown

Recommended modules:

- `Pairing`
  - QR scanner
  - pairing status
  - waiting/activation screen
- `Session`
  - token refresh
  - revoked-session handling
- `Inventory`
  - item list
  - search
  - item detail
- `ItemEditor`
  - create/edit item
  - planning updates
  - movement/rental events
- `History`
  - per-item history screen
- `Networking`
  - API client
  - request builders
  - response decoding
- `SecureStorage`
  - Keychain helpers
- `SharedUI`
  - reusable views
- `Models`
  - DTOs/view models

### 10.2 Recommended folder structure

```text
iOSApp
  /Features
    /Pairing
    /Session
    /Inventory
    /ItemEditor
    /History
  /Networking
  /Models
  /Storage
  /SharedUI
  /Utilities
```

### 10.3 iPhone app responsibilities

- scan QR using `AVFoundation`
- send pairing token and device metadata
- wait while host admin finalizes naming
- store refresh token in Keychain
- keep access token in memory
- refresh session when needed
- go directly to inventory list on future launches unless revoked

## 11. API Design

The API is REST JSON.

There is one shared backend contract:

- iPhone app talks to the backend
- React web/PWA talks to the same backend
- clients do not talk to each other directly

### 11.1 Host admin UI endpoints

These are only for `localhost` in the prototype and `admin.<domain>` in the long-term setup.

#### Admin session and onboarding

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/admin/session/login` | Log into host admin UI |
| `POST` | `/api/admin/session/logout` | Log out |
| `GET` | `/api/admin/session/me` | Check admin session |
| `POST` | `/api/admin/onboarding` | Create initial installation settings |
| `GET` | `/api/admin/settings` | Read organization settings |
| `PUT` | `/api/admin/settings` | Update organization name/settings |
| `PUT` | `/api/admin/password` | Change host admin password |

#### Mobile pairing

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/admin/mobile-pairings` | Generate a QR pairing session |
| `GET` | `/api/admin/mobile-pairings` | List recent pairing sessions |
| `POST` | `/api/admin/mobile-pairings/{id}/finalize` | Finalize name and activate device |
| `POST` | `/api/admin/mobile-pairings/{id}/cancel` | Cancel a pairing session |

#### Web access approval

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/admin/web-access-requests` | List pending/processed access requests |
| `POST` | `/api/admin/web-access-requests/{id}/approve` | Approve request and assign role |
| `POST` | `/api/admin/web-access-requests/{id}/reject` | Reject request |

#### Device management

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/admin/devices` | List registered devices |
| `PUT` | `/api/admin/devices/{id}/role` | Change device role |
| `POST` | `/api/admin/devices/{id}/revoke` | Revoke device and its session |

### 11.2 Public onboarding/client bootstrap endpoints

#### Mobile pairing endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/mobile/pairings/scan` | iPhone submits pairing token and device info |
| `GET` | `/api/mobile/pairings/{id}` | Poll pairing status |
| `POST` | `/api/mobile/pairings/{id}/complete` | Exchange completed pairing for device session |

#### Web access request endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/web/access-requests` | Browser asks for approval |
| `GET` | `/api/web/access-requests/{id}` | Poll pending/approved/rejected state |
| `POST` | `/api/web/access-requests/{id}/complete` | Exchange approved request for device session |

### 11.3 Auth/session endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/auth/refresh` | Get a new access token |
| `POST` | `/api/auth/logout` | Revoke current device session |
| `GET` | `/api/auth/me` | Get current device session info |

Notes:

- Web uses refresh token cookie.
- iPhone sends the refresh token from Keychain through the mobile API client.

### 11.4 Protected item endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/items` | Paged list with search/filter/sort |
| `POST` | `/api/items` | Create item and first history row |
| `GET` | `/api/items/{id}` | Item detail |
| `PUT` | `/api/items/{id}` | Edit core item metadata |
| `PATCH` | `/api/items/{id}/planning` | Update promised org / expected leave date |
| `POST` | `/api/items/{id}/movements` | Add a new move/rental/return event |
| `GET` | `/api/items/{id}/history` | Chronological actual history |
| `POST` | `/api/items/{id}/archive` | Archive item, admin only |
| `GET` | `/api/items/conflicts/main-number` | Optional UX pre-check helper |

### 11.5 Lookup endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/locations` | List active locations for selection |
| `POST` | `/api/locations` | Create location, admin only |
| `PUT` | `/api/locations/{id}` | Rename location, admin only |
| `POST` | `/api/locations/{id}/archive` | Archive location, admin only |
| `GET` | `/api/authors` | Search author suggestions |
| `POST` | `/api/authors` | Create author during item flow |
| `GET` | `/api/organizations` | Search organization suggestions |
| `POST` | `/api/organizations` | Create organization during planning/rental flow |

### 11.6 Example payloads

#### Host admin login

```http
POST /api/admin/session/login
Content-Type: application/json
```

```json
{
  "password": "super-secret-password"
}
```

#### Generate mobile QR pairing

```http
POST /api/admin/mobile-pairings
Content-Type: application/json
```

```json
{
  "role": "EDITOR"
}
```

Example response:

```json
{
  "pairingId": "c4f15aa9-d92d-47fc-82db-a9c62d104dfd",
  "pairingToken": "cb83ce39-c174-4e19-871d-2168bb8aad6d",
  "expiresAt": "2026-05-06T16:00:00Z",
  "qrUrl": "manageit://pair?server=http%3A%2F%2F192.168.1.50&token=cb83ce39-c174-4e19-871d-2168bb8aad6d"
}
```

#### iPhone scans QR

```http
POST /api/mobile/pairings/scan
Content-Type: application/json
```

```json
{
  "pairingToken": "cb83ce39-c174-4e19-871d-2168bb8aad6d",
  "suggestedName": "iPhone 15 Pro",
  "platformName": "iOS",
  "platformVersion": "18.0",
  "modelName": "iPhone 15 Pro"
}
```

#### Finalize iPhone device

```http
POST /api/admin/mobile-pairings/c4f15aa9-d92d-47fc-82db-a9c62d104dfd/finalize
Content-Type: application/json
```

```json
{
  "friendlyName": "Bilol's iPhone"
}
```

#### Create web access request

```http
POST /api/web/access-requests
Content-Type: application/json
```

```json
{
  "suggestedName": "Front Desk Chrome",
  "platformName": "macOS",
  "platformVersion": "15.0",
  "browserName": "Chrome",
  "browserVersion": "136"
}
```

Example response:

```json
{
  "requestId": "3f56cde0-9b72-44fd-b74c-b0dfc039de3a",
  "approvalCode": "A7KQ2M"
}
```

#### Approve web access request

```http
POST /api/admin/web-access-requests/3f56cde0-9b72-44fd-b74c-b0dfc039de3a/approve
Content-Type: application/json
```

```json
{
  "role": "EDITOR",
  "friendlyName": "Front Desk Chrome"
}
```

#### Create item

```http
POST /api/items
Content-Type: application/json
Authorization: Bearer <access-token>
```

```json
{
  "mainInventoryNumber": "INV-2026-001",
  "title": "Mask of the Harvest Festival",
  "secondaryInventoryNumbers": [
    "A-15",
    "TEMP-77"
  ],
  "authors": [
    { "id": 12 },
    { "name": "Unknown Workshop" }
  ],
  "initialLocationId": 3,
  "moveInDate": "2026-05-06"
}
```

#### Update planning fields

```http
PATCH /api/items/45/planning
Content-Type: application/json
Authorization: Bearer <access-token>
```

```json
{
  "promisedOrganization": {
    "id": 7
  },
  "expectedLeaveDate": "2026-05-20"
}
```

Or create a new organization explicitly:

```json
{
  "promisedOrganization": {
    "name": "Museum of Rome"
  },
  "expectedLeaveDate": "2026-05-20"
}
```

#### Move item to another internal location

```http
POST /api/items/45/movements
Content-Type: application/json
Authorization: Bearer <access-token>
```

```json
{
  "presenceType": "INTERNAL",
  "locationId": 8,
  "moveInDate": "2026-05-12"
}
```

#### Rent item to external organization

```http
POST /api/items/45/movements
Content-Type: application/json
Authorization: Bearer <access-token>
```

```json
{
  "presenceType": "EXTERNAL",
  "organization": {
    "id": 7
  },
  "moveInDate": "2026-05-20",
  "expectedReturnDate": "2026-06-20"
}
```

### 11.7 Standard error shape

Use one consistent error structure:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "details": {}
  }
}
```

#### Duplicate main inventory number example

```json
{
  "error": {
    "code": "DUPLICATE_MAIN_INVENTORY_NUMBER",
    "message": "Main inventory number already exists",
    "details": {
      "field": "mainInventoryNumber",
      "value": "INV-2026-001",
      "conflictingItem": {
        "id": 45,
        "title": "Mask of the Harvest Festival",
        "currentPresenceType": "INTERNAL",
        "currentLocationName": "Storage 1"
      }
    }
  }
}
```

This lets the frontend offer:

- open existing item
- or change the number and continue

#### Unauthorized or revoked device example

```json
{
  "error": {
    "code": "DEVICE_REVOKED",
    "message": "This device has been revoked",
    "details": {}
  }
}
```

#### Validation error example

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Author list must contain at least one author",
    "details": {
      "field": "authors"
    }
  }
}
```

## 12. Search, List, and Visibility Rules

### 12.1 Item list/search

Search should support:

- main inventory number
- secondary inventory numbers
- title
- author name
- current location name

Search behavior:

- partial text matching is supported
- case-insensitive matching
- paginated in the backend
- sorted in the backend
- filtered in the backend

When no filter is set:

- backend returns the first page of non-archived items by default

### 12.2 Archived visibility

Defaults:

- archived items hidden by default
- archived locations hidden from selection/search by default
- archived authors hidden from suggestion lists by default
- archived organizations hidden from suggestion lists by default

Admin-only option:

- `includeArchived=true`

### 12.3 Item detail screen layout

The item detail UI should show two separate sections:

1. `Current / Planned Status`
   - current location or current organization
   - promised organization
   - expected leave date
2. `History`
   - actual internal/external placement records only

Promised fields are visible in the UI but do not create timeline rows by themselves.

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

## 16. Security Boundaries

### Host-only

- onboarding
- host admin password login
- mobile QR generation/finalization
- web access approval/rejection
- device revoke/change role
- installation settings

### LAN-accessible to approved devices

- item list/detail/search
- item create/edit
- planning updates
- movement/rental events
- per-item history
- location management for admin devices

### Role differences

`EDITOR` can:

- create items
- edit item metadata
- update planning fields
- create authors during item flows
- create organizations during planning/rental flows
- add move/rental/return events

`ADMIN` can do everything `EDITOR` can, plus:

- archive items
- create/edit/archive locations
- use admin-level inventory actions in the regular client app

Only the host-only admin UI can:

- onboard the installation
- approve/reject devices
- revoke devices
- change device roles
- change installation settings/password

## 17. Practical Implementation Order

Build the prototype in this order:

1. Create backend project with modules:
   - `settings`, `auth`, `devices`, `items`, `authors`, `locations`, `organizations`, `history`
2. Add PostgreSQL and Flyway.
3. Create migrations for:
   - `app_settings`
   - device tables
   - business tables
4. Implement host admin onboarding and password login.
5. Implement registered-device model and database-backed refresh sessions.
6. Implement iPhone QR pairing flow.
7. Implement web access request + approval flow.
8. Implement item create flow with:
   - initial location
   - authors
   - secondary numbers
   - first history row
9. Implement movement/rental/return logic and current-state updates.
10. Implement item list/search/history APIs.
11. Build React app:
    - regular client routes
    - host admin routes
    - device startup screen
12. Build SwiftUI iPhone app:
    - QR scan
    - activation wait screen
    - inventory list/detail/edit/history
13. Add Caddy + Docker Compose.
14. Demo on:
    - your computer as server
    - your iPhone as editor device

## 18. Prototype Deliverable Summary

At the end of the prototype, you should have:

- one Docker-based local stack
- one Spring Boot backend
- one PostgreSQL database
- one React web app served by Caddy
- one host-only admin flow on `localhost`
- one iPhone app that scans QR once and then opens directly into inventory on later launches
- full item current-state tracking
- full item movement/rental history
- device approval/revocation

This is a strong prototype for the challenge because it demonstrates:

- real local-network architecture
- native iPhone experience
- cross-platform desktop access
- practical security model
- room for a clean long-term production deployment
