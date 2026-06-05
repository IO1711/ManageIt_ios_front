import Foundation
import Observation

@MainActor
@Observable
final class ItemHistoryFeatureModel {
    var itemID: Int64
    var entries: [ItemHistoryEntry] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var offlineStateVersion: Int = 0

    var storedContext: StoredDeviceContext

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let offlineMovementStore: OfflineMovementStore

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    @ObservationIgnored
    private var offlineObserverTask: Task<Void, Never>?

    @ObservationIgnored
    private var snapshotObserverTask: Task<Void, Never>?

    init(
        itemID: Int64,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        offlineMovementStore: OfflineMovementStore,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.itemID = itemID
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.offlineMovementStore = offlineMovementStore
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )

        self.offlineObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .offlineMovementStoreDidChange) {
                guard let self else { return }
                self.offlineStateVersion += 1
            }
        }

        self.snapshotObserverTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .offlineMovementServerSnapshotDidChange) {
                guard let self else { return }
                let changedItemID: Int64?
                if let item = notification.userInfo?[OfflineMovementNotificationKey.item] as? ItemResponse {
                    changedItemID = item.id
                } else if let rawID = notification.userInfo?[OfflineMovementNotificationKey.itemId] as? NSNumber {
                    changedItemID = rawID.int64Value
                } else {
                    changedItemID = notification.userInfo?[OfflineMovementNotificationKey.itemId] as? Int64
                }

                guard changedItemID == self.itemID else {
                    continue
                }
                if let history = notification.userInfo?[OfflineMovementNotificationKey.history] as? [ItemHistoryEntry] {
                    self.entries = history
                }
                self.offlineStateVersion += 1
            }
        }
    }

    deinit {
        offlineObserverTask?.cancel()
        snapshotObserverTask?.cancel()
    }

    var displayedEntries: [ItemHistoryEntry] {
        _ = offlineStateVersion
        return offlineMovementStore.applyOverlay(to: entries, itemId: itemID)
    }

    var offlineStatusPresentation: OfflineMovementStatusPresentation? {
        _ = offlineStateVersion
        return offlineMovementStore.statusPresentation(for: itemID)
    }

    func dismissRejectedOfflineMovement() {
        offlineMovementStore.dismissRejectedEntry(for: itemID)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let results = try await authenticated.perform { url, token in
                try await self.apiClient.fetchItemHistory(serverURL: url, accessToken: token, itemID: self.itemID)
            }
            self.entries = results
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
