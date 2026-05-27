import Foundation
import Observation

@MainActor
@Observable
final class DeviceSessionModel {
    var activeSession: ActiveDeviceSession?
    var recoveryReason: SessionRecoveryReason?
    var isRestoring: Bool = false
    var isRefreshing: Bool = false

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let keychainStore: KeychainStore

    init(apiClient: ManageItAPIClient, keychainStore: KeychainStore) {
        self.apiClient = apiClient
        self.keychainStore = keychainStore
    }

    func adopt(activeSession: ActiveDeviceSession) {
        self.activeSession = activeSession
        self.recoveryReason = nil
    }

    func clear() {
        activeSession = nil
        recoveryReason = nil
    }

    func restore(storedContext: StoredDeviceContext) async throws -> ActiveDeviceSession {
        isRestoring = true
        defer { isRestoring = false }

        let refreshToken: String?
        do {
            refreshToken = try keychainStore.loadRefreshToken()
        } catch {
            recoveryReason = .corruptLocalState
            throw ManageItError.secureStorageFailed
        }

        guard let token = refreshToken, !token.isEmpty else {
            recoveryReason = .missingRefreshToken
            throw ManageItError.unauthorized
        }

        let serverURL: URL
        do {
            serverURL = try storedContext.serverURL()
        } catch {
            recoveryReason = .corruptLocalState
            throw error
        }

        do {
            let response = try await apiClient.refreshDeviceSession(
                serverURL: serverURL,
                request: DeviceTokenRefreshRequest(refreshToken: token)
            )
            let session = try applyRefreshResponse(response, base: storedContext)
            return session
        } catch let error as ManageItError {
            recoveryReason = mapToRecoveryReason(error)
            throw error
        } catch {
            recoveryReason = .serverUnreachable
            throw error
        }
    }

    func ensureValidAccessToken(storedContext: StoredDeviceContext) async throws -> String {
        if let session = activeSession, session.accessTokenExpiresAt > Date().addingTimeInterval(15) {
            return session.accessToken
        }
        let refreshed = try await refresh(storedContext: storedContext)
        return refreshed.accessToken
    }

    func refresh(storedContext: StoredDeviceContext) async throws -> ActiveDeviceSession {
        isRefreshing = true
        defer { isRefreshing = false }

        let refreshTokenOptional: String? = try? keychainStore.loadRefreshToken()
        guard let refreshToken = refreshTokenOptional, !refreshToken.isEmpty else {
            recoveryReason = .missingRefreshToken
            throw ManageItError.unauthorized
        }

        let serverURL = try storedContext.serverURL()

        do {
            let response = try await apiClient.refreshDeviceSession(
                serverURL: serverURL,
                request: DeviceTokenRefreshRequest(refreshToken: refreshToken)
            )
            return try applyRefreshResponse(response, base: storedContext)
        } catch let error as ManageItError {
            recoveryReason = mapToRecoveryReason(error)
            throw error
        } catch {
            recoveryReason = .serverUnreachable
            throw error
        }
    }

    func fetchCurrentDeviceStatus(storedContext: StoredDeviceContext) async throws -> DeviceSessionStatusResponse {
        let token = try await ensureValidAccessToken(storedContext: storedContext)
        let serverURL = try storedContext.serverURL()
        return try await apiClient.fetchCurrentSession(serverURL: serverURL, accessToken: token)
    }

    func logout(storedContext: StoredDeviceContext) async {
        if let session = activeSession {
            let serverURL = try? storedContext.serverURL()
            if let url = serverURL {
                try? await apiClient.logoutCurrentSession(
                    serverURL: url,
                    accessToken: session.accessToken
                )
            }
        }
        activeSession = nil
        recoveryReason = nil
    }

    // MARK: -

    private func applyRefreshResponse(
        _ response: DeviceTokenRefreshResponse,
        base: StoredDeviceContext
    ) throws -> ActiveDeviceSession {
        var updated = base
        updated.role = response.role
        updated.friendlyName = response.friendlyName
        updated.refreshTokenExpiresAt = response.refreshTokenExpiresAt

        if let newRefreshToken = response.refreshToken, !newRefreshToken.isEmpty {
            do {
                try keychainStore.saveRefreshToken(newRefreshToken)
            } catch {
                throw ManageItError.secureStorageFailed
            }
        }

        let session = ActiveDeviceSession(
            context: updated,
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt
        )
        self.activeSession = session
        self.recoveryReason = nil
        return session
    }

    private func mapToRecoveryReason(_ error: ManageItError) -> SessionRecoveryReason {
        switch error {
        case .deviceRevoked:
            return .revokedDevice
        case .unauthorized:
            return .expiredSession
        case let .backend(code, _):
            if code == "DEVICE_REVOKED" { return .revokedDevice }
            return .expiredSession
        case .transportFailure:
            return .serverUnreachable
        case .invalidServerAddress, .invalidResponse:
            return .corruptLocalState
        default:
            return .expiredSession
        }
    }
}
