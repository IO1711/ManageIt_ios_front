## Implementation Rule

Implement one frontend feature at a time. When one feature is finished, wait for user validation before continuing.

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
  - moved-by device display
- `exhibitions`
  - exhibition list/detail
  - create/edit exhibition
  - past exhibition history
  - local end reminder state
- `notifications`
  - local exhibition end reminders
  - local rental return reminders
- `planning`
  - promised organization
  - expected leave date
- `locations-admin`
  - browse location hierarchy
  - add root location
  - add child location
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
    /exhibitions
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
- render hierarchical location selectors with full-path labels
- allow only leaf locations in item placement selectors
- show planned/active/ended exhibitions with their linked item group
- show moved-by device friendly name in history views when available
- schedule, reschedule, and cancel local exhibition-end reminders from the latest exhibition `endDate`
- schedule, reschedule, and cancel local rental-return reminders 3 calendar days before an open external row's `expectedReturnDate`
- do not auto-assume an exact typed author/org is an existing one
- show duplicate main number conflict details if backend returns them

### 9.5 PWA notes

Include:

- manifest
- app icons
- standalone window metadata
- install metadata
- exhibition-end reminders as a client-local feature when browser support and notification permission exist
- rental-return reminders as a client-local feature when browser support and notification permission exist

Do not rely on in the prototype demo:

- offline data
- offline writes
- background sync
- backend push notifications for exhibition reminders
- backend push notifications for rental reminders

## 12. Search, List, and Visibility Rules

### 12.1 Item list/search

Search should support:

- main inventory number
- secondary inventory numbers
- title
- author name
- current location name
- current location full path

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
- archived locations hidden from tree selection/search by default
- archived authors hidden from suggestion lists by default
- archived organizations hidden from suggestion lists by default

Admin-only option:

- `includeArchived=true`

### 12.3 Item detail screen layout

The item detail UI should show two separate sections:

1. `Current / Planned Status`
   - current location path or current organization
   - current exhibition, if active
   - promised organization
   - expected leave date
2. `History`
   - actual internal/external placement records only
   - moved-by device friendly name when available

Promised fields are visible in the UI but do not create timeline rows by themselves.

### 12.4 Exhibition reminder behavior

- Exhibition reminders are client-local only.
- The web/PWA should schedule reminders from the latest exhibition `endDate` returned by the backend.
- If an exhibition date range changes, the client must reschedule the existing reminder for that exhibition.
- If an exhibition disappears from the accessible dataset or notification permission is removed, the client should cancel its local reminder.
- Exact reminder timing is a frontend product decision and is not fixed by this architecture document.
- Browser/PWA reminder delivery is best-effort and depends on notification permission and platform support.

### 12.5 Rental return reminder behavior

- Rental return reminders are client-local only.
- The web/PWA should schedule a reminder 3 calendar days before `expectedReturnDate` for an open external rental row.
- The reminder should identify the item and the organization where it is currently recorded, and say it is due back in 3 days.
- If `expectedReturnDate` changes, the client must reschedule the existing reminder for that rental row.
- If the rental row closes on return, disappears from the accessible dataset, or notification permission is removed, the client should cancel its local reminder.
- Browser/PWA reminder delivery is best-effort and depends on notification permission and platform support.
