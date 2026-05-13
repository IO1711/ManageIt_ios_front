import Foundation

enum DeviceRole: String, Codable, Equatable {
    case admin = "ADMIN"
    case editor = "EDITOR"

    var displayName: String {
        rawValue.capitalized
    }
}

enum DeviceType: String, Codable, Equatable {
    case iosApp = "IOS_APP"
    case webBrowser = "WEB_BROWSER"

    var displayName: String {
        switch self {
        case .iosApp:
            return "iOS App"
        case .webBrowser:
            return "Web Browser"
        }
    }
}

struct StoredDeviceContext: Codable, Equatable {
    let serverAddress: String
    let deviceId: UUID
    let role: DeviceRole
    let deviceType: DeviceType
    let friendlyName: String
    let refreshTokenExpiresAt: Date
}

struct ActiveDeviceSession: Equatable {
    let context: StoredDeviceContext
    let accessToken: String
    let accessTokenExpiresAt: Date
}
