import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var pairedDevice: StoredDeviceContext?
    var activeSession: ActiveDeviceSession?
    let pairingModel: PairingFeatureModel

    @ObservationIgnored
    private let preferences: AppPreferences

    @ObservationIgnored
    private let keychainStore: KeychainStore

    init() {
        let preferences = AppPreferences()
        let keychainStore = KeychainStore()
        let apiClient = ManageItAPIClient()

        self.preferences = preferences
        self.keychainStore = keychainStore
        self.pairedDevice = preferences.loadDeviceContext()
        self.activeSession = nil
        self.pairingModel = PairingFeatureModel(
            apiClient: apiClient,
            keychainStore: keychainStore,
            initialServerAddress: preferences.serverAddress
        )

        pairingModel.onActivationComplete = { [weak self] response, serverAddress in
            try self?.storeActivatedDevice(response: response, serverAddress: serverAddress)
        }
    }

    func clearLocalPairing() {
        keychainStore.clearRefreshToken()
        preferences.clearDeviceContext()
        activeSession = nil
        pairedDevice = nil
        pairingModel.reset(keepServerAddress: true)
    }

    private func storeActivatedDevice(
        response: MobilePairingCompleteResponse,
        serverAddress: String
    ) throws {
        do {
            try keychainStore.saveRefreshToken(response.refreshToken)
        } catch {
            throw ManageItError.secureStorageFailed
        }

        let context = StoredDeviceContext(
            serverAddress: serverAddress,
            deviceId: response.deviceId,
            role: response.role,
            deviceType: .iosApp,
            friendlyName: response.friendlyName,
            refreshTokenExpiresAt: response.refreshTokenExpiresAt
        )

        preferences.serverAddress = serverAddress
        preferences.saveDeviceContext(context)
        pairedDevice = context
        activeSession = ActiveDeviceSession(
            context: context,
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt
        )
    }
}
