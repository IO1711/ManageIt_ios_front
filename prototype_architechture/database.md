## 2. Core Product Rules

- Each installation belongs to exactly one organization.
- The organization name is set during onboarding.
- Locations form a hierarchy such as `Room 1 > Shelf 1 > Grid A`.
- A location can contain sub-locations such as shelves, grids, drawers, and similar internal divisions.
- Sub-locations can themselves contain more sub-locations.
- Location names only need to be unique among siblings under the same parent.
- Items can only be placed in leaf locations with no children.
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
- An exhibition:
  - happens at exactly one internal leaf location
  - has a start date and end date
  - can contain multiple items during that period
- During an active exhibition, every included item must:
  - remain `INTERNAL`
  - have `items.current_location_id` exactly equal to the exhibition location
- The same item can never belong to two exhibitions whose date ranges overlap.
- Ended exhibitions and their linked item sets are kept permanently as exhibition history.
- Open external rentals with an `expected_return_date` should trigger a client-local reminder 3 calendar days before that date.
- The rental reminder should identify the item, the external organization where it currently is, and that the expected return is in 3 days.

### 6.4 Item creation flow

1. User enters item metadata.
2. User selects or creates authors.
3. User adds optional secondary inventory numbers.
4. User selects the initial internal leaf location.
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
- `location_id` must reference a leaf location
- `expected_return_date` stays `null`

For external rental:

- new history row points to an `organization_id`
- `expected_return_date` can be filled
- `expected_return_date` is the source date for the 3-day rental return reminder on clients
- `items.current_presence_type` becomes `EXTERNAL`
- `items.current_organization_id` is set
- `items.current_location_id` becomes `null`
- `items.promised_organization_id` is cleared
- `items.expected_leave_date` is cleared

### 6.6 Item return flow

When an item returns from an external organization:

1. User creates a normal new internal movement event.
2. User selects the leaf location where the item is placed again.
3. Backend closes the external history row automatically.
4. Backend creates a new internal history row.
5. Backend updates `items.current_location_id`.

### 6.7 Exhibition flow

When creating or editing an exhibition:

1. User enters the exhibition name, internal location, start date, end date, and item group.
2. Backend validates the exhibition location is a leaf internal location.
3. Backend validates `start_date <= end_date`.
4. Backend validates the same item is not already linked to another exhibition whose date range overlaps.
5. If the exhibition is already active for the relevant business date, backend validates every included item is currently `INTERNAL` and `items.current_location_id` exactly equals the exhibition location.
6. Backend stores the exhibition row and its linked item rows.
7. Ended exhibitions remain queryable as exhibition history.

Notification note:

- Exhibition end reminders are client-local only.
- Rental return reminders are client-local only.
- For an open external rental with `expected_return_date`, clients should schedule a reminder 3 calendar days before that date.
- Rental reminders should identify the item and the current external organization, and say the expected return is in 3 days.
- When an exhibition date range or an open rental `expected_return_date` changes, clients must reschedule the corresponding local reminder from the latest returned dates.
- When an open rental row is closed by return, clients must cancel the rental reminder.

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
- `exhibitions`
- `items`
- `item_secondary_numbers`
- `item_authors`
- `item_history`
- `exhibition_items`

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

For `item_history`, `created_by_device_id` is the registered device/browser/iPhone that created the movement row. Clients should resolve that device through `registered_devices.friendly_name` for the "moved by" display.

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

Stores hierarchical internal museum locations.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `parent_location_id` | `BIGINT NULL REFERENCES locations(id)` | Null for top-level locations |
| `name` | `VARCHAR(255) NOT NULL` | Case-insensitive unique among siblings |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `is_archived` | `BOOLEAN NOT NULL DEFAULT FALSE` | Soft delete |
| `archived_at` | `TIMESTAMPTZ NULL` | Archive time |
| `archived_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |

Rules:

- `parent_location_id = null` means a top-level location
- child locations may nest recursively
- backend must reject self-parenting and cycles
- item placement and internal history rows may reference only leaf locations
- locations with history should never be hard-deleted

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

#### `exhibitions`

Stores exhibitions and the period/location where they happen.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `name` | `VARCHAR(255) NOT NULL` | Exhibition name |
| `location_id` | `BIGINT NOT NULL REFERENCES locations(id)` | Leaf internal location where the exhibition happens |
| `start_date` | `DATE NOT NULL` | Planned/actual start |
| `end_date` | `DATE NOT NULL` | Planned/actual end |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Audit |

Rules:

- `location_id` must point to a leaf location
- `start_date` must be less than or equal to `end_date`
- an active exhibition means the business date is inside the inclusive range `[start_date, end_date]`
- ended exhibitions remain stored and queryable as history

#### `items`

Stores the current state and planning state for each item.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `BIGSERIAL PRIMARY KEY` | Business id |
| `main_inventory_number` | `VARCHAR(100) NOT NULL` | Unique, case-insensitive |
| `title` | `VARCHAR(255) NOT NULL` | Required |
| `current_presence_type` | `VARCHAR(20) NOT NULL` | `INTERNAL`, `EXTERNAL` |
| `current_location_id` | `BIGINT NULL REFERENCES locations(id)` | Used when internal, must reference a leaf location |
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
- when `current_location_id` is set, it must point to a leaf location

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
| `location_id` | `BIGINT NULL REFERENCES locations(id)` | Used for internal rows, must reference a leaf location |
| `organization_id` | `BIGINT NULL REFERENCES organizations(id)` | Used for external rows |
| `move_in_date` | `DATE NOT NULL` | Start of that placement period |
| `expected_return_date` | `DATE NULL` | Only for external rows |
| `move_out_date` | `DATE NULL` | Null while this row is the current open row |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |
| `created_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Device/browser/iPhone that created the move/rental row |
| `updated_by_device_id` | `UUID NULL REFERENCES registered_devices(id)` | Device/browser/iPhone that later closed/edited it |

Rules:

- exactly one currently open row per item
- open row means `move_out_date IS NULL`
- internal rows:
  - `location_id` set
  - `location_id` points to a leaf location
  - `organization_id` null
  - `expected_return_date` null
- external rows:
  - `organization_id` set
  - `location_id` null
  - `expected_return_date` optional
- `created_by_device_id` is the movement actor record for that history row and should be displayed together with the registered device friendly name when available

#### `exhibition_items`

Stores the item group linked to each exhibition.

| Column | Type | Notes |
| --- | --- | --- |
| `exhibition_id` | `BIGINT NOT NULL REFERENCES exhibitions(id)` | Parent exhibition |
| `item_id` | `BIGINT NOT NULL REFERENCES items(id)` | Linked item |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Audit |

Primary key:

- `(exhibition_id, item_id)`

Rules:

- the same item cannot be linked twice to the same exhibition
- service-layer validation must reject linking the same item to another exhibition whose date range overlaps
- when the linked exhibition is active, the linked item must have `current_presence_type = INTERNAL`
- when the linked exhibition is active, the linked item must have `current_location_id = exhibitions.location_id`
- ended exhibitions and their linked item rows form the exhibition history record

### 7.5 Recommended constraints

- Case-insensitive uniqueness:
  - `items.main_inventory_number`
  - `authors.name`
  - `locations.name` among siblings with the same parent
  - `organizations.name`
- Check constraints:
  - valid `role`
  - valid `device_type`
  - valid `presence_type`
  - valid current-state combinations on `items`
  - valid target combinations on `item_history`
  - `exhibitions.start_date <= exhibitions.end_date`
  - `locations.parent_location_id <> locations.id`
- Service-layer validations:
  - prevent location cycles
  - reject non-leaf locations in item create/move/return flows
  - reject non-leaf exhibition locations
  - reject overlapping exhibition memberships for the same item
  - reject active exhibition memberships whose items are not currently internal at the exhibition location
- One active history row per item:
  - partial unique index on `item_history(item_id)` where `move_out_date IS NULL`
- One active session per device:
  - partial unique index on `device_sessions(device_id)` where `revoked_at IS NULL`

### 7.6 Recommended indexes

Use these indexes from the beginning:

- unique index on `LOWER(items.main_inventory_number)`
- index on `locations.parent_location_id`
- index on `items.current_location_id`
- index on `items.current_organization_id`
- index on `items.promised_organization_id`
- unique index on `LOWER(authors.name)`
- unique index on `LOWER(locations.name)` where `parent_location_id IS NULL`
- unique index on `(parent_location_id, LOWER(name))` where `parent_location_id IS NOT NULL`
- unique index on `LOWER(organizations.name)`
- index on `exhibitions.location_id`
- index on `exhibitions.start_date`
- index on `exhibitions.end_date`
- index on `item_secondary_numbers(item_id)`
- index on `LOWER(item_secondary_numbers.secondary_inventory_number)`
- index on `item_authors(author_id)`
- index on `item_history(item_id, move_in_date DESC)`
- partial unique index on `item_history(item_id)` where `move_out_date IS NULL`
- partial index on `item_history(expected_return_date)` where `presence_type = 'EXTERNAL' AND move_out_date IS NULL AND expected_return_date IS NOT NULL`
- index on `exhibition_items(exhibition_id)`
- index on `exhibition_items(item_id)`
- unique index on `web_access_requests.approval_code`
- unique index on `mobile_pairing_sessions.pairing_token`

Search note:

- For the prototype, simple indexed `ILIKE` queries are enough.
- If the dataset grows a lot, add PostgreSQL `pg_trgm` indexes later for faster partial text search on title/numbers/names.
