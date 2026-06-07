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
        case let .backend(code, message):
            switch code {
            case "ITEM_EXHIBITION_OVERLAP":
                return "One or more items already belong to another exhibition in an overlapping period. Adjust the dates or remove the conflicting items."
            case "ITEM_NOT_AT_EXHIBITION_LOCATION":
                return "One or more items are not currently at the exhibition location. Move them there first, then try again."
            case "NON_LEAF_LOCATION":
                return "Items and exhibitions can only reference leaf locations. Pick a child node."
            case "STALE_OFFLINE_MOVEMENT":
                return "The queued offline movement no longer matches the server's current item state and was rejected."
            default:
                return message
            }
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
