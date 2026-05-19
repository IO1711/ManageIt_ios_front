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
| `installation_id` | `UUID NULL` | Stable client-install identity, currently used by `IOS_APP` |
| `browser_name` | `VARCHAR(100) NULL` | For web clients |
| `browser_version` | `VARCHAR(100) NULL` | For web clients |
| `last_seen_at` | `TIMESTAMPTZ NULL` | Last successful activity |
| `revoked_at` | `TIMESTAMPTZ NULL` | Revocation moment |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

Notes:

- Each browser profile becomes its own registered device.
- Chrome and Safari on the same machine count as different devices.
- `installation_id` must be unique per (`device_type`, `installation_id`) when present.
- Re-pairing the same iPhone app install should reuse the same `registered_devices` row instead of creating duplicates.

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
| `installation_id` | `UUID NULL` | Stable iPhone app-install identity from Keychain |
| `registered_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Filled on completion |
| `server_base_url` | `VARCHAR(512) NULL` | LAN-reachable backend base URL embedded into the QR |
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
