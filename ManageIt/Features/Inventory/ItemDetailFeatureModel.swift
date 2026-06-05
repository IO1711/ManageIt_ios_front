import Foundation
import Observation

@MainActor
@Observable
final class ItemDetailFeatureModel {
    var itemID: Int64
    var item: ItemResponse?
    var historyEntries: [ItemHistoryEntry] = []
    var isLoading: Bool = false
    var isLoadingHistory: Bool = false
    var isArchiving: Bool = false
    var errorMessage: String?
    var historyErrorMessage: String?
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
    private let onItemUpdated: (ItemResponse) -> Void

    @ObservationIgnored
    private let onItemArchived: (ItemResponse) -> Void

    @ObservationIgnored
    private let onReminderSourcesChanged: () -> Void

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
        onSessionInvalidated: @escaping () -> Void,
        onReminderSourcesChanged: @escaping () -> Void,
        onItemUpdated: @escaping (ItemResponse) -> Void,
        onItemArchived: @escaping (ItemResponse) -> Void
    ) {
        self.itemID = itemID
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.offlineMovementStore = offlineMovementStore
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onReminderSourcesChanged = onReminderSourcesChanged
        self.onItemUpdated = onItemUpdated
        self.onItemArchived = onItemArchived

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

                if let item = notification.userInfo?[OfflineMovementNotificationKey.item] as? ItemResponse {
                    self.item = item
                    self.onItemUpdated(item)
                }
                if let history = notification.userInfo?[OfflineMovementNotificationKey.history] as? [ItemHistoryEntry] {
                    self.historyEntries = history
                }
                self.offlineStateVersion += 1
            }
        }
    }

    deinit {
        offlineObserverTask?.cancel()
        snapshotObserverTask?.cancel()
    }

    var role: DeviceRole { sessionModel.activeSession?.context.role ?? storedContext.role }

    var displayedItem: ItemResponse? {
        _ = offlineStateVersion
        guard let item else { return nil }
        return offlineMovementStore.applyOverlay(to: item)
    }

    var displayedHistoryEntries: [ItemHistoryEntry] {
        _ = offlineStateVersion
        return offlineMovementStore.applyOverlay(to: historyEntries, itemId: itemID)
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
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.fetchItem(serverURL: url, accessToken: token, itemID: self.itemID)
            }
            self.item = result
            await loadHistory()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func reload() async {
        await load()
    }

    func loadHistory() async {
        isLoadingHistory = true
        historyErrorMessage = nil
        defer { isLoadingHistory = false }
        do {
            let entries = try await authenticated.perform { url, token in
                try await self.apiClient.fetchItemHistory(serverURL: url, accessToken: token, itemID: self.itemID)
            }
            self.historyEntries = entries
        } catch {
            historyErrorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func archiveItem() async {
        guard role.isAdmin else { return }
        isArchiving = true
        defer { isArchiving = false }
        do {
            let archived = try await authenticated.perform { url, token in
                try await self.apiClient.archiveItem(serverURL: url, accessToken: token, itemID: self.itemID)
            }
            self.item = archived
            self.onItemArchived(archived)
            onReminderSourcesChanged()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func applyUpdatedItem(_ updated: ItemResponse) {
        self.item = updated
        onItemUpdated(updated)
    }

    // MARK: - Child models

    func makeEditorModel() -> ItemEditorFeatureModel? {
        guard let item else { return nil }
        return ItemEditorFeatureModel(
            mode: .edit(itemID: item.id, original: item),
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func makePlanningEditorModel() -> PlanningEditorFeatureModel? {
        guard let item else { return nil }
        return PlanningEditorFeatureModel(
            itemID: item.id,
            initialPlanning: item.planning,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func makeMovementModel() -> MovementFeatureModel? {
        guard let item = displayedItem else { return nil }
        return MovementFeatureModel(
            currentItem: item,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            offlineMovementStore: offlineMovementStore,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
            onReminderSourcesChanged: onReminderSourcesChanged
        )
    }

    func makeHistoryModel() -> ItemHistoryFeatureModel {
        ItemHistoryFeatureModel(
            itemID: itemID,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            offlineMovementStore: offlineMovementStore,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }
}
