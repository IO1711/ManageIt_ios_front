## Implementation Rule

Before implementing any endpoint:

- first check the already implemented backend endpoints
- first check `implementation_doc/backend_impl_process.md`
- only implement endpoints that were not implemented before
- do not recreate or recount an older endpoint as a new implementation

## 11. API Design

The API is REST JSON.

There is one shared backend contract:

- iPhone app talks to the backend
- React web/PWA talks to the same backend
- clients do not talk to each other directly

### 11.0 Backend controller documentation convention

For backend controller implementation:

- every endpoint method should have a short block comment directly above it
- the comment should show what the endpoint expects to receive
- for JSON body endpoints, show an example JSON object
- for endpoints with no request body, explicitly write:
  - `No request body.`
- after implementing a new API endpoint, update `documentation/backend.html`
  - add the new API to the left-side implemented API menu
  - add its workflow/details so the visualization stays in sync with the backend
- after implementing a new API endpoint, update `implementation_doc/backend_impl_process.md`
  - append the new implementation history at the bottom
  - never delete previous history entries
- every new implementation always needs both documentation updates
  - update `implementation_doc/backend_impl_process.md`
  - update `documentation/backend.html`

Example style:

```java
/*
    {
        "password": "string"
    }
*/
@PostMapping("/login")
public ResponseEntity<?> login(@RequestBody LoginRequest request) {
    ...
}
```

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
| `POST` | `/api/mobile/pairings/scan` | iPhone submits pairing token, stable installation id, and device info |
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
  "installationId": "11111111-1111-1111-1111-111111111111",
  "suggestedName": "iPhone 15 Pro",
  "platformName": "iOS",
  "platformVersion": "18.0",
  "modelName": "iPhone 15 Pro"
}
```

`installationId` is a stable UUID that the iPhone app stores in Keychain per app install. The backend uses it to reuse the same `IOS_APP` registered-device row when that phone pairs again, instead of creating duplicates.

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
