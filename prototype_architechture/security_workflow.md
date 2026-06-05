# Security Workflow Reference Archive

## Purpose

This document captures the JWT security workflow style used in the reference repository:

- [WebSecurityConfig.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/config/WebSecurityConfig.java)
- [JWTFilter.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/components/JWTFilter.java)
- [JWTService.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/services/JWTService.java)
- [MyUserDetailsService.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/services/MyUserDetailsService.java)

To understand the full runtime path, these related files were also inspected:

- [AuthController.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/controllers/AuthController.java)
- [UserService.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/services/UserService.java)
- [UserPrincipal.java](https://github.com/IO1711/consultingServer/blob/main/src/main/java/com/bilolbek/ConsultingWebsite/utilities/UserPrincipal.java)

This is not a copy-paste target.

It is only a secondary reference archive for possible ideas later.

## Source Of Truth For ManageIt

The actual source of truth for this project's security design is our own architecture documentation, especially:

- [auth.md](/Users/bilolbekrayimov/games/ManageIt/prototype_architechture/auth.md)
- [api.md](/Users/bilolbekrayimov/games/ManageIt/prototype_architechture/api.md)
- [backend.md](/Users/bilolbekrayimov/games/ManageIt/prototype_architechture/backend.md)

If this file conflicts with those project docs, the project docs win.

This file should be treated as:

- a reference for Spring Security structure ideas
- a note about JWT filter/provider/service patterns
- a reminder of what may or may not be worth borrowing

This file should not be treated as:

- the implementation plan for ManageIt security
- a direct blueprint for our auth model
- permission to replace the project's planned security design

---

## What The Reference Repository Is Doing

The reference repository implements stateless JWT authentication for normal API requests.

Core behavior:

- a user logs in with email and password
- Spring Security authenticates credentials through `AuthenticationManager`
- if authentication succeeds, a JWT is generated
- the client stores that token
- later requests send `Authorization: Bearer <token>`
- a custom filter reads the token on every request
- the filter extracts the username from the token
- the filter loads fresh user details from the database
- the filter validates the token against those user details
- if valid, the filter places an authenticated object into `SecurityContextHolder`
- route rules then decide whether the request is allowed

Important style characteristics:

- stateless session model
- custom `OncePerRequestFilter`
- `DaoAuthenticationProvider` with custom `UserDetailsService`
- `BCryptPasswordEncoder`
- role-based request matching in `SecurityFilterChain`
- JWT subject contains the username/email

---

## Main Components In The Reference Repository

## 1. `WebSecurityConfig`

Responsibility:

- defines the Spring Security filter chain
- defines which routes are public and which require auth
- defines which routes require admin role
- enables stateless session policy
- registers the custom JWT filter before username/password auth filter
- creates the DAO authentication provider
- exposes `AuthenticationManager`
- configures CORS

Key behaviors:

- disables CSRF
- enables CORS
- permits `/api/v1/auth/**`
- permits `/api/v1/get/**`
- restricts `/api/v1/admin/**` to `ROLE_ADMIN`
- requires authentication for `/api/v1/request/**`
- requires authentication for `/api/v1/getProtected/**`
- sets `SessionCreationPolicy.STATELESS`
- adds `jwtFilter` before `UsernamePasswordAuthenticationFilter`

Security meaning:

- the app does not rely on server-side login sessions for API auth
- every protected request must carry enough auth information in the bearer token
- route authorization is decided after the JWT filter populates the security context

Notes about style:

- the repo also enables `httpBasic()`
- for a JWT-first API, this is usually unnecessary unless intentionally kept for testing/debugging

## 2. `JWTFilter`

Responsibility:

- intercepts every HTTP request once
- extracts bearer token from `Authorization` header
- parses username from token
- loads the current user from database-backed user details service
- validates token
- if valid, sets authentication into `SecurityContextHolder`

Detailed runtime behavior:

1. read `Authorization` header
2. check that it starts with `"Bearer "`
3. strip the prefix and keep the raw token
4. ask `JWTService.extractUsername(token)` for the token subject
5. if username exists and there is not already an authenticated context:
6. load user through `MyUserDetailsService.loadUserByUsername(username)`
7. validate token through `JWTService.validateToken(token, userDetails)`
8. create `UsernamePasswordAuthenticationToken(userDetails, null, authorities)`
9. attach web request details
10. store that authentication in `SecurityContextHolder`
11. continue the filter chain

Important style detail:

- the filter does not trust token contents alone
- it re-loads the user from the database on every protected request
- this means role changes or deleted users can affect later requests without generating a new token

Implementation detail used there:

- instead of constructor-injecting `MyUserDetailsService`, the filter gets it from `ApplicationContext`
- that works, but direct constructor injection is usually cleaner in a new implementation

## 3. `JWTService`

Responsibility:

- owns JWT creation
- owns JWT parsing
- owns claim extraction
- owns token validation
- checks expiration

Key methods:

- `generateToken(String username)`
- `extractUsername(String token)`
- `validateToken(String token, UserDetails userDetails)`
- `isTokenExpired(String token)`

JWT content used there:

- subject: username/email
- issued at
- expiration
- no custom business claims are required for core auth

Expiration used there:

- `8` hours from issue time

Critical implementation detail:

- the reference repo generates a random HMAC key in the constructor on every application startup

Meaning:

- all previously issued tokens become invalid after a server restart
- tokens are not stable across deployments/restarts
- horizontal scaling would break unless all instances shared the same key

This detail is acceptable for a simple demo, but it must not be copied directly into ManageIt.

## 4. `MyUserDetailsService`

Responsibility:

- bridges Spring Security and application user storage
- loads a user entity from the repository
- converts it into a `UserDetails` implementation

Detailed behavior:

1. receives username
2. queries `AppUserRepository.findByEmail(username)`
3. if user does not exist, throws `UsernameNotFoundException`
4. wraps the entity in `UserPrincipal`

Security meaning:

- Spring Security does not authenticate the JPA entity directly
- it authenticates through a `UserDetails` abstraction

## 5. `UserPrincipal`

Responsibility:

- adapts the application user model to Spring Security

Important behavior:

- `getUsername()` returns email
- `getPassword()` returns hashed password from DB
- `getAuthorities()` returns `ROLE_<role>`

Security meaning:

- route matchers like `hasRole("ADMIN")` work because authorities are exposed as `ROLE_ADMIN`

## 6. `UserService.verify(...)`

Responsibility in login flow:

- receives login credentials
- builds `UsernamePasswordAuthenticationToken(email, password)`
- delegates real credential check to `AuthenticationManager`
- if authenticated, generates JWT and returns it to client

Important meaning:

- password verification is not hand-written in the service
- Spring Security handles it through the configured `AuthenticationProvider`

---

## Full Authentication Workflow In The Reference Repository

## A. Registration flow

High-level sequence:

1. client calls auth registration endpoint
2. service creates new user entity
3. password is hashed using `BCryptPasswordEncoder(12)`
4. entity is saved
5. registration success response is returned

Important style detail:

- password hashing happens before save
- plain password is never persisted

Potential cleanup point for future implementation:

- the repo creates a new `BCryptPasswordEncoder(12)` directly inside `UserService`
- a cleaner style is to expose one shared `PasswordEncoder` bean and inject it everywhere

## B. Login flow

High-level sequence:

1. client sends email and password to `/api/v1/auth/login`
2. controller forwards to service
3. service calls `authenticationManager.authenticate(...)`
4. Spring Security uses the configured `DaoAuthenticationProvider`
5. `DaoAuthenticationProvider` calls `MyUserDetailsService.loadUserByUsername(email)`
6. `MyUserDetailsService` loads the user from repository
7. `UserPrincipal` exposes password hash and authorities
8. `DaoAuthenticationProvider` compares submitted password with stored hash using BCrypt
9. if credentials are correct, authentication succeeds
10. service calls `jwtService.generateToken(email)`
11. signed token is returned in response body

Text sequence diagram:

```text
Client
  -> AuthController.login()
  -> UserService.verify()
  -> AuthenticationManager.authenticate()
  -> DaoAuthenticationProvider
  -> MyUserDetailsService.loadUserByUsername()
  -> AppUserRepository.findByEmail()
  -> UserPrincipal
  -> BCrypt password check
  -> JWTService.generateToken()
  -> Client receives token
```

## C. Protected request flow

High-level sequence:

1. client sends `Authorization: Bearer <token>`
2. `JWTFilter` runs before username/password auth filter
3. filter extracts token
4. filter extracts username from token
5. filter loads fresh user details from DB
6. filter validates token username and expiration
7. filter creates authenticated token with authorities
8. filter stores authentication in `SecurityContextHolder`
9. request reaches controller
10. route matcher / method security uses roles from `SecurityContext`

Text sequence diagram:

```text
Client request
  -> JWTFilter
  -> JWTService.extractUsername()
  -> MyUserDetailsService.loadUserByUsername()
  -> AppUserRepository.findByEmail()
  -> JWTService.validateToken()
  -> SecurityContextHolder.setAuthentication(...)
  -> Spring authorization rules
  -> Controller/service logic
```

## D. Authorization flow

After authentication is placed into the security context:

- `hasRole("ADMIN")` checks for `ROLE_ADMIN`
- `.authenticated()` only checks that a valid authenticated object exists
- public routes bypass auth requirement entirely

This means:

- authentication = who the request is
- authorization = what that request is allowed to do

---

## Exact Security Decisions Made By The Reference Repository

## Token format and storage

- bearer token in `Authorization` header
- JWT subject = user email
- signed with HMAC key
- token expiry = 8 hours
- no refresh token flow
- no database-backed token/session tracking
- no server-side token revocation list

## Password handling

- passwords hashed with BCrypt strength `12`
- login compares plain submitted password against stored hash through Spring Security

## Session handling

- stateless
- no persistent server session used for JWT-authenticated endpoints

## User loading

- always reload user by email from repository before accepting request token

## Role handling

- roles converted to Spring format `ROLE_<NAME>`
- route rules use `hasRole("ADMIN")`

---

## Strengths Of This Style

- simple and readable
- uses standard Spring Security authentication flow
- password verification is delegated correctly to `DaoAuthenticationProvider`
- request auth is centralized in a filter
- works well for a small single-backend application
- role-based route protection is easy to understand

---

## Weaknesses And Risks In The Reference Style

## 1. Restart-invalidated tokens

Because JWT secret key is generated at runtime in the constructor:

- restart invalidates every token
- scaled deployments would fail unless key sharing is added

For ManageIt:

- use a stable configured signing key from environment or secure local config
- never generate the signing key randomly per boot for production auth

## 2. No refresh token model

The reference repo uses only access tokens.

For ManageIt architecture this is not enough because our design already says:

- short-lived access token
- refresh token for session continuity
- refresh token revocation support

## 3. No revocation tracking

The reference repo cannot centrally revoke issued JWTs unless waiting for expiration.

For ManageIt:

- device sessions must be revocable
- a revoked device must stop refreshing tokens
- revoking a device should terminate its future access

## 4. Per-user account model does not match our device model

The reference repo authenticates named users by email and password.

ManageIt regular clients are different:

- regular device access is device-based
- mobile and browser approvals create trusted devices
- only host admin UI uses password login

So we should reuse the technical pattern, not the business identity model.

## 5. `httpBasic()` is enabled

For our server:

- only keep it if intentionally needed
- otherwise avoid extra auth mechanisms that do not match the product rules

## 6. Duplicate password encoder creation style

Reference repo:

- encoder bean in security provider
- another encoder instance directly inside service

For ManageIt:

- use one injected `PasswordEncoder` bean everywhere

## 7. Filter pulls service from `ApplicationContext`

That works, but for our implementation:

- prefer constructor injection
- keep dependencies explicit

---

## What May Be Useful As Reference Later

These patterns may still be useful as reference later:

- `SecurityFilterChain` as the single place to define route access rules
- stateless auth for regular client APIs
- custom request filter before `UsernamePasswordAuthenticationFilter`
- `UserDetailsService`-like adapter layer between Spring Security and persistence
- `AuthenticationManager` + `DaoAuthenticationProvider` for password-based admin login
- `PasswordEncoder` bean with BCrypt
- `SecurityContextHolder` population inside a single filter
- route-based role enforcement

---

## Where ManageIt Already Differs

## 1. Split security into two auth modes

ManageIt needs two different security models:

### Host admin UI

- password-based login
- secure session cookie
- host-only endpoints
- onboarding/settings/password/device approval operations

### Regular approved devices

- access token + refresh token
- device-based identity
- database-backed refresh sessions
- revocable sessions

The reference repo only has one JWT flow. Our planned ManageIt implementation is already different and must stay split.

## 2. Use device identity for normal clients

Instead of:

- subject = user email

We need something like:

- subject = device id or session id
- claims = device role, device type, maybe token version/session id

## 3. Support refresh flow

Our architecture already requires:

- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/me`

So we need:

- short-lived access token
- long-lived refresh token
- refresh token hash stored in `device_sessions`
- one active refresh session per device

## 4. Stable secret management

Use:

- configured signing key from env/local config
- no startup-random key generation

## 5. Revocation-aware validation

Access token validation can stay stateless for speed, but refresh must be stateful.

Recommended approach:

- access token: signed JWT with short TTL
- refresh token: random secret or JWT, but always validated against `device_sessions`
- device revocation: revokes refresh ability immediately

## 6. Map roles to our domain

We only need:

- `ADMIN`
- `EDITOR`

And Spring authorities should still be exposed as:

- `ROLE_ADMIN`
- `ROLE_EDITOR`
- `ROLE_HOST_ADMIN` for the host-admin session itself

The authenticated host-admin session should also be granted `ROLE_ADMIN` and `ROLE_EDITOR` so it can reach any protected API without pretending to be a registered device.

## 7. Restrict host-only admin routes

Our route groups should eventually reflect architecture docs:

- `/api/admin/session/**`
- `/api/admin/onboarding`
- `/api/admin/settings`
- `/api/admin/password`
- `/api/admin/mobile-pairings/**`
- `/api/admin/web-access-requests/**`
- `/api/admin/devices/**`

These should not use the same auth flow as normal device APIs.

---

## Possible Structural Ideas We May Borrow

If we later borrow structural ideas from the reference repo, a package direction like this could still be useful:

```text
backend/src/main/java/com/manageit
  /auth
    /controller
    /service
    /dto
    /entity
    /repository
  /shared
    /security
      SecurityConfiguration
      DeviceJwtAuthenticationFilter
      HostAdminSessionFilter
      JwtService
      PasswordEncoderConfig
      CurrentDevicePrincipal
      CurrentAdminPrincipal
```

Possible future classes/interfaces:

- `SecurityConfiguration`
- `PasswordEncoder` bean
- `JwtService`
- `DeviceJwtAuthenticationFilter`
- `HostAdminSessionService`
- `HostAdminAuthenticationProvider` or equivalent admin auth service
- `DevicePrincipal`
- `AdminPrincipal`
- `RegisteredDeviceDetailsService` or device principal loader
- `RefreshTokenService`

---

## ManageIt Security Direction From Our Own Architecture

## A. Host admin password login

1. admin submits password to `/api/admin/session/login`
2. backend verifies against `app_settings.admin_password_hash`
3. backend creates secure admin session
4. secure session cookie is returned
5. host-only admin requests use that cookie

This is different from the reference repo.

## B. Approved web client flow

1. browser is approved through admin flow
2. backend creates `registered_devices` row
3. backend creates `device_sessions` row
4. backend issues short-lived access token
5. backend issues refresh token
6. browser stores access token in memory
7. browser stores refresh token in secure cookie
8. protected requests use access token bearer header
9. refresh endpoint renews access token when needed

## C. Approved mobile client flow

1. mobile pairing is completed
2. backend creates device + session
3. backend issues access token + refresh token
4. mobile app stores refresh token in Keychain
5. mobile sends access token on protected requests
6. mobile uses refresh endpoint when access token expires

## D. Protected API request flow in ManageIt

A future sequence consistent with our own architecture would look more like this:

1. request arrives with bearer token
2. device JWT filter extracts token
3. JWT service verifies signature and expiration
4. principal loader resolves current registered device
5. backend confirms device is active
6. backend loads role
7. filter sets `SecurityContext`
8. route rules and service-level role logic run

---

## Concrete Lessons To Carry Forward Carefully

## Possibly keep

- central filter chain
- custom JWT request filter
- `SecurityContextHolder` population flow
- role mapping through `GrantedAuthority`
- BCrypt
- Spring-managed authentication provider pattern

## Definitely improve

- use stable configured secret key
- use constructor injection
- use one shared password encoder bean
- separate host-admin security from device security
- add refresh-token and revocation model
- align route protection strictly with architecture docs

## Do not copy directly

- random signing key generated on startup
- user-email subject model for normal ManageIt devices
- no-refresh-token approach
- shared auth style for both admin UI and device APIs

---

## Reference Checklist For Later Comparison

- Define one stable signing key source
- Add a shared `PasswordEncoder` bean
- Implement admin password verification against `app_settings`
- Implement device access token creation
- Implement refresh token persistence in `device_sessions`
- Implement refresh endpoint
- Implement logout/revocation behavior
- Implement JWT filter for device APIs
- Implement host-only session protection for admin endpoints
- Map roles to `ROLE_ADMIN` and `ROLE_EDITOR`
- Add `/api/auth/me`
- Add device/session principal resolution
- Add tests for login, refresh, revoked device, expired token, and role-restricted routes

---

## Final Rule

The reference repository provides a good Spring Security shape:

- configuration
- provider
- user-details bridge
- JWT utility
- request filter

For ManageIt, parts of that shape may still be helpful, but the identity model must follow our own project plan:

- host admin session cookie for host-only admin UI
- device-based JWT + refresh model for approved clients
- database-backed revocation and session control

So the reference repository is useful as a technical example, but not as the design authority for this project.
