import Foundation

enum ManageItError: LocalizedError {
    case invalidServerAddress
    case invalidPairingCode
    case pairingCancelled
    case pairingExpired
    case invalidResponse
    case transportFailure(endpoint: String, details: String)
    case backend(code: String, message: String)
    case deviceIdentityUnavailable
    case secureStorageFailed
    case unauthorized
    case deviceRevoked
    case validationError(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            return "This pairing link does not include a usable museum server address."
        case .invalidPairingCode:
            return "The QR content could not be read as a ManageIt pairing token."
        case .pairingCancelled:
            return "This pairing request was cancelled from the host screen. Generate a new QR code and try again."
        case .pairingExpired:
            return "This pairing token has expired. Generate a new QR code from the host screen."
        case .invalidResponse:
            return "The server returned a response that the app could not understand."
        case let .transportFailure(endpoint, details):
            return """
            The iPhone could not reach the museum server.
            Request: \(endpoint)
            Underlying error: \(details)
            """
        case .backend(_, let message):
            return message
        case .deviceIdentityUnavailable:
            return "The iPhone could not create or read its stable installation identity from Keychain."
        case .secureStorageFailed:
            return "The iPhone received device credentials but could not save them securely in Keychain."
        case .unauthorized:
            return "This session is no longer authorized. Please re-pair this device."
        case .deviceRevoked:
            return "This device has been revoked by the host admin."
        case .validationError(let message):
            return message
        }
    }
}
