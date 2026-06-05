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
- once authenticated, that host-admin session may call any protected backend API, including the normal inventory and lookup APIs

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
- persisted authenticator material:
  - for the current prototype, this means the refresh token plus the stable `installationId`
  - if a future persisted value can authenticate or re-authenticate the device by itself, it also belongs in the iOS Keychain
- recoverable paired-device summary:
  - fields such as `deviceId`, role, friendly name, remembered server address, and refresh expiry may be cached outside Keychain because they do not authenticate the device by themselves

### 5.5 Session model

- refresh tokens are database-backed, not stateless
- one active refresh session per registered device
- repeated pairing from the same iPhone app install reuses the same registered device row through the stable Keychain `installationId`
- if a device re-registers or a new session replaces an old one, the previous one is revoked
- revoking a device also revokes its active session

### 6.1 First installation onboarding

1. Open host-only admin UI on `localhost`.
2. Set organization name.
3. Set installation-wide admin password.
4. Add the initial location tree.
5. Mark onboarding complete.

The system is not considered ready until at least one leaf location exists.

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
- exhibition list/detail/history
- protected exhibition management APIs according to role checks
- hierarchical location management for admin devices
- the same protected APIs may also be used by an authenticated host-admin session

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
- create root/child locations, rename locations, archive locations
- use admin-level inventory actions in the regular client app

The host admin can also use any protected API regardless of device role, because it is a separate trusted operator session rather than a registered device.

Only the host-only admin UI can:

- onboard the installation
- approve/reject devices
- revoke devices
- change device roles
- change installation settings/password
