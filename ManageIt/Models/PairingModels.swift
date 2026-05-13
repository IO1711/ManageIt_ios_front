import Foundation

enum MobilePairingSessionStatus: String, Codable, Equatable {
    case generated = "GENERATED"
    case scanned = "SCANNED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
}

struct MobilePairingScanRequest: Encodable {
    let pairingToken: UUID
    let installationId: UUID
    let suggestedName: String
    let platformName: String
    let platformVersion: String
    let modelName: String
}

struct MobilePairingStatusResponse: Decodable, Equatable {
    let pairingId: UUID
    let status: MobilePairingSessionStatus
    let expiresAt: Date
    let scannedAt: Date?
    let completedAt: Date?
    let expired: Bool
    let friendlyName: String?
}

struct MobilePairingCompleteResponse: Decodable, Equatable {
    let deviceId: UUID
    let role: DeviceRole
    let friendlyName: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}
