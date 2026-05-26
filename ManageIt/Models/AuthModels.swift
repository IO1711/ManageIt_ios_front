import Foundation

struct DeviceTokenRefreshRequest: Encodable, Equatable {
    let refreshToken: String
}

struct DeviceTokenRefreshResponse: Decodable, Equatable {
    let deviceId: UUID
    let role: DeviceRole
    let deviceType: DeviceType
    let friendlyName: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String?
    let refreshTokenExpiresAt: Date
}

struct DeviceSessionStatusResponse: Decodable, Equatable {
    let authenticated: Bool
    let deviceId: UUID
    let role: DeviceRole
    let deviceType: DeviceType
    let friendlyName: String
}

enum SessionRecoveryReason: Equatable {
    case missingRefreshToken
    case revokedDevice
    case expiredSession
    case serverUnreachable
    case corruptLocalState

    var headline: String {
        switch self {
        case .missingRefreshToken:
            return "Sign in again to continue"
        case .revokedDevice:
            return "This device has been revoked"
        case .expiredSession:
            return "Session has expired"
        case .serverUnreachable:
            return "Museum server unreachable"
        case .corruptLocalState:
            return "Local session state is unusable"
        }
    }

    var detail: String {
        switch self {
        case .missingRefreshToken:
            return "We could not find the secure refresh token on this iPhone. Re-pair this device from the host admin screen."
        case .revokedDevice:
            return "The host admin revoked this iPhone. Ask them to pair this device again."
        case .expiredSession:
            return "Your session timed out. Re-pair to restore access."
        case .serverUnreachable:
            return "Could not reach the museum server. Check the Wi-Fi connection and try again."
        case .corruptLocalState:
            return "Stored session details are no longer usable. Clear local pairing and start over."
        }
    }
}
