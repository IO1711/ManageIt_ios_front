import Foundation

/// Thin coordinator that pairs a `ManageItAPIClient` with a live `DeviceSessionModel`
/// so feature models do not have to repeat token resolution, recovery routing, and
/// stored-context updates for every authenticated call.
@MainActor
final class AuthenticatedAPI {
    let apiClient: ManageItAPIClient
    private let sessionModel: DeviceSessionModel
    private let initialContext: StoredDeviceContext
    private let onContextUpdated: (StoredDeviceContext) -> Void
    private let onSessionInvalidated: () -> Void

    init(
        apiClient: ManageItAPIClient,
        sessionModel: DeviceSessionModel,
        storedContext: StoredDeviceContext,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.apiClient = apiClient
        self.sessionModel = sessionModel
        self.initialContext = storedContext
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
    }

    func currentContext() -> StoredDeviceContext {
        sessionModel.activeSession?.context ?? initialContext
    }

    func perform<T>(
        _ block: (_ serverURL: URL, _ accessToken: String) async throws -> T
    ) async throws -> T {
        let context = currentContext()
        let serverURL: URL
        do {
            serverURL = try context.serverURL()
        } catch let error as ManageItError {
            throw error
        }

        do {
            let token = try await sessionModel.ensureValidAccessToken(storedContext: context)
            let result = try await block(serverURL, token)
            if let updated = sessionModel.activeSession?.context, updated != context {
                onContextUpdated(updated)
            }
            return result
        } catch let error as ManageItError {
            if AuthenticatedAPI.isFatalAuth(error) {
                onSessionInvalidated()
            }
            throw error
        }
    }

    static func isFatalAuth(_ error: ManageItError) -> Bool {
        switch error {
        case .unauthorized, .deviceRevoked:
            return true
        case let .backend(code, _):
            return code == "DEVICE_REVOKED"
        default:
            return false
        }
    }

    static func userFacing(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
