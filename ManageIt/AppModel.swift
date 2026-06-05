import Foundation
import Network
import Observation

enum AppPhase: Equatable {
    case bootstrapping
    case pairing
    case restoring
    case active
    case sessionRecovery
}

@MainActor
@Observable
final class AppModel {
    var appPhase: AppPhase = .bootstrapping
    var pairedDevice: StoredDeviceContext?
    var pairingModel: PairingFeatureModel
    var sessionModel: DeviceSessionModel
    var inventoryModel: InventoryFeatureModel?
    var exhibitionsModel: ExhibitionsFeatureModel?

    @ObservationIgnored
    private let preferences: AppPreferences

    @ObservationIgnored
    private let keychainStore: KeychainStore

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let offlineMovementStore: OfflineMovementStore

    @ObservationIgnored
    private let reminderCoordinator: ReminderCoordinator

    @ObservationIgnored
    private var restoreTask: Task<Void, Never>?

    @ObservationIgnored
    private let pathMonitor: NWPathMonitor

    @ObservationIgnored
    private let pathMonitorQueue = DispatchQueue(label: "manageit.offline-sync.monitor")

    init() {
        let preferences = AppPreferences()
        let keychainStore = KeychainStore()

        let urlSession: URLSession = {
            let configuration = URLSessionConfiguration.default
            #if DEBUG
            var classes = configuration.protocolClasses ?? []
            classes.insert(DemoAPIProtocol.self, at: 0)
            configuration.protocolClasses = classes
            #endif
            return URLSession(configuration: configuration)
        }()
        let apiClient = ManageItAPIClient(urlSession: urlSession)
        let offlineMovementStore = OfflineMovementStore(preferences: preferences)

        self.preferences = preferences
        self.keychainStore = keychainStore
        self.apiClient = apiClient
        self.offlineMovementStore = offlineMovementStore

        let storedContext = preferences.loadDeviceContext()
        self.pairedDevice = storedContext

        #if DEBUG
        if let stored = storedContext, stored.serverAddress == DemoAPIProtocol.demoServerAddress {
            DemoAPIProtocol.enable()
        }
        #endif

        let sessionModel = DeviceSessionModel(
            apiClient: apiClient,
            keychainStore: keychainStore
        )
        self.sessionModel = sessionModel
        self.reminderCoordinator = ReminderCoordinator(
            apiClient: apiClient,
            sessionModel: sessionModel
        )
        self.pathMonitor = NWPathMonitor()
        self.pairingModel = PairingFeatureModel(
            apiClient: apiClient,
            keychainStore: keychainStore,
            initialServerAddress: preferences.serverAddress
        )

        if storedContext == nil {
            self.appPhase = .pairing
        }

        pairingModel.onActivationComplete = { [weak self] response, serverAddress in
            try self?.activatePairedDevice(response: response, serverAddress: serverAddress)
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                await self?.syncOfflineMovements()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    var activeSession: ActiveDeviceSession? {
        sessionModel.activeSession
    }

    func bootIfNeeded() {
        guard restoreTask == nil else { return }
        restoreTask = Task { [weak self] in
            await self?.restoreSessionOnLaunch()
        }
    }

    func restoreSessionOnLaunch() async {
        guard let storedContext = pairedDevice else {
            appPhase = .pairing
            return
        }

        appPhase = .restoring

        do {
            let session = try await sessionModel.restore(storedContext: storedContext)
            updatePersistedContext(from: session)
            inventoryModel = makeInventoryModel(for: session.context)
            exhibitionsModel = makeExhibitionsModel(for: session.context)
            appPhase = .active
            await syncOfflineMovements()
        } catch {
            appPhase = .sessionRecovery
        }
    }

    func activatePairedDevice(
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

        let session = ActiveDeviceSession(
            context: context,
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt
        )
        sessionModel.adopt(activeSession: session)
        inventoryModel = makeInventoryModel(for: context)
        exhibitionsModel = makeExhibitionsModel(for: context)
        appPhase = .active
        Task { await syncLocalState() }
    }

    func applyRefreshedSession(_ session: ActiveDeviceSession) {
        pairedDevice = session.context
        preferences.saveDeviceContext(session.context)
        if inventoryModel == nil {
            inventoryModel = makeInventoryModel(for: session.context)
        } else {
            inventoryModel?.updateStoredContext(session.context)
        }
        if exhibitionsModel == nil {
            exhibitionsModel = makeExhibitionsModel(for: session.context)
        } else {
            exhibitionsModel?.updateStoredContext(session.context)
        }
    }

    func handleSessionInvalidation(clearLocalPairing: Bool) {
        sessionModel.clear()
        inventoryModel = nil
        exhibitionsModel = nil
        Task { await reminderCoordinator.cancelManagedNotifications() }
        if clearLocalPairing {
            clearAllLocalPairing()
        } else {
            appPhase = .sessionRecovery
        }
    }

    func logoutCurrentDevice() async {
        if let context = pairedDevice {
            await sessionModel.logout(storedContext: context)
        }
        clearAllLocalPairing()
    }

    func clearAllLocalPairing() {
        keychainStore.clearAuthenticatedMaterial()
        preferences.clearDeviceContext()
        sessionModel.clear()
        inventoryModel = nil
        exhibitionsModel = nil
        pairedDevice = nil
        offlineMovementStore.clearAll()
        pairingModel.reset(keepServerAddress: true)
        appPhase = .pairing
        Task { await reminderCoordinator.cancelManagedNotifications() }
    }

    func retryRestore() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            await self?.restoreSessionOnLaunch()
        }
    }

    #if DEBUG
    /// Bypasses real pairing by enabling the in-memory `DemoAPIProtocol` and seeding
    /// a fake ADMIN device context. The normal restore flow then drives everything
    /// through canned demo responses so all screens become navigable without a backend.
    func activateDemoMode() {
        DemoAPIProtocol.enable()

        let context = StoredDeviceContext(
            serverAddress: DemoAPIProtocol.demoServerAddress,
            deviceId: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            role: .admin,
            deviceType: .iosApp,
            friendlyName: "Demo iPhone",
            refreshTokenExpiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30)
        )

        try? keychainStore.saveRefreshToken("demo-refresh-token")
        preferences.serverAddress = context.serverAddress
        preferences.saveDeviceContext(context)
        pairedDevice = context

        retryRestore()
    }
    #endif

    // MARK: -

    private func updatePersistedContext(from session: ActiveDeviceSession) {
        pairedDevice = session.context
        preferences.saveDeviceContext(session.context)
    }

    private func makeInventoryModel(for context: StoredDeviceContext) -> InventoryFeatureModel {
        InventoryFeatureModel(
            storedContext: context,
            sessionModel: sessionModel,
            apiClient: apiClient,
            preferences: preferences,
            offlineMovementStore: offlineMovementStore,
            onContextUpdated: { [weak self] updated in
                self?.pairedDevice = updated
                self?.preferences.saveDeviceContext(updated)
            },
            onSessionInvalidated: { [weak self] in
                self?.handleSessionInvalidation(clearLocalPairing: false)
            },
            onReminderSourcesChanged: { [weak self] in
                guard let self else { return }
                Task { await self.syncLocalState() }
            }
        )
    }

    private func makeExhibitionsModel(for context: StoredDeviceContext) -> ExhibitionsFeatureModel {
        ExhibitionsFeatureModel(
            storedContext: context,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: { [weak self] updated in
                self?.pairedDevice = updated
                self?.preferences.saveDeviceContext(updated)
            },
            onSessionInvalidated: { [weak self] in
                self?.handleSessionInvalidation(clearLocalPairing: false)
            },
            onReminderSourcesChanged: { [weak self] in
                guard let self else { return }
                Task { await self.syncLocalState() }
            }
        )
    }

    func syncLocalState() async {
        await syncOfflineMovements()
        await syncReminders()
    }

    func syncOfflineMovements() async {
        guard let context = sessionModel.activeSession?.context ?? pairedDevice else {
            return
        }

        let authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: context,
            onContextUpdated: { [weak self] updated in
                self?.pairedDevice = updated
                self?.preferences.saveDeviceContext(updated)
            },
            onSessionInvalidated: { [weak self] in
                self?.handleSessionInvalidation(clearLocalPairing: false)
            }
        )

        await offlineMovementStore.syncQueuedMovements(
            authenticated: authenticated,
            apiClient: apiClient
        )
    }

    func syncReminders() async {
        guard let context = sessionModel.activeSession?.context ?? pairedDevice else {
            await reminderCoordinator.cancelManagedNotifications()
            return
        }

        await reminderCoordinator.syncAll(
            storedContext: context,
            onContextUpdated: { [weak self] updated in
                self?.pairedDevice = updated
                self?.preferences.saveDeviceContext(updated)
            },
            onSessionInvalidated: { [weak self] in
                self?.handleSessionInvalidation(clearLocalPairing: false)
            }
        )
    }
}
