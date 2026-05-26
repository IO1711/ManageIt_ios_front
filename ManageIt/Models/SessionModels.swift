import Foundation

enum DeviceRole: String, Codable, Equatable {
    case admin = "ADMIN"
    case editor = "EDITOR"

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .editor: return "Editor"
        }
    }

    var isAdmin: Bool { self == .admin }
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
    var role: DeviceRole
    let deviceType: DeviceType
    var friendlyName: String
    var refreshTokenExpiresAt: Date

    func serverURL() throws -> URL {
        var address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty {
            throw ManageItError.invalidServerAddress
        }
        if !address.contains("://") {
            address = "http://\(address)"
        }
        guard let url = URL(string: address) else {
            throw ManageItError.invalidServerAddress
        }
        return url
    }
}

struct ActiveDeviceSession: Equatable {
    var context: StoredDeviceContext
    var accessToken: String
    var accessTokenExpiresAt: Date
}
