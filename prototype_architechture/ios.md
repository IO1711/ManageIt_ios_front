### 4.3 iPhone app

| Technology / Framework | Purpose |
| --- | --- |
| `SwiftUI` | Native iPhone UI |
| `Observation` | State management in the SwiftUI app |
| `URLSession` | HTTP networking |
| `Keychain Services` | Secure storage for the refresh token, the stable installation identity, and any future persisted authenticator material |
| `AVFoundation` | QR code scanning |
| `Foundation` | Models, dates, formatting, decoding |

### 6.2 iPhone registration flow

1. Host admin opens the host-only admin UI.
2. Host admin chooses role:
   - `ADMIN`
   - `EDITOR`
3. Host admin generates a QR code.
4. The QR contains a short-lived pairing token plus the LAN-reachable backend base URL that the iPhone should call.
5. iPhone app scans the QR.
6. iPhone app loads or creates a stable `installationId` in Keychain and sends it with the token plus device metadata to the backend.
7. Host admin UI shows a final step:
   - use generated generic device name
   - or enter a custom friendly name
8. The backend saves the registered device, or reuses the existing `IOS_APP` device row for that same `installationId`.
9. The iPhone app receives credentials/tokens and becomes active.

There is no second approval decision for the phone. The QR generation itself is the approval step.

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

Finished authenticated shell:

- use a tab bar root
- Inventory is the primary tab
- editing, planning, movement, and history stay inside the Inventory navigation flow instead of becoming their own top-level tabs
- admin-only location management may appear as a separate tab when the current device role is `ADMIN`
- a device/session tab can hold logout, pairing summary, and future session diagnostics

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
- load or create a stable `installationId` in Keychain
- send pairing token, installation identity, and device metadata
- wait while host admin finalizes naming
- store refresh token in Keychain
- keep the stable `installationId` in Keychain across re-pairings
- keep access token in memory
- keep recoverable paired-device summary data outside Keychain unless it can authenticate the device by itself
- refresh session when needed
- go directly to inventory list on future launches unless revoked

### 10.4 Working instructions for this iPhone prototype

- implement iPhone features one at a time
- after one feature is added, stop and wait for validation before continuing
- check `documentation` first for backend behavior and API details
- read `backend` only when the needed detail is not available in `documentation`
- keep the visual style a little artistic because this is for museum staff
- keep usability and data clarity higher priority than decorative styling
- when requirements are unclear, ask questions and do not assume
