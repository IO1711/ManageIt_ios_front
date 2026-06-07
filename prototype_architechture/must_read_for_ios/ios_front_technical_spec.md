# iOS Front Technical Specification

This document is the technical specification for `ios_front`.

It has two jobs:

1. document the current Swift codebase in detail
2. define what the prototype iPhone app still must implement to match the prototype architecture plan

This is not a product-vision summary. It is the implementation-facing reference for iOS work.

## How To Use This Document

- If you need current repo reality, read `Part I. Current Implementation Reference`.
- If you are continuing iOS development, start at `Part II. Required Prototype Completion Spec`.
- If you need the remaining architecture decisions, read `Part III. Open Decisions And Blockers`.
- The Markdown iOS docs are canonical. The HTML companion is optional and may be easier to read, but it should be kept in sync with Markdown. If it ever differs, trust Markdown.

## Document Map

- `Executive Summary`: current scope and the definition of prototype-complete
- `Part I. Current Implementation Reference`: current files, types, functions, and backend contract already used by the app
- `Part II. Required Prototype Completion Spec`: everything that still must be implemented
- `Part III. Open Decisions And Blockers`: unresolved source-of-truth gaps

## Source Of Truth

Use these files in this order when there is a conflict:

1. `prototype_architechture/prototype_architechture.md`
2. `prototype_architechture/ios.md`
3. `prototype_architechture/auth.md`
4. `prototype_architechture/api.md`
5. `prototype_architechture/database.md`

Current code is not automatically the source of truth when it diverges from the prototype architecture.

## Scope

This document covers:

- every current Swift file in `ios_front/ManageIt/ManageIt`
- every current class, struct, enum, and extension in the iOS app
- every current function and computed member with meaningful behavior
- the backend contract the iPhone app already uses
- the remaining technical requirements for the iPhone app to be prototype-complete
- the places where the architecture does not yet define enough detail to finish implementation without clarification

## Executive Summary

### Implemented Today

Implemented today:

- app bootstrap
- pairing UI
- QR scanning
- manual pairing-link fallback
- pairing scan request
- pairing status polling
- pairing completion request
- refresh-token persistence in Keychain
- stable `installationId` persistence in Keychain
- local paired-device context persistence
- post-pairing placeholder screen

### Not Implemented Today

Not implemented today:

- launch-time session restore
- general authenticated device API layer
- inventory list
- inventory detail
- item create/edit
- planning update UI
- movement/rental/return UI
- item history UI
- admin item archive UI
- admin location-management UI
- automated tests

### Definition Of Complete Prototype

According to `prototype_architechture/prototype_architechture.md`, the prototype iPhone app is complete only when it:

- scans the host QR once and activates the iPhone as a device
- stores the stable installation identity in Keychain
- stores the refresh token in Keychain
- keeps the access token in memory only
- refreshes sessions when needed
- opens directly into inventory on future launches unless revoked
- supports inventory list/detail/edit/history behavior consistent with the shared backend contract
- respects role boundaries between `EDITOR` and `ADMIN`

## Part I. Current Implementation Reference

Everything in Part I documents the iPhone app exactly as it exists today.

### Current Project Configuration

Project file:

- `ios_front/ManageIt/ManageIt.xcodeproj`

Current relevant Xcode settings from the project file:

- bundle identifier: `com.bestAppleDev.ManageIt`
- deployment target: `26.2`
- Swift version: `5.0`
- generated Info.plist: enabled
- camera usage description:
  - `ManageIt uses the camera to scan pairing QR codes from the museum host screen.`

Important current configuration gap:

- the prototype architecture expects plain HTTP for the prototype LAN setup
- the current project does not document or expose an explicit App Transport Security exception strategy for that prototype mode

### Current Swift Code Reference

#### `ios_front/ManageIt/ManageIt/ManageItApp.swift`

##### `ManageItApp`

- Kind: `struct`
- Conforms to: `App`
- Purpose: application entrypoint

Stored members:

- `appModel: AppModel`
  - created once with `@State`
  - owns the root app state

Computed members:

- `body -> some Scene`
  - Expects: no arguments; uses `appModel`
  - Returns: one `WindowGroup` containing `ContentView(appModel:)`
  - Responsibility: boot the root SwiftUI scene

#### `ios_front/ManageIt/ManageIt/AppModel.swift`

##### `AppModel`

- Kind: `final class`
- Annotations: `@MainActor`, `@Observable`
- Purpose: root app state container and dependency wiring layer

Stored members:

- `pairedDevice: StoredDeviceContext?`
  - local persisted paired-device summary currently loaded from `AppPreferences`
- `activeSession: ActiveDeviceSession?`
  - in-memory authenticated session
- `pairingModel: PairingFeatureModel`
  - feature model used by the pairing UI
- `preferences: AppPreferences`
  - private persistence wrapper for `UserDefaults`
- `keychainStore: KeychainStore`
  - private persistence wrapper for Keychain

Functions:

- `init()`
  - Expects: no arguments
  - Returns: initialized `AppModel`
  - Responsibility:
    - create `AppPreferences`
    - create `KeychainStore`
    - create `ManageItAPIClient`
    - restore `pairedDevice` from preferences
    - initialize `activeSession` to `nil`
    - create `PairingFeatureModel` with remembered `serverAddress`
    - assign `pairingModel.onActivationComplete`

- `clearLocalPairing()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - clear refresh token from Keychain
    - clear paired-device context from `UserDefaults`
    - set `activeSession = nil`
    - set `pairedDevice = nil`
    - reset the pairing feature while preserving the remembered server address

- `storeActivatedDevice(response:serverAddress:)`
  - Visibility: private
  - Expects:
    - `response: MobilePairingCompleteResponse`
    - `serverAddress: String`
  - Returns: `Void`
  - Throws:
    - `ManageItError.secureStorageFailed` if refresh-token persistence fails
  - Responsibility:
    - save refresh token in Keychain
    - create a `StoredDeviceContext`
    - persist `serverAddress`
    - persist paired-device context
    - populate `pairedDevice`
    - populate `activeSession`

#### `ios_front/ManageIt/ManageIt/ContentView.swift`

##### `ContentView`

- Kind: `struct`
- Conforms to: `View`
- Purpose: root view switch between pairing and post-pairing branches

Stored members:

- `appModel: AppModel`

Computed members:

- `body -> some View`
  - Expects: no explicit arguments; reads `appModel`
  - Returns:
    - `PairingFeatureView` when `pairedDevice == nil`
    - `DeviceReadyView` when `pairedDevice != nil`
  - Responsibility: current root-state routing

##### `DeviceReadyView`

- Kind: private `struct`
- Conforms to: `View`
- Purpose: current placeholder screen after successful pairing

Stored members:

- `pairedDevice: StoredDeviceContext`
- `hasActiveSession: Bool`
- `clearLocalPairing: () -> Void`

Computed members:

- `body -> some View`
  - Expects: injected paired device and local clear callback
  - Returns: placeholder ready screen with pairing summary
  - Responsibility:
    - show friendly name, role, device type, server, refresh-expiry
    - show whether a live session exists
    - expose `Clear local pairing`

Functions:

- `deviceRow(_:_:) -> some View`
  - Visibility: private
  - Expects:
    - `label: String`
    - `value: String`
  - Returns: one vertically stacked label/value row
  - Responsibility: present read-only summary values

#### `ios_front/ManageIt/ManageIt/Features/Pairing/PairingFeature.swift`

##### `PairingFeatureView`

- Kind: `struct`
- Conforms to: `View`
- Purpose: complete current pairing UI

Stored members:

- `store: PairingFeatureModel`

Computed members:

- `body -> some View`
  - Expects: a `PairingFeatureModel`
  - Returns:
    - scanner + manual entry UI when `phase.showsScanner == true`
    - waiting UI otherwise
    - optional error card when `errorMessage` is non-`nil`
  - Responsibility: main pairing screen composition

- `header -> some View`
  - Visibility: private
  - Expects: no explicit arguments
  - Returns: title and explanatory copy

- `scannerCard -> some View`
  - Visibility: private
  - Expects: no explicit arguments; reads `store.phase`, `store.scannerHelperText`, `store.updateScannerState`
  - Returns: QR-scanner card
  - Responsibility:
    - embed `QRScannerView`
    - start `beginPairing(from:)` on code scan
    - show progress overlay during `.submitting`

- `waitingCard -> some View`
  - Visibility: private
  - Expects: no explicit arguments; reads `store.lastStatus`, `store.phase`, `store.statusHeadline`, `store.statusDetail`
  - Returns: waiting/progress card
  - Responsibility:
    - show status text
    - show progress rows
    - show expiry time when available

- `scannerStatusBadge -> some View`
  - Visibility: private
  - Expects: `store.scannerStatusTitle`
  - Returns: small state badge

Functions:

- `manualEntryCard(manualPairingCode:) -> some View`
  - Visibility: private
  - Expects: `Binding<String>` for the manual pairing code
  - Returns: manual-entry form with action button
  - Responsibility:
    - collect pasted pairing link
    - trigger `beginPairing(from:)`
    - disable action when `store.canStartPairingManually == false`

- `errorCard(_:) -> some View`
  - Visibility: private
  - Expects: `message: String`
  - Returns: styled error card
  - Responsibility: render visible failure state

- `sectionLabel(_:) -> some View`
  - Visibility: private
  - Expects: `title: String`
  - Returns: stylized section label

##### `PairingProgressRow`

- Kind: private `struct`
- Conforms to: `View`
- Purpose: compact row used inside the waiting state

Stored members:

- `title: String`
- `detail: String`
- `isActive: Bool`

Computed members:

- `body -> some View`
  - Expects: row title, detail, active state
  - Returns: one progress row with icon and text

#### `ios_front/ManageIt/ManageIt/Features/Pairing/PairingFeatureModel.swift`

##### `PairingFeatureModel`

- Kind: `final class`
- Annotations: `@MainActor`, `@Observable`
- Purpose: pairing state machine and orchestration layer

Stored members:

- `onActivationComplete: ((MobilePairingCompleteResponse, String) throws -> Void)?`
  - callback into `AppModel`
- `serverAddress: String`
  - remembered canonical server address
- `manualPairingCode: String`
  - current pasted manual code
- `phase: Phase`
  - current pairing phase
- `errorMessage: String?`
  - last user-facing error
- `lastStatus: MobilePairingStatusResponse?`
  - most recent pairing status response
- `scannerState: PairingScannerState`
  - current QR scanner availability state
- `statusHeadline: String`
- `statusDetail: String`
- `apiClient: ManageItAPIClient`
  - private networking dependency
- `keychainStore: KeychainStore`
  - private secure-storage dependency
- `pollTask: Task<Void, Never>?`
  - private polling task
- `isCompletingPairing: Bool`
  - private duplicate-completion guard

Computed members:

- `canStartPairingManually -> Bool`
  - Expects: `phase`, `manualPairingCode`
  - Returns: `true` only when the feature is ready and manual code is not blank

- `scannerStatusTitle -> String`
  - Expects: `scannerState`
  - Returns: short badge label for the current scanner state

- `scannerHelperText -> String`
  - Expects: `scannerState`
  - Returns: user-facing helper copy for the scanner state

Functions:

- `init(apiClient:keychainStore:initialServerAddress:)`
  - Expects:
    - `apiClient: ManageItAPIClient`
    - `keychainStore: KeychainStore`
    - `initialServerAddress: String`
  - Returns: initialized `PairingFeatureModel`

- `updateScannerState(_:)`
  - Expects: `newState: PairingScannerState`
  - Returns: `Void`
  - Responsibility: update observable scanner state

- `beginPairing(from:)`
  - Expects: `rawValue: String`
  - Returns: `Void` asynchronously
  - Does not throw outward; failures are converted into local UI state
  - Responsibility:
    - ignore calls unless `phase == .ready`
    - parse token and server
    - resolve or normalize the backend server URL
    - load or create `installationId`
    - build `DeviceMetadata`
    - call `scanPairing`
    - store canonical server address on success
    - either complete immediately or begin polling
    - convert all failures into `errorMessage` through `handleFailure(_:)`

- `reset(keepServerAddress:)`
  - Expects: `keepServerAddress: Bool`
  - Returns: `Void`
  - Responsibility:
    - cancel polling
    - restore the feature to its ready state
    - optionally clear the remembered server address

- `applyStatus(_:) -> Bool`
  - Visibility: private
  - Expects: `status: MobilePairingStatusResponse`
  - Returns:
    - `false` when the app should remain in the waiting state
    - `true` when the app should proceed to `completePairing`
  - Throws:
    - `ManageItError.pairingExpired`
    - `ManageItError.pairingCancelled`
  - Responsibility:
    - persist latest status
    - set phase and status copy

- `beginPolling(pairingId:server:)`
  - Visibility: private
  - Expects:
    - `pairingId: UUID`
    - `server: ResolvedServer`
  - Returns: `Void`
  - Responsibility:
    - cancel any previous poll task
    - poll every 2 seconds
    - call `fetchPairingStatus`
    - hand off to `completePairing` when status becomes `COMPLETED`
    - convert failures into `handleFailure(_:)`

- `completePairing(pairingId:server:cancelPollingTask:)`
  - Visibility: private
  - Expects:
    - `pairingId: UUID`
    - `server: ResolvedServer`
    - `cancelPollingTask: Bool = true`
  - Returns: `Void` asynchronously
  - Throws:
    - whatever `apiClient.completePairing` throws
    - whatever `onActivationComplete` throws
  - Responsibility:
    - prevent duplicate completion calls
    - optionally cancel the polling task
    - call pairing completion endpoint
    - pass the response back to the root app model

- `handleFailure(_:)`
  - Visibility: private
  - Expects: `error: Error`
  - Returns: `Void`
  - Responsibility:
    - cancel polling
    - return the feature to ready state
    - clear transient pairing status
    - translate the error into a user-facing message

- `parsePairingPayload(from:) -> PairingPayload`
  - Visibility: private
  - Expects: `rawValue: String`
  - Returns: parsed `PairingPayload`
  - Throws:
    - `ManageItError.invalidPairingCode`
  - Responsibility:
    - accept a raw UUID token
    - accept a full `manageit://pair?...` URL
    - extract `token`
    - optionally extract `server`

- `resolvedServer(explicitAddress:) -> ResolvedServer`
  - Visibility: private
  - Expects: `explicitAddress: String?`
  - Returns: normalized `ResolvedServer`
  - Throws:
    - `ManageItError.invalidServerAddress`
  - Responsibility:
    - prefer QR-embedded server
    - fall back to remembered server
    - prepend `http://` when no scheme is present
    - strip trailing `/`
    - normalize away a base `/api` path

##### `PairingFeatureModel.Phase`

- Kind: nested `enum`
- Cases:
  - `ready`
  - `submitting`
  - `waiting`
  - `finalizing`

Computed members:

- `showsScanner -> Bool`
  - Returns `true` during `ready` and `submitting`

##### `ResolvedServer`

- Kind: private `struct`
- Purpose: normalized server result used during pairing

Stored members:

- `url: URL`
- `canonicalAddress: String`

##### `PairingPayload`

- Kind: private `struct`
- Purpose: parsed QR/manual-link payload

Stored members:

- `pairingToken: UUID`
- `serverAddress: String?`

#### `ios_front/ManageIt/ManageIt/Features/Pairing/QRScannerView.swift`

##### `PairingScannerState`

- Kind: `enum`
- Purpose: scanner availability and permission state
- Cases:
  - `idle`
  - `requestingPermission`
  - `cameraReady`
  - `permissionDenied`
  - `unavailable`

##### `QRScannerView`

- Kind: `struct`
- Conforms to: `UIViewRepresentable`
- Purpose: bridge `AVCaptureSession`-backed QR scanning into SwiftUI

Stored members:

- `isEnabled: Bool`
- `onCodeScanned: (String) -> Void`
- `onStateChanged: (PairingScannerState) -> Void`

Functions:

- `makeCoordinator() -> Coordinator`
  - Expects: no arguments
  - Returns: `Coordinator`
  - Responsibility: create the capture-session coordinator

- `makeUIView(context:) -> ScannerPreviewView`
  - Expects: SwiftUI representable `Context`
  - Returns: configured preview view
  - Responsibility:
    - create the preview view
    - assign video gravity
    - attach preview session

- `updateUIView(_:context:)`
  - Expects:
    - `uiView: ScannerPreviewView`
    - `context: Context`
  - Returns: `Void`
  - Responsibility:
    - reattach preview
    - enable or disable the coordinator

- `dismantleUIView(_:coordinator:)`
  - Expects:
    - `uiView: ScannerPreviewView`
    - `coordinator: Coordinator`
  - Returns: `Void`
  - Responsibility: stop capture when the view is removed

##### `QRScannerView.Coordinator`

- Kind: nested `final class`
- Inherits: `NSObject`
- Conforms to: `AVCaptureMetadataOutputObjectsDelegate`
- Purpose: camera permissions, capture-session lifecycle, QR decode callbacks

Stored members:

- `onCodeScanned: (String) -> Void`
- `onStateChanged: (PairingScannerState) -> Void`
- `session: AVCaptureSession`
- `sessionQueue: DispatchQueue`
- `previewView: ScannerPreviewView?`
- `didConfigureSession: Bool`
- `lastScannedCode: String?`
- `isEnabled: Bool`

Functions:

- `init(onCodeScanned:onStateChanged:)`
  - Expects the two callback closures
  - Returns: initialized coordinator

- `attachPreview(_:)`
  - Expects: `previewView: ScannerPreviewView`
  - Returns: `Void`
  - Responsibility: attach the capture session to the preview layer

- `setEnabled(_:)`
  - Expects: `enabled: Bool`
  - Returns: `Void`
  - Responsibility:
    - start preparing camera when enabled
    - clear dedupe state and stop capture when disabled

- `stop()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility: stop `AVCaptureSession` asynchronously

- `prepareCamera()`
  - Visibility: private
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - inspect camera authorization status
    - request permission when needed
    - forward resulting `PairingScannerState`

- `configureIfNeededAndStart()`
  - Visibility: private
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - exit early when disabled
    - verify a video device exists
    - configure session once
    - mark camera ready
    - start running the session

- `configureSession()`
  - Visibility: private
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - create `AVCaptureDeviceInput`
    - attach input and metadata output
    - restrict metadata scanning to `.qr`
    - mark configuration success

- `metadataOutput(_:didOutput:from:)`
  - Expects AVFoundation metadata callback arguments
  - Returns: `Void`
  - Responsibility:
    - ignore scans when disabled
    - accept the first QR code string
    - dedupe identical scans for 1.5 seconds
    - call `onCodeScanned`

##### `ScannerPreviewView`

- Kind: `final class`
- Inherits: `UIView`
- Purpose: host `AVCaptureVideoPreviewLayer`

Computed members:

- `layerClass -> AnyClass`
  - Returns: `AVCaptureVideoPreviewLayer.self`

- `previewLayer -> AVCaptureVideoPreviewLayer`
  - Returns: typed preview layer cast from `layer`

#### `ios_front/ManageIt/ManageIt/Networking/ManageItAPIClient.swift`

##### `ManageItAPIClient`

- Kind: `struct`
- Purpose: current REST client for pairing endpoints

Stored members:

- `urlSession: URLSession`
- `decoder: JSONDecoder`
- `encoder: JSONEncoder`

Functions:

- `init(urlSession:)`
  - Expects: `urlSession: URLSession = .shared`
  - Returns: initialized API client
  - Responsibility:
    - configure `JSONDecoder` with `.iso8601`
    - configure `JSONEncoder` with `.iso8601`

- `scanPairing(serverURL:request:) -> MobilePairingStatusResponse`
  - Expects:
    - `serverURL: URL`
    - `request: MobilePairingScanRequest`
  - Returns: decoded `MobilePairingStatusResponse`
  - Responsibility: call `POST /api/mobile/pairings/scan`

- `fetchPairingStatus(serverURL:pairingId:) -> MobilePairingStatusResponse`
  - Expects:
    - `serverURL: URL`
    - `pairingId: UUID`
  - Returns: decoded `MobilePairingStatusResponse`
  - Responsibility: call `GET /api/mobile/pairings/{id}`

- `completePairing(serverURL:pairingId:) -> MobilePairingCompleteResponse`
  - Expects:
    - `serverURL: URL`
    - `pairingId: UUID`
  - Returns: decoded `MobilePairingCompleteResponse`
  - Responsibility: call `POST /api/mobile/pairings/{id}/complete`

- `sendRequest(serverURL:path:method:body:) -> Response`
  - Visibility: private generic helper
  - Expects:
    - `serverURL: URL`
    - `path: String`
    - `method: String`
    - `body: Body?`
  - Returns: decoded `Response`
  - Throws:
    - `ManageItError.invalidServerAddress`
    - `ManageItError.transportFailure`
    - `ManageItError.backend`
    - `ManageItError.invalidResponse`
  - Responsibility:
    - construct the full endpoint URL
    - encode request body when present
    - execute the request
    - decode backend error envelopes on non-2xx responses
    - decode the success model on 2xx responses

- `buildURL(serverURL:path:) -> URL`
  - Visibility: private
  - Expects:
    - `serverURL: URL`
    - `path: String`
  - Returns: full backend API URL
  - Throws:
    - `ManageItError.invalidServerAddress`
  - Responsibility:
    - normalize away trailing `/`
    - strip duplicate `/api` from the base URL
    - append `/api` plus the requested path

- `transportFailure(for:error:) -> ManageItError`
  - Visibility: private
  - Expects:
    - `endpoint: URL`
    - `error: Error`
  - Returns: `ManageItError.transportFailure(...)`
  - Responsibility: create user-readable networking failures

- `transportFailureDetails(for:) -> String`
  - Visibility: private
  - Expects: `error: URLError`
  - Returns: best-effort human-readable message
  - Responsibility: map common `URLError` codes to stable copy

##### `APIErrorEnvelope`

- Kind: private `struct`
- Purpose: decode backend error payload wrapper

Stored members:

- `error: APIErrorBody`

##### `APIErrorBody`

- Kind: private `struct`
- Purpose: decode backend error object

Stored members:

- `code: String`
- `message: String`

#### `ios_front/ManageIt/ManageIt/Models/SessionModels.swift`

##### `DeviceRole`

- Kind: `enum`
- Raw type: `String`
- Conforms to: `Codable`, `Equatable`
- Cases:
  - `admin = "ADMIN"`
  - `editor = "EDITOR"`

Computed members:

- `displayName -> String`
  - Returns: capitalized role name for UI display

##### `DeviceType`

- Kind: `enum`
- Raw type: `String`
- Conforms to: `Codable`, `Equatable`
- Cases:
  - `iosApp = "IOS_APP"`
  - `webBrowser = "WEB_BROWSER"`

Computed members:

- `displayName -> String`
  - Returns:
    - `iOS App` for `.iosApp`
    - `Web Browser` for `.webBrowser`

##### `StoredDeviceContext`

- Kind: `struct`
- Conforms to: `Codable`, `Equatable`
- Purpose: locally persisted paired-device summary

Stored members:

- `serverAddress: String`
- `deviceId: UUID`
- `role: DeviceRole`
- `deviceType: DeviceType`
- `friendlyName: String`
- `refreshTokenExpiresAt: Date`

##### `ActiveDeviceSession`

- Kind: `struct`
- Conforms to: `Equatable`
- Purpose: in-memory authenticated session

Stored members:

- `context: StoredDeviceContext`
- `accessToken: String`
- `accessTokenExpiresAt: Date`

#### `ios_front/ManageIt/ManageIt/Models/PairingModels.swift`

##### `MobilePairingSessionStatus`

- Kind: `enum`
- Raw type: `String`
- Conforms to: `Codable`, `Equatable`
- Cases:
  - `generated`
  - `scanned`
  - `completed`
  - `cancelled`

##### `MobilePairingScanRequest`

- Kind: `struct`
- Conforms to: `Encodable`
- Purpose: request body for pairing scan

Stored members:

- `pairingToken: UUID`
- `installationId: UUID`
- `suggestedName: String`
- `platformName: String`
- `platformVersion: String`
- `modelName: String`

##### `MobilePairingStatusResponse`

- Kind: `struct`
- Conforms to: `Decodable`, `Equatable`
- Purpose: pairing status response model

Stored members:

- `pairingId: UUID`
- `status: MobilePairingSessionStatus`
- `expiresAt: Date`
- `scannedAt: Date?`
- `completedAt: Date?`
- `expired: Bool`
- `friendlyName: String?`

##### `MobilePairingCompleteResponse`

- Kind: `struct`
- Conforms to: `Decodable`, `Equatable`
- Purpose: final pairing completion payload

Stored members:

- `deviceId: UUID`
- `role: DeviceRole`
- `friendlyName: String`
- `accessToken: String`
- `accessTokenExpiresAt: Date`
- `refreshToken: String`
- `refreshTokenExpiresAt: Date`

#### `ios_front/ManageIt/ManageIt/Models/ManageItError.swift`

##### `ManageItError`

- Kind: `enum`
- Conforms to: `LocalizedError`
- Purpose: current app-wide error vocabulary

Cases:

- `invalidServerAddress`
- `invalidPairingCode`
- `pairingCancelled`
- `pairingExpired`
- `invalidResponse`
- `transportFailure(endpoint: String, details: String)`
- `backend(code: String, message: String)`
- `deviceIdentityUnavailable`
- `secureStorageFailed`

Computed members:

- `errorDescription -> String?`
  - Expects: current enum case
  - Returns: user-facing error copy
  - Responsibility: convert technical failures into readable UI messages

#### `ios_front/ManageIt/ManageIt/Storage/KeychainStore.swift`

##### `KeychainStore`

- Kind: `final class`
- Purpose: secure storage for refresh token and stable installation identity

Stored members:

- `service: String`
- `refreshTokenAccount: String`
- `installationIdAccount: String`

Functions:

- `saveRefreshToken(_:)`
  - Expects: `refreshToken: String`
  - Returns: `Void`
  - Throws: `KeychainStoreError.operationFailed`
  - Responsibility: persist the refresh token under the refresh-token account

- `loadOrCreateInstallationId() -> UUID`
  - Expects: no arguments
  - Returns: existing or newly generated `UUID`
  - Throws: `KeychainStoreError.operationFailed`
  - Responsibility:
    - load existing installation id when present
    - create and persist a new one otherwise

- `clearRefreshToken()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility: delete refresh token from Keychain

- `saveString(_:account:)`
  - Visibility: private
  - Expects:
    - `value: String`
    - `account: String`
  - Returns: `Void`
  - Throws: `KeychainStoreError.operationFailed`
  - Responsibility:
    - try `SecItemUpdate`
    - if not found, fall back to `SecItemAdd`

- `loadString(account:) -> String?`
  - Visibility: private
  - Expects: `account: String`
  - Returns:
    - decoded `String` when present
    - `nil` when not found
  - Throws: `KeychainStoreError.operationFailed`

- `clearValue(account:)`
  - Visibility: private
  - Expects: `account: String`
  - Returns: `Void`
  - Responsibility: delete one account entry

- `baseQuery(for:) -> [String: Any]`
  - Visibility: private
  - Expects: `account: String`
  - Returns: Keychain query dictionary

##### `KeychainStoreError`

- Kind: `enum`
- Conforms to: `Error`
- Cases:
  - `operationFailed(OSStatus)`

#### `ios_front/ManageIt/ManageIt/Storage/AppPreferences.swift`

##### `AppPreferences`

- Kind: `final class`
- Purpose: non-secure local preferences and cached device context

Stored members:

- `userDefaults: UserDefaults`
- `encoder: JSONEncoder`
- `decoder: JSONDecoder`

Functions:

- `init(userDefaults:)`
  - Expects: `userDefaults: UserDefaults = .standard`
  - Returns: initialized preferences wrapper
  - Responsibility:
    - configure date encoding/decoding as `.iso8601`

- `serverAddress -> String`
  - Expects: no explicit arguments
  - Returns: remembered server address or empty string
  - Responsibility: wrap `UserDefaults` get/set for the last server address

- `loadDeviceContext() -> StoredDeviceContext?`
  - Expects: no arguments
  - Returns:
    - decoded `StoredDeviceContext` when available
    - `nil` when absent or unreadable
  - Responsibility: restore persisted paired-device context

- `saveDeviceContext(_:)`
  - Expects: `context: StoredDeviceContext`
  - Returns: `Void`
  - Responsibility: encode and persist local paired-device context

- `clearDeviceContext()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility: remove local paired-device context

#### `ios_front/ManageIt/ManageIt/Utilities/DeviceMetadata.swift`

##### `DeviceMetadata`

- Kind: `struct`
- Purpose: current-device metadata payload for pairing

Stored members:

- `installationId: UUID`
- `suggestedName: String`
- `platformName: String`
- `platformVersion: String`
- `modelName: String`

Functions:

- `current(installationId:) -> DeviceMetadata`
  - Expects: `installationId: UUID`
  - Returns: populated `DeviceMetadata`
  - Responsibility:
    - use `UIDevice.current.model`
    - use `UIDevice.current.systemName`
    - use `UIDevice.current.systemVersion`
    - resolve a machine identifier for the model

- `machineIdentifier() -> String`
  - Visibility: private static
  - Expects: no arguments
  - Returns: hardware machine identifier string
  - Responsibility: read `utsname.machine`

#### `ios_front/ManageIt/ManageIt/SharedUI/AppTheme.swift`

##### `AppTheme`

- Kind: `enum`
- Purpose: central current visual palette

Static members:

- `canvas`
- `paper`
- `ink`
- `mutedInk`
- `subtleInk`
- `outline`
- `badgeBackground`
- `deepClay`
- `scannerFrame`
- `alertBackground`
- `alertBorder`

##### `MuseumPanelModifier`

- Kind: private `struct`
- Conforms to: `ViewModifier`
- Purpose: reusable card/panel styling

Functions:

- `body(content:) -> some View`
  - Expects: `content: Content`
  - Returns: padded rounded panel with border and shadow

##### `View` extension

Functions:

- `museumPanel() -> some View`
  - Expects: any `View`
  - Returns: the view with `MuseumPanelModifier` applied

### Implemented Backend Contract

The current iPhone app already depends on these backend endpoints.

#### Pairing Endpoints

- `POST /api/mobile/pairings/scan`
  - Request body:
    - `pairingToken: UUID`
    - `installationId: UUID`
    - `suggestedName: String`
    - `platformName: String`
    - `platformVersion: String`
    - `modelName: String`
  - Success response:
    - `pairingId: UUID`
    - `status: GENERATED | SCANNED | COMPLETED | CANCELLED`
    - `expiresAt: OffsetDateTime`
    - `scannedAt: OffsetDateTime?`
    - `completedAt: OffsetDateTime?`
    - `expired: Boolean`
    - `friendlyName: String?`

- `GET /api/mobile/pairings/{id}`
  - No request body
  - Success response: same shape as scan response

- `POST /api/mobile/pairings/{id}/complete`
  - No request body
  - Success response:
    - `deviceId: UUID`
    - `role: ADMIN | EDITOR`
    - `friendlyName: String`
    - `accessToken: String`
    - `accessTokenExpiresAt: OffsetDateTime`
    - `refreshToken: String`
    - `refreshTokenExpiresAt: OffsetDateTime`

#### Standard Error Shape

All backend error responses are expected to follow:

```json
{
  "error": {
    "code": "STRING_CODE",
    "message": "Human-readable message",
    "details": {}
  }
}
```

The current iPhone app only decodes:

- `error.code`
- `error.message`

It currently ignores `error.details`.

## Part II. Required Prototype Completion Spec

Start here if you are continuing iOS development.

Everything below defines what still must be implemented for the prototype iPhone app to be considered complete.

### Required Shared Backend Contract

The finished prototype iPhone app must support the shared contract defined in `prototype_architechture/api.md`.

#### Device-Auth Endpoints

- `POST /api/auth/refresh`
  - iPhone request body:
    - `refreshToken: String`
  - Success response:
    - `deviceId: UUID`
    - `role: ADMIN | EDITOR`
    - `deviceType: IOS_APP | WEB_BROWSER`
    - `friendlyName: String`
    - `accessToken: String`
    - `accessTokenExpiresAt: OffsetDateTime`
    - `refreshTokenExpiresAt: OffsetDateTime`

- `POST /api/auth/logout`
  - no request body
  - authenticated request
  - revokes the current device session

- `GET /api/auth/me`
  - no request body
  - authenticated request
  - success response:
    - `authenticated: Boolean`
    - `deviceId: UUID`
    - `role: ADMIN | EDITOR`
    - `deviceType: IOS_APP | WEB_BROWSER`
    - `friendlyName: String`

#### Inventory Endpoints

- `GET /api/items`
  - query parameters:
    - `q`
    - `includeArchived`
    - `page`
    - `size`
    - `sort`
  - response:
    - `items: [ItemResponse]`
    - `page: Int`
    - `size: Int`
    - `totalItems: Long`
    - `totalPages: Int`

- `GET /api/items/{id}`
  - response: `ItemResponse`

- `POST /api/items`
  - request body:
    - `mainInventoryNumber: String`
    - `title: String`
    - `secondaryInventoryNumbers: [String]`
    - `authors: [{ id?: Long, name?: String }]`
    - `initialLocationId: Long`
    - `moveInDate: YYYY-MM-DD`
  - response: `ItemResponse`

- `PUT /api/items/{id}`
  - request body:
    - `mainInventoryNumber: String`
    - `title: String`
    - `secondaryInventoryNumbers: [String]`
    - `authors: [{ id?: Long, name?: String }]`
  - response: `ItemResponse`

- `PATCH /api/items/{id}/planning`
  - request body:
    - `promisedOrganization: { id?: Long, name?: String } | null`
    - `expectedLeaveDate: YYYY-MM-DD | null`
  - response: `ItemResponse`

- `POST /api/items/{id}/archive`
  - no request body
  - admin-only
  - response: `ItemResponse`

- `GET /api/items/conflicts/main-number`
  - query parameter:
    - `mainInventoryNumber`
  - success response:
    - `available: Boolean`
    - `mainInventoryNumber: String`
    - `conflictingItem: { id, title, currentPresenceType, currentLocationName } | null`

#### Lookup Endpoints

- `GET /api/locations`
  - query parameter:
    - `includeArchived`
  - response:
    - array of `{ id, name, archived }`

- `POST /api/locations`
  - admin-only
  - request body:
    - `name: String`
  - response:
    - `{ id, name, archived }`

- `PUT /api/locations/{id}`
  - admin-only
  - request body:
    - `name: String`
  - response:
    - `{ id, name, archived }`

- `POST /api/locations/{id}/archive`
  - admin-only
  - no request body
  - response:
    - `{ id, name, archived }`

- `GET /api/authors`
  - query parameters:
    - `q`
    - `includeArchived`
  - response:
    - array of `{ id, name, archived }`

- `POST /api/authors`
  - request body:
    - `name: String`
  - response:
    - `{ id, name, archived }`

- `GET /api/organizations`
  - query parameters:
    - `q`
    - `includeArchived`
  - response:
    - array of `{ id, name, archived }`

- `POST /api/organizations`
  - request body:
    - `name: String`
  - response:
    - `{ id, name, archived }`

#### Movement And History Endpoints

The architecture requires these endpoints:

- `POST /api/items/{id}/movements`
- `GET /api/items/{id}/history`

The source-of-truth documents currently define:

- movement request examples
- history business rules
- the database shape of `item_history`

The source-of-truth documents do not currently define the exact success response DTOs for these two endpoints.

That missing contract is a real implementation blocker for iOS completion.

### Required Product And Behavior Rules

#### 1. App Bootstrap And Routing

The finished app must:

- load stored local context
- load the refresh token from Keychain
- attempt device-session restoration on launch
- route directly into inventory when the device is still valid
- route back to pairing when the device is revoked or local auth material is unusable

Current code gap:

- root routing is based on `pairedDevice != nil`, not on successful authenticated session restoration

#### 2. Session Requirements

The finished app must:

- keep access token in memory only
- store refresh token in Keychain
- reuse stable `installationId` across re-pairings
- refresh the device session through `POST /api/auth/refresh`
- handle revoked or expired sessions cleanly
- support one active session per registered device as described by the architecture

Current code gaps:

- no refresh flow on launch
- no generic bearer-authenticated API path
- no complete authenticated session manager

#### 3. Persistence Requirements

For the current prototype, the secure persisted authenticator boundary is:

- refresh token
- stable installation identity

Current working persistence boundary:

- access token: memory only
- refresh token: stored in Keychain
- installation identity: stored in Keychain
- paired-device summary (`deviceId`, role, friendly name, server address, refresh expiry): stored in `UserDefaults` as recoverable local cache

Rule:

- do not move recoverable summary metadata into Keychain unless the team explicitly expands the security boundary
- if a newly persisted field can authenticate or re-authenticate the device by itself, store it in Keychain

#### 4. Networking And Date Requirements

The finished app must support two different date families:

- timestamps:
  - pairing expiries
  - completion timestamps
  - token expiries
  - typically ISO 8601 timestamp values
- business dates:
  - `moveInDate`
  - `moveOutDate`
  - `expectedLeaveDate`
  - `expectedReturnDate`
  - explicitly `DATE` values per architecture

Current code gap:

- `ManageItAPIClient` uses `.iso8601` `JSONDecoder` and `JSONEncoder`
- that is not sufficient by itself for the future item/planning/history contract because the architecture uses business `DATE` values, not only timestamps

Requirement:

- add a stable serialization strategy for backend `LocalDate` values
- do not model business dates casually as timestamp-based `Date` values without an explicit codec strategy

#### 5. Inventory List Requirements

The finished app must provide an inventory list that:

- uses `GET /api/items`
- supports the architecture search fields:
  - main inventory number
  - secondary inventory numbers
  - title
  - author name
  - current location name
- relies on backend pagination/sorting/filtering
- hides archived items by default
- only exposes `includeArchived=true` to admin-capable flows

#### 6. Item Detail Requirements

The finished item detail screen must show exactly two sections:

1. `Current / Planned Status`
   - current location or current organization
   - promised organization
   - expected leave date
2. `History`
   - actual internal/external placement records only

Promised planning fields must not appear as timeline history rows by themselves.

#### 7. Item Create And Edit Requirements

The finished app must support:

- create item
- edit item metadata
- update planning fields

Create-item requirements:

- require main inventory number
- require title
- require at least one author
- require initial internal location
- allow optional secondary inventory numbers
- require the initial `moveInDate`

Edit-item requirements:

- allow editing main inventory number
- allow editing title
- allow editing secondary inventory numbers
- allow editing author list

Planning requirements:

- allow promised organization to be cleared or set
- allow promised organization by existing id or explicit new name
- allow `expectedLeaveDate`
- do not create history rows from planning updates alone

Conflict requirement:

- the app must be able to surface duplicate main-number conflicts using the backend error shape and/or `GET /api/items/conflicts/main-number`

#### 8. Author And Organization Requirements

The finished app must:

- show author suggestions from `GET /api/authors`
- show organization suggestions from `GET /api/organizations`
- allow explicit author creation during item flows
- allow explicit organization creation during planning/rental flows
- avoid assuming that typed text already matches an existing author or organization

#### 9. Movement And History Requirements

The finished app must support:

- internal movement
- external rental
- return from external organization
- per-item chronological history display

Movement business rules from the architecture:

- every new event closes the previous open history row
- internal movement uses a `locationId`
- external rental uses an organization target and optional `expectedReturnDate`
- return is modeled as a normal new internal movement event
- `items.current_presence_type`, current location, and current organization must reflect the latest actual movement state

Current blocker:

- the architecture does not yet define the exact iPhone-facing response DTOs for movement create and history list

#### 10. Role Requirements

`EDITOR` must be able to:

- create items
- edit item metadata
- update planning fields
- create authors during item flows
- create organizations during planning/rental flows
- add move/rental/return events

`ADMIN` must be able to do everything `EDITOR` can, plus:

- archive items
- create/edit/archive locations
- use admin-level inventory actions in the LAN client app

Host-only flows must not be implemented in the iPhone app:

- onboarding
- host admin password login
- device approval or rejection
- device revocation
- device role changes
- installation settings

#### 11. Location Management Requirements

Because the architecture gives `ADMIN` location-management powers to approved LAN devices, the finished iPhone app must support admin-only location flows if the prototype is considered feature-complete:

- list locations
- create location
- rename location
- archive location

Archived visibility rules:

- archived locations hidden by default
- admin flows may request archived inclusion

#### 12. Networking Transport Requirements

The prototype architecture explicitly uses plain HTTP for the prototype LAN demo.

Therefore the finished iPhone app must:

- be able to call LAN HTTP backend URLs in prototype mode
- preserve the ability to move to HTTPS later
- avoid baking production-only HTTPS assumptions into the prototype client

The architecture does not define the exact ATS exception policy. That policy still needs an explicit decision.

#### 13. Current Implementation Gaps

These are the most important mismatches today:

1. The app does not restore a session on launch.
2. The app does not open directly into inventory on later launches.
3. The app has no inventory modules yet.
4. The app has no movement/history modules yet.
5. The current network codec does not yet cover business `DATE` values.
6. The current local clear action does not call backend logout.
### Required Implementation Surface

This section translates the architecture into concrete implementation work for the iPhone app.

These are not optional refinements. They are the remaining pieces required for the prototype to match the current plan.

#### 14.1 Required Root App States

The finished iPhone app must support these root runtime states:

1. bootstrap / restore
   - load local persisted context
   - load refresh token
   - decide whether a real authenticated session can be restored
2. unpaired
   - show the pairing feature
3. paired but restoring failed
   - handle revoked/expired/invalid session material cleanly
   - return the user to a recoverable path
4. active authenticated device
   - open into the inventory app branch

This state split is required by the architecture statement that the phone should open directly into inventory on later launches unless revoked.

#### 14.2 Required Feature Modules

The architecture defines these iPhone modules as part of the planned app:

- `Pairing`
- `Session`
- `Inventory`
- `ItemEditor`
- `History`
- `Networking`
- `SecureStorage`
- `SharedUI`
- `Models`

Current implementation status by module:

- `Pairing`: partially implemented
- `Session`: not implemented as a distinct module yet
- `Inventory`: not implemented
- `ItemEditor`: not implemented
- `History`: not implemented
- `Networking`: pairing-only today
- `SecureStorage`: partially implemented
- `SharedUI`: minimally implemented
- `Models`: pairing/session models only

#### 14.3 Required Module Deliverables

##### Pairing Module

Must include:

- QR scan
- manual pairing-link fallback
- waiting state
- activation state
- cancellation/expiry handling

Current status:

- mostly implemented

Remaining work:

- integrate pairing success into the finished session/bootstrap flow instead of a placeholder-only branch
- ensure pairing success transitions into inventory after activation

##### Session Module

Must include:

- refresh-token loading from Keychain
- launch-time session restore
- authenticated device state
- revoked-session handling
- logout
- authenticated session verification when useful

Must integrate with:

- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/me`

This is currently the highest-priority missing module.

##### Inventory Module

Must include:

- inventory list
- search
- item detail

Must integrate with:

- `GET /api/items`
- `GET /api/items/{id}`

Required behavior:

- backend-driven pagination
- backend-driven sorting/filtering
- default archived-hidden behavior
- role-aware archived visibility if admin-only affordances are added

##### ItemEditor Module

Must include:

- create item
- edit item metadata
- planning updates
- duplicate-number handling
- author suggestion/create
- organization suggestion/create
- location selection

Must integrate with:

- `POST /api/items`
- `PUT /api/items/{id}`
- `PATCH /api/items/{id}/planning`
- `GET /api/items/conflicts/main-number`
- `GET /api/authors`
- `POST /api/authors`
- `GET /api/organizations`
- `POST /api/organizations`
- `GET /api/locations`

##### History Module

Must include:

- item movement/rental/return entry flow
- per-item chronological history display

Must integrate with:

- `POST /api/items/{id}/movements`
- `GET /api/items/{id}/history`

Current blocker:

- exact response DTOs for these two endpoints are not defined in the source-of-truth documents yet

##### Admin Device-Capability Surfaces Inside The LAN Client App

Because the architecture gives approved `ADMIN` devices extra powers, the iPhone app must also provide admin-only client actions for:

- archive item
- create location
- rename location
- archive location

Must integrate with:

- `POST /api/items/{id}/archive`
- `POST /api/locations`
- `PUT /api/locations/{id}`
- `POST /api/locations/{id}/archive`

#### 14.4 Required Screens And User Journeys

The finished prototype must include these user journeys.

##### Journey A: First-Time Pairing

Steps:

1. open pairing screen
2. scan or paste pairing link
3. submit pairing scan payload
4. wait for host finalization
5. complete pairing
6. persist session material
7. enter the inventory app branch

##### Journey B: Return Launch For A Valid Device

Steps:

1. app starts
2. local persisted context is loaded
3. refresh token is read from Keychain
4. app calls `POST /api/auth/refresh`
5. if refresh succeeds, the app goes directly into inventory

##### Journey C: Return Launch For A Revoked Or Invalid Device

Steps:

1. app starts
2. restore is attempted
3. backend rejects refresh because the device/session is no longer usable
4. app clears or quarantines unusable session state
5. app returns the user to a recoverable pairing/setup path

##### Journey D: Inventory Browsing

Steps:

1. authenticated device opens inventory list
2. list uses backend paging/search
3. user opens item detail
4. detail shows current/planned state plus actual history section

##### Journey E: Item Creation

Steps:

1. authenticated device opens create-item flow
2. enters metadata
3. selects or creates authors
4. selects initial location
5. adds optional secondary numbers
6. sets initial move-in date
7. submits create request
8. receives resulting item snapshot

##### Journey F: Item Metadata Editing

Steps:

1. authenticated device opens an existing item
2. edits metadata fields
3. edits secondary numbers
4. edits authors
5. handles duplicate-number conflicts when necessary
6. submits update request

##### Journey G: Planning Update

Steps:

1. authenticated device edits planning state
2. selects or creates promised organization
3. sets or clears expected leave date
4. submits planning update
5. receives updated item snapshot

##### Journey H: Movement / Rental / Return

Steps:

1. authenticated device opens movement flow for an item
2. chooses movement type:
   - internal move
   - external rental
   - return to internal location
3. enters date and target data
4. submits movement request
5. sees updated current state and history

##### Journey I: Admin-Only Archive And Location Management

Admin devices only:

- archive item
- create location
- rename location
- archive location

#### 14.5 Required Screen Inventory

The architecture does not define the exact navigation shell, but the finished prototype still requires at least the following screen responsibilities:

- pairing screen
- pairing waiting/activation screen
- inventory list screen
- item detail screen
- item create screen
- item edit screen
- planning edit screen
- movement/rental/return entry screen
- item history screen or detail-history section
- admin location list/management screen or equivalent admin affordances in the client UI

Because the shell pattern is not specified, the exact navigation structure still requires a decision.

#### 14.6 Required Local Client Models To Add

Beyond the currently implemented pairing/session models, the iPhone app still needs local DTOs or view-model shapes for:

- device refresh request
- device refresh response
- device session status response
- item list response
- item response
- item author summary
- item placement summary
- item planning summary
- item create request
- item update request
- item planning update request
- item main-number conflict response
- location response
- location create request
- location update request
- author response
- author create request
- organization response
- organization create request
- movement request model
- history response model

The last two remain blocked by missing source-of-truth DTO definitions.

#### 14.7 Required Networking Capabilities To Add

The final app needs two networking layers:

1. public device-bootstrap API support
   - pairing scan
   - pairing status
   - pairing completion
   - session refresh before an access token exists
2. authenticated device API support
   - bearer-authenticated requests
   - logout
   - me
   - inventory endpoints
   - lookup endpoints
   - admin LAN-device endpoints

The authenticated layer must handle:

- bearer token attachment
- 401 recovery strategy
- refresh retry path
- session-invalid fallback path
- backend error decoding
- date encoding/decoding for both timestamps and business dates

#### 14.8 Required Role Gating In The iPhone UI

The UI must respect these backend security boundaries:

- `EDITOR`
  - can create items
  - can edit item metadata
  - can update planning fields
  - can create authors
  - can create organizations
  - can add movement/rental/return events
- `ADMIN`
  - everything `EDITOR` can do
  - archive item
  - create/edit/archive locations
  - archived-visibility affordances where supported

The host-only flows must not appear in the iPhone app.

#### 14.9 Required Validation And UX Error Handling

The finished app must handle at least these error families cleanly:

- invalid pairing link
- invalid or missing server URL
- expired pairing token
- cancelled pairing
- transport failures
- App Transport Security / HTTP transport failures in prototype mode
- invalid refresh token
- revoked device
- expired session
- duplicate main inventory number
- author not found / archived
- organization not found / archived
- location not found / archived
- role-based forbidden actions
- standard validation errors from malformed or incomplete item requests

Required UX implication:

- the app must distinguish "retry with same state" errors from "this device is no longer usable" errors

#### 14.10 Required Date-Handling Implementation

The iPhone app must implement two distinct serialization paths:

- timestamp codec for token expiries and pairing timestamps
- business-date codec for:
  - `moveInDate`
  - `moveOutDate`
  - `expectedLeaveDate`
  - `expectedReturnDate`

This is mandatory because the architecture explicitly says business dates are `DATE` values, not timestamps.

#### 14.11 Required Persistence Implementation

The finished app must persist and restore:

- stable `installationId`
- refresh token
- enough paired-device context to reconnect to the correct server/device identity

It must also define a clear invalidation policy for:

- revoked refresh credential
- mismatched local server/device context
- user-triggered local reset

#### 14.12 Required Testing And QA Work

To finish the prototype responsibly, the iPhone app still needs:

- automated unit tests for parsing and URL normalization
- automated tests for bootstrap/session-state transitions
- automated tests for date codecs
- automated tests for request/response decoding
- manual QA on Simulator
- manual QA on real iPhone over LAN

Minimum end-to-end QA scenarios:

1. first-time pairing succeeds
2. expired pairing fails cleanly
3. cancelled pairing fails cleanly
4. relaunch restores session and opens inventory
5. revoked device falls back cleanly
6. inventory list and detail load
7. item create works
8. item edit works
9. planning update works
10. role-gated admin actions are hidden or blocked for editors

#### 14.13 Definition Of Done For A Prototype-Complete iPhone App

The iPhone app is not complete until all of the following are true:

- pairing works end-to-end
- relaunch restores the authenticated device session
- the app opens directly into inventory on later launches unless revoked
- inventory list and detail are implemented
- item create/edit/planning flows are implemented
- movement/history flows are implemented
- role boundaries are honored
- admin LAN-device actions required by the architecture are implemented
- the app can operate against the prototype LAN backend using the intended transport setup
- unresolved source-of-truth gaps have been decided and documented

#### 14.14 Required Implementation-Surface Specification For Unfinished Modules

Format for sections 14.15 to 14.19:

- `Type` or `Class` or `Struct` or `Enum`: what must exist
- `Fields`: stored data with types
- `Functions`: callable surface
- `Accepts`: input parameters
- `Returns`: return value
- `Does`: exact responsibility
- `Why`: reason the type exists
- `Throws`: error surface when relevant
- `Blocked`: cannot be finalized until source-of-truth is clarified

Label mapping used below:

- `Expects` = `Accepts`
- `Responsibility` = `Does`
- `Purpose` = `Why`

Rule:

- where the source-of-truth architecture already defines a backend contract, this section binds the iPhone implementation to that contract
- where the source-of-truth architecture does not define a contract, this section does not invent one
- unresolved backend DTOs remain explicitly blocked in Part III

Reading rule for Part II:

- `14.15` covers files that already exist in the repo today and must be expanded
- `14.16` and `14.18` describe planned files and types that do not exist in the repo today unless Part I already documents them as existing
- whenever a heading starts with `Planned file:`, read it as a file to create later, not as a file that already exists now

#### 14.15 Existing Files That Must Be Expanded

Files to expand:

- these files already exist in the repo today

##### `ios_front/ManageIt/ManageIt/AppModel.swift`

Type: `AppModel`

- Kind: `final class`
- Why: root app state and root routing

Fields to add:

- `appPhase: AppPhase`
  - current root routing phase
- `sessionModel: DeviceSessionModel`
  - owns authenticated-session restore, refresh, and logout behavior
- `inventoryModel: InventoryFeatureModel?`
  - root inventory state once the device becomes active
- `restoreTask: Task<Void, Never>?`
  - launch-time bootstrap task

Functions to add:

- `restoreSessionOnLaunch()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - load persisted device context
    - load the refresh token from Keychain
    - decide whether restore is possible
    - call the refresh endpoint when possible
    - move the root app phase to active inventory or recoverable fallback

- `activatePairedDevice(response:serverAddress:)`
  - Expects:
    - `response: MobilePairingCompleteResponse`
    - `serverAddress: String`
  - Returns: `Void`
  - Throws:
    - secure-storage failures
  - Responsibility:
    - persist the new device session material
    - create active in-memory session state
    - create the inventory root model
    - transition to the authenticated app branch

- `applyRefreshedSession(_:)`
  - Expects: `response: DeviceTokenRefreshResponse`
  - Returns: `Void`
  - Responsibility:
    - update the active access token
    - update token expiry
    - update locally cached friendly-name and role if changed
    - create or refresh the inventory root model

- `handleSessionInvalidation(clearLocalPairing:)`
  - Expects: `clearLocalPairing: Bool`
  - Returns: `Void`
  - Responsibility:
    - drop the active access token
    - optionally clear persisted pairing/session material
    - route to the correct recovery branch

- `logoutCurrentDevice()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility:
    - call backend logout when an authenticated session exists
    - clear local secure and non-secure state
    - return the app to the pairing branch

Types to add:

- `AppPhase`
  - Kind: `enum`
  - Cases:
    - `bootstrapping`
    - `pairing`
    - `restoring`
    - `active`
    - `sessionRecovery`
  - Purpose: drive root routing without relying only on `pairedDevice != nil`

##### `ios_front/ManageIt/ManageIt/ContentView.swift`

Type: `ContentView`

Does:

- show a bootstrap/loading branch while launch restore is in progress
- show the pairing branch when the device is not usable
- show a recoverable session-failure branch when local material exists but restore fails
- show the authenticated inventory branch after successful restore or pairing

Views to add:

- `BootstrapView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: launch-time loading state

- `SessionRecoveryView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: explain that the device can no longer continue directly and offer recovery actions

- `AuthenticatedRootView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: host the finished authenticated app shell as a tab bar root

Authenticated shell rule:

- use a tab bar root for the finished authenticated app
- Inventory is the primary tab
- item detail, item edit, planning, movement, and history stay in the Inventory navigation stack rather than becoming separate top-level tabs
- admin-only location management may appear as a separate tab only for `ADMIN` devices
- a device/session tab may expose logout, pairing summary, and future session diagnostics

Functions to add:

- `body -> some View`
  - must route from `appModel.appPhase`, not from `pairedDevice` alone

- `recoveryActionButtons -> some View`
  - Expects: access to recovery/logout/reset callbacks
  - Returns: action row for session-recovery branch

##### `ios_front/ManageIt/ManageIt/Storage/KeychainStore.swift`

Type: `KeychainStore`

- Why: secure session and device-material storage

Functions to add:

- `loadRefreshToken() -> String?`
  - Expects: no arguments
  - Returns:
    - stored refresh token when present
    - `nil` when absent
  - Throws:
    - `KeychainStoreError.operationFailed`

- `clearAuthenticatedMaterial()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - clear refresh token
    - clear any future persisted authenticator values if the security boundary expands later

##### `ios_front/ManageIt/ManageIt/Storage/AppPreferences.swift`

Type: `AppPreferences`

- Why: non-secure cached local UI state

Functions to add:

- `clearAllLocalContext()`
  - Expects: no arguments
  - Returns: `Void`
  - Responsibility:
    - clear persisted device context
    - clear remembered server address

- `saveLastInventoryQuery(_:)`
  - Expects: `query: String`
  - Returns: `Void`
  - Responsibility: optional UX caching for the inventory screen

- `loadLastInventoryQuery() -> String`
  - Expects: no arguments
  - Returns: last remembered query or empty string

Current rule:

- paired-device summary and remembered server address may remain here because they are recoverable cache values, not persisted authenticators

#### 14.16 Required New Model Files, Types, And Function Contracts

New files and types:

- every `Planned file:` heading below is a file that does not exist in the repo today

##### Planned file: `ios_front/ManageIt/ManageIt/Models/AuthModels.swift`

Types:

- `DeviceTokenRefreshRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`
  - Stored members:
    - `refreshToken: String`

- `DeviceTokenRefreshResponse`
  - Kind: `struct`
  - Conforms to: `Decodable`, `Equatable`
  - Stored members:
    - `deviceId: UUID`
    - `role: DeviceRole`
    - `deviceType: DeviceType`
    - `friendlyName: String`
    - `accessToken: String`
    - `accessTokenExpiresAt: Date`
    - `refreshTokenExpiresAt: Date`

- `DeviceSessionStatusResponse`
  - Kind: `struct`
  - Conforms to: `Decodable`, `Equatable`
  - Stored members:
    - `authenticated: Bool`
    - `deviceId: UUID`
    - `role: DeviceRole`
    - `deviceType: DeviceType`
    - `friendlyName: String`

- `SessionRecoveryReason`
  - Kind: `enum`
  - Conforms to: `Equatable`
  - Cases:
    - `missingRefreshToken`
    - `revokedDevice`
    - `expiredSession`
    - `serverUnreachable`
    - `corruptLocalState`
  - Purpose: root and session layers need a stable local reason vocabulary for recovery UI

##### Planned file: `ios_front/ManageIt/ManageIt/Models/BusinessDate.swift`

Type:

- `BusinessDate`
  - Kind: `struct`
  - Conforms to: `Hashable`, `Comparable`, `Codable`
  - Purpose: represent day-precision backend `DATE` values without time-zone semantics

Fields:

- `encodedString: String`
  - format: `YYYY-MM-DD`

Functions:

- `init(encodedString:)`
  - Expects: `encodedString: String`
  - Returns: initialized `BusinessDate`
  - Throws:
    - validation error when the string is not a valid backend `DATE`

- `init(dateComponents:)`
  - Expects: `dateComponents: DateComponents`
  - Returns: initialized `BusinessDate`
  - Throws:
    - validation error when the components do not describe a valid calendar day

- `dateComponents(calendar:) -> DateComponents`
  - Expects: `calendar: Calendar = .current`
  - Returns: day-precision `DateComponents`

- `formattedForDisplay(locale:) -> String`
  - Expects: `locale: Locale = .current`
  - Returns: user-facing day string for display only

Rule:

- do not use timestamp `Date` values as the semantic storage type for business dates

##### Planned file: `ios_front/ManageIt/ManageIt/Models/InventoryModels.swift`

Types:

- `ItemPresenceType`
  - Kind: `enum`
  - Raw type: `String`
  - Conforms to: `Codable`, `Equatable`
  - Cases:
    - `internal = "INTERNAL"`
    - `external = "EXTERNAL"`

- `ItemAuthorSummary`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `name: String`

- `ItemLocationSummary`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `name: String`

- `ItemOrganizationSummary`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `name: String`

- `ItemPlacement`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `presenceType: ItemPresenceType`
    - `location: ItemLocationSummary?`
    - `organization: ItemOrganizationSummary?`

- `ItemPlanning`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `promisedOrganization: ItemOrganizationSummary?`
    - `expectedLeaveDate: BusinessDate?`

- `ItemResponse`
  - Kind: `struct`
  - Conforms to: `Decodable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `mainInventoryNumber: String`
    - `title: String`
    - `secondaryInventoryNumbers: [String]`
    - `authors: [ItemAuthorSummary]`
    - `currentPlacement: ItemPlacement`
    - `planning: ItemPlanning`
    - `archived: Bool`

- `ItemListResponse`
  - Kind: `struct`
  - Conforms to: `Decodable`, `Equatable`
  - Stored members:
    - `items: [ItemResponse]`
    - `page: Int`
    - `size: Int`
    - `totalItems: Int64`
    - `totalPages: Int`

- `ItemAuthorInput`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `id: Int64?`
    - `name: String?`

- `ItemCreateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `mainInventoryNumber: String`
    - `title: String`
    - `secondaryInventoryNumbers: [String]`
    - `authors: [ItemAuthorInput]`
    - `initialLocationId: Int64`
    - `moveInDate: BusinessDate`

- `ItemUpdateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `mainInventoryNumber: String`
    - `title: String`
    - `secondaryInventoryNumbers: [String]`
    - `authors: [ItemAuthorInput]`

- `ItemPlanningOrganizationInput`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `id: Int64?`
    - `name: String?`

- `ItemPlanningUpdateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `promisedOrganization: ItemPlanningOrganizationInput?`
    - `expectedLeaveDate: BusinessDate?`

- `ItemMainNumberConflictResponse`
  - Kind: `struct`
  - Conforms to: `Decodable`, `Equatable`
  - Stored members:
    - `available: Bool`
    - `mainInventoryNumber: String`
    - `conflictingItem: ConflictingItem?`

- `ConflictingItem`
  - Kind: `struct`
  - Conforms to: `Decodable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `title: String`
    - `currentPresenceType: ItemPresenceType`
    - `currentLocationName: String?`

Computed:

- `ItemPlacement.displayTargetName -> String`
  - Returns:
    - location name for internal placement
    - organization name for external placement

- `ItemResponse.authorNames -> String`
  - Returns: comma-separated author list for compact UI display

##### Planned file: `ios_front/ManageIt/ManageIt/Models/LookupModels.swift`

Types:

- `LocationResponse`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `name: String`
    - `archived: Bool`

- `LocationCreateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `name: String`

- `LocationUpdateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `name: String`

- `AuthorResponse`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `name: String`
    - `archived: Bool`

- `AuthorCreateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `name: String`

- `OrganizationResponse`
  - Kind: `struct`
  - Conforms to: `Codable`, `Equatable`
  - Stored members:
    - `id: Int64`
    - `name: String`
    - `archived: Bool`

- `OrganizationCreateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `name: String`

##### Planned file: `ios_front/ManageIt/ManageIt/Models/HistoryModels.swift`

Types:

- `ItemMovementCreateRequest`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `presenceType: ItemPresenceType`
    - `locationId: Int64?`
    - `organization: MovementOrganizationInput?`
    - `moveInDate: BusinessDate`
    - `expectedReturnDate: BusinessDate?`

- `MovementOrganizationInput`
  - Kind: `struct`
  - Conforms to: `Encodable`, `Equatable`
  - Stored members:
    - `id: Int64?`
    - `name: String?`

Local types:

- `MovementEntryMode`
  - Kind: `enum`
  - Conforms to: `Equatable`
  - Cases:
    - `internalMove`
    - `externalRental`
    - `returnToInternal`

Blocked:

- final success model for `POST /api/items/{id}/movements`
- final response model for `GET /api/items/{id}/history`

These cannot be fully specified until Part III is answered.

#### 14.17 Required API-Client Surface

Type: `ManageItAPIClient`

- Why: full public and authenticated backend client
- Does: pairing, refresh, logout, me, inventory, lookups, admin location actions, movement, history

##### Public Bootstrap And Session Functions

- `refreshDeviceSession(serverURL:request:) -> DeviceTokenRefreshResponse`
  - Expects:
    - `serverURL: URL`
    - `request: DeviceTokenRefreshRequest`
  - Returns: decoded refresh response
  - Responsibility: call `POST /api/auth/refresh`

- `fetchCurrentSession(serverURL:accessToken:) -> DeviceSessionStatusResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
  - Returns: decoded current-session status
  - Responsibility: call `GET /api/auth/me`

- `logoutCurrentSession(serverURL:accessToken:)`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
  - Returns: `Void`
  - Responsibility: call `POST /api/auth/logout`

##### Inventory Functions

- `fetchItems(serverURL:accessToken:query:) -> ItemListResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `query: InventoryListQuery`
  - Returns: paged item list

- `fetchItem(serverURL:accessToken:itemID:) -> ItemResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `itemID: Int64`
  - Returns: one item snapshot

- `createItem(serverURL:accessToken:request:) -> ItemResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `request: ItemCreateRequest`
  - Returns: created item snapshot

- `updateItem(serverURL:accessToken:itemID:request:) -> ItemResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `itemID: Int64`
    - `request: ItemUpdateRequest`
  - Returns: updated item snapshot

- `updateItemPlanning(serverURL:accessToken:itemID:request:) -> ItemResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `itemID: Int64`
    - `request: ItemPlanningUpdateRequest`
  - Returns: updated item snapshot

- `archiveItem(serverURL:accessToken:itemID:) -> ItemResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `itemID: Int64`
  - Returns: archived item snapshot

- `checkMainInventoryNumberConflict(serverURL:accessToken:mainInventoryNumber:) -> ItemMainNumberConflictResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `mainInventoryNumber: String`
  - Returns: conflict-helper response

##### Lookup Functions

- `fetchLocations(serverURL:accessToken:includeArchived:) -> [LocationResponse]`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `includeArchived: Bool`
  - Returns: decoded array of locations

- `createLocation(serverURL:accessToken:request:) -> LocationResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `request: LocationCreateRequest`
  - Returns: created location

- `updateLocation(serverURL:accessToken:locationID:request:) -> LocationResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `locationID: Int64`
    - `request: LocationUpdateRequest`
  - Returns: updated location

- `archiveLocation(serverURL:accessToken:locationID:) -> LocationResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `locationID: Int64`
  - Returns: archived location

- `fetchAuthors(serverURL:accessToken:query:includeArchived:) -> [AuthorResponse]`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `query: String`
    - `includeArchived: Bool`
  - Returns: decoded author suggestions

- `createAuthor(serverURL:accessToken:request:) -> AuthorResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `request: AuthorCreateRequest`
  - Returns: created author

- `fetchOrganizations(serverURL:accessToken:query:includeArchived:) -> [OrganizationResponse]`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `query: String`
    - `includeArchived: Bool`
  - Returns: decoded organization suggestions

- `createOrganization(serverURL:accessToken:request:) -> OrganizationResponse`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `request: OrganizationCreateRequest`
  - Returns: created organization

##### Movement And History Functions

- `createMovement(serverURL:accessToken:itemID:request:)`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `itemID: Int64`
    - `request: ItemMovementCreateRequest`
  - Returns:
    - the exact return type is blocked by the unresolved success DTO for `POST /api/items/{id}/movements`

- `fetchItemHistory(serverURL:accessToken:itemID:)`
  - Expects:
    - `serverURL: URL`
    - `accessToken: String`
    - `itemID: Int64`
  - Returns:
    - the exact return type is blocked by the unresolved success DTO for `GET /api/items/{id}/history`

##### Helper Functions

- `sendAuthenticatedRequest(serverURL:path:method:accessToken:body:) -> Response`
  - Visibility: private generic helper
  - Expects:
    - `serverURL: URL`
    - `path: String`
    - `method: String`
    - `accessToken: String`
    - `body: Body?`
  - Returns: decoded `Response`
  - Responsibility:
    - attach bearer token
    - preserve current error-envelope decoding
    - decode success bodies

- `sendAuthenticatedRequestWithoutResponseBody(serverURL:path:method:accessToken:body:)`
  - Visibility: private helper
  - Expects:
    - same authenticated request inputs
  - Returns: `Void`
  - Responsibility:
    - support endpoints that may return empty success bodies

- `makeTimestampDecoder() -> JSONDecoder`
  - Visibility: private static or helper
  - Expects: no arguments
  - Returns: decoder for ISO 8601 timestamp values

- `makeEncoder() -> JSONEncoder`
  - Visibility: private static or helper
  - Expects: no arguments
  - Returns: encoder that preserves business-date string encoding

- `encodeQueryItems(from:) -> [URLQueryItem]`
  - Visibility: private helper
  - Expects: query input value type
  - Returns: query items for list and lookup endpoints

Helper type:

- `InventoryListQuery`
  - Kind: `struct`
  - Conforms to: `Equatable`
  - Stored members:
    - `searchText: String`
    - `includeArchived: Bool`
    - `page: Int`
    - `size: Int`
    - `sort: String?`

#### 14.18 Required Feature Files, Types, And Function Contracts

- every `Planned file:` heading below is a file that does not exist in the repo today

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Session/DeviceSessionModel.swift`

Type:

- `DeviceSessionModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: restore, refresh, validate, and revoke the authenticated device session

Fields:

- `activeSession: ActiveDeviceSession?`
- `recoveryReason: SessionRecoveryReason?`
- `isRestoring: Bool`
- `isRefreshing: Bool`
- `apiClient: ManageItAPIClient`
- `keychainStore: KeychainStore`

Functions:

- `restore(storedContext:) -> ActiveDeviceSession`
  - Expects: `storedContext: StoredDeviceContext`
  - Returns: restored active session
  - Throws:
    - `ManageItError`
    - secure-storage failures
  - Responsibility:
    - load refresh token
    - call refresh endpoint
    - create `ActiveDeviceSession`
    - set recovery reason on failure

- `ensureValidAccessToken(storedContext:) -> String`
  - Expects: `storedContext: StoredDeviceContext`
  - Returns: currently valid access token
  - Throws:
    - when refresh cannot recover the session

- `refresh(storedContext:) -> ActiveDeviceSession`
  - Expects: `storedContext: StoredDeviceContext`
  - Returns: refreshed session
  - Throws:
    - networking or revocation failures

- `fetchCurrentDeviceStatus(storedContext:) -> DeviceSessionStatusResponse`
  - Expects: `storedContext: StoredDeviceContext`
  - Returns: backend current-session view
  - Throws:
    - networking or authorization failures

- `logout(storedContext:)`
  - Expects: `storedContext: StoredDeviceContext`
  - Returns: `Void`
  - Responsibility:
    - call backend logout when possible
    - clear active session state

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Inventory/InventoryFeature.swift`

Types:

- `InventoryFeatureView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: inventory list UI for authenticated devices

- `InventoryItemRow`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: compact item row

Functions:

- `body -> some View`
  - Expects: `store: InventoryFeatureModel`
  - Returns: inventory list screen

- `searchBar -> some View`
  - Expects: current search binding
  - Returns: query-entry control

- `resultsList -> some View`
  - Expects: current items and loading state
  - Returns: scrolling result list

- `emptyState -> some View`
  - Expects: no-result state
  - Returns: empty-state UI

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Inventory/InventoryFeatureModel.swift`

Type:

- `InventoryFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: inventory list search, paging, and root item actions

Fields:

- `items: [ItemResponse]`
- `query: InventoryListQuery`
- `isLoading: Bool`
- `isLoadingNextPage: Bool`
- `errorMessage: String?`
- `hasLoadedOnce: Bool`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Functions:

- `loadFirstPage()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility:
    - request page 0 using current query
    - replace the current item list

- `reload()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility: rerun the current list query

- `loadNextPageIfNeeded(currentItemID:)`
  - Expects: `currentItemID: Int64`
  - Returns: `Void` asynchronously
  - Responsibility:
    - detect near-end scrolling
    - fetch the next page only when more data exists

- `updateSearchText(_:)`
  - Expects: `value: String`
  - Returns: `Void`
  - Responsibility:
    - update query state
    - reset pagination
    - optionally debounce reload

- `setIncludeArchived(_:)`
  - Expects: `includeArchived: Bool`
  - Returns: `Void`
  - Responsibility:
    - only allow `true` for admin-capable UI flows

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Inventory/ItemDetailFeature.swift`

Types:

- `ItemDetailView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: item detail screen

Sections:

- current and planned status
- metadata summary
- history preview or history link/surface
- editor/admin actions appropriate to the current device role

Functions:

- `body -> some View`
  - Expects: `store: ItemDetailFeatureModel`
  - Returns: full detail screen

- `statusSection -> some View`
  - Expects: current item snapshot
  - Returns: current/planned status UI

- `metadataSection -> some View`
  - Expects: current item snapshot
  - Returns: item metadata UI

- `actionSection -> some View`
  - Expects: current role and available actions
  - Returns: edit/archive/move/history entry points

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Inventory/ItemDetailFeatureModel.swift`

Type:

- `ItemDetailFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: load one item, expose action availability, and coordinate detail-level refresh

Fields:

- `itemID: Int64`
- `item: ItemResponse?`
- `isLoading: Bool`
- `errorMessage: String?`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Functions:

- `load()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility: fetch the item snapshot from the backend

- `reload()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility: reload current item state after any edit, planning, movement, or archive action

- `archiveItem() -> ItemResponse`
  - Expects: no arguments
  - Returns: archived item snapshot
  - Throws:
    - backend authorization or validation failures

##### Planned file: `ios_front/ManageIt/ManageIt/Features/ItemEditor/ItemEditorFeature.swift`

Types:

- `ItemEditorView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: create and edit item metadata

- `AuthorChipRow`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: render selected authors

Functions:

- `body -> some View`
  - Expects: `store: ItemEditorFeatureModel`
  - Returns: create/edit form

- `mainFieldsSection -> some View`
  - Expects: current draft fields
  - Returns: title and inventory number controls

- `authorsSection -> some View`
  - Expects: selected authors and suggestion state
  - Returns: author selector/create UI

- `locationAndDateSection -> some View`
  - Expects: initial-location and move-in-date state in create mode
  - Returns: create-only location/date controls

##### Planned file: `ios_front/ManageIt/ManageIt/Features/ItemEditor/ItemEditorFeatureModel.swift`

Type:

- `ItemEditorFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: manage create/edit item drafts and submit create/update requests

Fields:

- `mode: EditorMode`
- `mainInventoryNumber: String`
- `title: String`
- `secondaryInventoryNumbers: [String]`
- `selectedAuthors: [AuthorResponse]`
- `authorQuery: String`
- `authorSuggestions: [AuthorResponse]`
- `initialLocationID: Int64?`
- `availableLocations: [LocationResponse]`
- `moveInDate: BusinessDate?`
- `isSaving: Bool`
- `validationMessage: String?`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Types:

- `EditorMode`
  - Kind: `enum`
  - Cases:
    - `create`
    - `edit(itemID: Int64, original: ItemResponse)`

Functions:

- `loadCreateDependencies()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility: load locations and any other create-time lookup data

- `hydrateForEdit(from:)`
  - Expects: `item: ItemResponse`
  - Returns: `Void`
  - Responsibility: map an item snapshot into editable local state

- `searchAuthors(query:)`
  - Expects: `query: String`
  - Returns: `Void` asynchronously
  - Responsibility: call `GET /api/authors`

- `createAuthor(name:) -> AuthorResponse`
  - Expects: `name: String`
  - Returns: created author
  - Throws:
    - backend validation failures

- `checkMainNumberConflict() -> ItemMainNumberConflictResponse?`
  - Expects: no arguments
  - Returns:
    - conflict helper result when the field is non-empty
    - `nil` when the check should be skipped

- `buildCreateRequest() -> ItemCreateRequest`
  - Expects: current draft state
  - Returns: validated create request
  - Throws:
    - validation error when required fields are missing

- `buildUpdateRequest() -> ItemUpdateRequest`
  - Expects: current draft state
  - Returns: validated update request
  - Throws:
    - validation error when required fields are missing

- `submit() -> ItemResponse`
  - Expects: no arguments
  - Returns: created or updated item snapshot
  - Throws:
    - validation, networking, or backend failures

##### Planned file: `ios_front/ManageIt/ManageIt/Features/ItemEditor/PlanningEditorFeature.swift`

Type:

- `PlanningEditorView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: planning-only edit surface

Functions:

- `body -> some View`
  - Expects: `store: PlanningEditorFeatureModel`
  - Returns: planning form

- `organizationSection -> some View`
  - Expects: organization suggestions and selected value
  - Returns: promised-organization selector/create UI

- `dateSection -> some View`
  - Expects: expected-leave-date state
  - Returns: business-date editing UI

##### Planned file: `ios_front/ManageIt/ManageIt/Features/ItemEditor/PlanningEditorFeatureModel.swift`

Type:

- `PlanningEditorFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: manage planning draft state and submit planning updates

Fields:

- `itemID: Int64`
- `selectedOrganization: OrganizationResponse?`
- `organizationQuery: String`
- `organizationSuggestions: [OrganizationResponse]`
- `expectedLeaveDate: BusinessDate?`
- `isSaving: Bool`
- `validationMessage: String?`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Functions:

- `hydrate(from:)`
  - Expects: `item: ItemResponse`
  - Returns: `Void`
  - Responsibility: map existing planning state into editable local values

- `searchOrganizations(query:)`
  - Expects: `query: String`
  - Returns: `Void` asynchronously
  - Responsibility: call `GET /api/organizations`

- `createOrganization(name:) -> OrganizationResponse`
  - Expects: `name: String`
  - Returns: created organization
  - Throws:
    - backend validation failures

- `buildRequest() -> ItemPlanningUpdateRequest`
  - Expects: current local planning state
  - Returns: validated planning request
  - Throws:
    - validation error when the combination is invalid

- `submit() -> ItemResponse`
  - Expects: no arguments
  - Returns: updated item snapshot
  - Throws:
    - networking or backend failures

##### Planned file: `ios_front/ManageIt/ManageIt/Features/History/MovementFeature.swift`

Type:

- `MovementEntryView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: create internal move, external rental, or return-to-internal events

Functions:

- `body -> some View`
  - Expects: `store: MovementFeatureModel`
  - Returns: movement-entry form

- `modePickerSection -> some View`
  - Expects: selected movement mode
  - Returns: mode-selection controls

- `targetSection -> some View`
  - Expects: location or organization target state
  - Returns: target-selection UI for the chosen mode

- `dateSection -> some View`
  - Expects: movement date and optional expected-return date
  - Returns: business-date editing controls

##### Planned file: `ios_front/ManageIt/ManageIt/Features/History/MovementFeatureModel.swift`

Type:

- `MovementFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: manage the movement/rental/return form and submit movement requests

Fields:

- `itemID: Int64`
- `mode: MovementEntryMode`
- `selectedLocationID: Int64?`
- `availableLocations: [LocationResponse]`
- `selectedOrganization: OrganizationResponse?`
- `organizationQuery: String`
- `organizationSuggestions: [OrganizationResponse]`
- `moveInDate: BusinessDate?`
- `expectedReturnDate: BusinessDate?`
- `isSaving: Bool`
- `validationMessage: String?`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Functions:

- `loadDependencies()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility:
    - load locations
    - preload any needed suggestions or defaults

- `searchOrganizations(query:)`
  - Expects: `query: String`
  - Returns: `Void` asynchronously
  - Responsibility: call `GET /api/organizations`

- `createOrganization(name:) -> OrganizationResponse`
  - Expects: `name: String`
  - Returns: created organization
  - Throws:
    - backend validation failures

- `buildRequest() -> ItemMovementCreateRequest`
  - Expects: current local movement draft
  - Returns: validated movement request
  - Throws:
    - validation error when target and mode do not align

- `submit()`
  - Expects: no arguments
  - Returns:
    - the return contract is blocked by the unresolved movement success DTO
  - Responsibility:
    - submit the movement event
    - make the caller reload item detail and history state after success

##### Planned file: `ios_front/ManageIt/ManageIt/Features/History/ItemHistoryFeature.swift`

Type:

- `ItemHistoryView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: chronological actual-history surface for one item

Functions:

- `body -> some View`
  - Expects: `store: ItemHistoryFeatureModel`
  - Returns: history list UI

- `historyRow(_:) -> some View`
  - Expects: one future history-entry view model
  - Returns: one chronological row

##### Planned file: `ios_front/ManageIt/ManageIt/Features/History/ItemHistoryFeatureModel.swift`

Type:

- `ItemHistoryFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: load and expose chronological item history

Fields:

- `itemID: Int64`
- `isLoading: Bool`
- `errorMessage: String?`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Blocked:

- the final `entries` array element type depends on the unresolved history response DTO

Functions:

- `load()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility:
    - call history endpoint
    - decode and publish chronological entry rows once the final DTO is defined

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Inventory/LocationManagementFeature.swift`

Type:

- `LocationManagementView`
  - Kind: `struct`
  - Conforms to: `View`
  - Purpose: admin-only location-management surface

Functions:

- `body -> some View`
  - Expects: `store: LocationManagementFeatureModel`
  - Returns: location-management UI

- `locationList -> some View`
  - Expects: current locations
  - Returns: list of locations with rename/archive actions

- `createLocationSection -> some View`
  - Expects: draft name and create action
  - Returns: location-create UI

##### Planned file: `ios_front/ManageIt/ManageIt/Features/Inventory/LocationManagementFeatureModel.swift`

Type:

- `LocationManagementFeatureModel`
  - Kind: `final class`
  - Annotations: `@MainActor`, `@Observable`
  - Purpose: admin-only location CRUD orchestration

Fields:

- `locations: [LocationResponse]`
- `includeArchived: Bool`
- `draftLocationName: String`
- `editingLocationID: Int64?`
- `editingName: String`
- `isLoading: Bool`
- `errorMessage: String?`
- `storedContext: StoredDeviceContext`
- `sessionModel: DeviceSessionModel`
- `apiClient: ManageItAPIClient`

Functions:

- `load()`
  - Expects: no arguments
  - Returns: `Void` asynchronously
  - Responsibility: fetch location list

- `createLocation() -> LocationResponse`
  - Expects: no arguments; uses `draftLocationName`
  - Returns: created location
  - Throws:
    - validation or backend failures

- `renameLocation(locationID:) -> LocationResponse`
  - Expects: `locationID: Int64`
  - Returns: updated location
  - Throws:
    - validation or backend failures

- `archiveLocation(locationID:) -> LocationResponse`
  - Expects: `locationID: Int64`
  - Returns: archived location
  - Throws:
    - backend failures

#### 14.19 Required Implementation Sequence

Build order:

1. finish session bootstrap
   - expand `AppModel`
   - add `DeviceSessionModel`
   - add auth DTOs
   - add refresh/logout/me API support
2. finish inventory browsing
   - add inventory models
   - add list and detail feature models/views
3. finish item create and edit
   - add business-date type
   - add item editor models/views
   - add author and location lookups
4. finish planning updates
   - add planning editor models/views
   - add organization lookup/create
5. finish admin item and location actions
   - add archive-item support
   - add location-management support
6. finish movement and history
   - add movement request models and UI
   - add history UI once the final response DTO is defined
7. finish testing and QA
   - bootstrap tests
   - codec tests
   - request/response decoding tests
   - real-device LAN QA

Why:

- session bootstrap unlocks every authenticated feature
- inventory detail is the entry point to editing, planning, movement, and history
- movement/history still depends on the unresolved backend DTO decision in Part III

## Part III. Open Decisions And Blockers

The source-of-truth architecture is not yet specific enough in these remaining backend-contract areas to finish the iPhone app without confirmation:

Persistence note for the current prototype:

- Keychain: refresh token and stable `installationId`
- `UserDefaults`: paired-device summary and remembered server address
- memory only: access token

Revisit that boundary only if the threat model changes or the backend introduces a new persisted authenticator.

1. What is the exact success response contract for:
   - `POST /api/items/{id}/movements`
   - `GET /api/items/{id}/history`
Until those are answered, the iPhone app can be advanced substantially, but the final prototype-complete implementation cannot be specified without remaining ambiguity.
