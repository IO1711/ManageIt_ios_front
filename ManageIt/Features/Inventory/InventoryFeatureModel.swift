import Foundation
import Observation

@MainActor
@Observable
final class InventoryFeatureModel {
    var items: [ItemResponse] = []
    var query: InventoryListQuery
    var isLoading: Bool = false
    var isLoadingNextPage: Bool = false
    var errorMessage: String?
    var hasLoadedOnce: Bool = false
    var totalItems: Int64 = 0
    var totalPages: Int = 0
    var offlineStateVersion: Int = 0

    var storedContext: StoredDeviceContext

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let preferences: AppPreferences

    @ObservationIgnored
    private let offlineMovementStore: OfflineMovementStore

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private let onReminderSourcesChanged: () -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    @ObservationIgnored
    private var searchDebounceTask: Task<Void, Never>?

    @ObservationIgnored
    private var offlineObserverTask: Task<Void, Never>?

    @ObservationIgnored
    private var snapshotObserverTask: Task<Void, Never>?

    init(
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        preferences: AppPreferences,
        offlineMovementStore: OfflineMovementStore,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onReminderSourcesChanged: @escaping () -> Void
    ) {
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.preferences = preferences
        self.offlineMovementStore = offlineMovementStore
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onReminderSourcesChanged = onReminderSourcesChanged

        var query = InventoryListQuery()
        query.searchText = preferences.loadLastInventoryQuery()
        self.query = query

        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: { updated in
                onContextUpdated(updated)
            },
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
                if let item = notification.userInfo?[OfflineMovementNotificationKey.item] as? ItemResponse {
                    self.replaceItem(item)
                }
                self.offlineStateVersion += 1
            }
        }
    }

    deinit {
        offlineObserverTask?.cancel()
        snapshotObserverTask?.cancel()
    }

    func updateStoredContext(_ context: StoredDeviceContext) {
        self.storedContext = context
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: context,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    var role: DeviceRole { storedContext.role }

    var visibleItems: [ItemResponse] {
        _ = offlineStateVersion
        return items.map { offlineMovementStore.applyOverlay(to: $0) }
    }

    func loadFirstPage() async {
        query.page = 0
        await load(replace: true)
    }

    func reload() async {
        query.page = 0
        await load(replace: true)
    }

    func loadNextPageIfNeeded(currentItemID: Int64) async {
        guard !isLoading, !isLoadingNextPage else { return }
        guard let lastIndex = items.lastIndex(where: { $0.id == currentItemID }) else { return }
        guard lastIndex >= items.count - 3 else { return }
        guard items.count < totalItems else { return }

        query.page += 1
        await load(replace: false, isNextPage: true)
    }

    func updateSearchText(_ value: String) {
        query.searchText = value
        preferences.saveLastInventoryQuery(value)
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.loadFirstPage()
        }
    }

    func setIncludeArchived(_ includeArchived: Bool) {
        guard storedContext.role.isAdmin else { return }
        query.includeArchived = includeArchived
        Task { await self.loadFirstPage() }
    }

    func replaceItem(_ updated: ItemResponse) {
        if let idx = items.firstIndex(where: { $0.id == updated.id }) {
            items[idx] = updated
        }
    }

    func removeItem(id: Int64) {
        items.removeAll { $0.id == id }
    }

    func itemSnapshot(id: Int64) -> ItemResponse? {
        visibleItems.first(where: { $0.id == id })
    }

    func offlineStatusPresentation(for itemId: Int64) -> OfflineMovementStatusPresentation? {
        _ = offlineStateVersion
        return offlineMovementStore.statusPresentation(for: itemId)
    }

    // MARK: -

    private func load(replace: Bool, isNextPage: Bool = false) async {
        if isNextPage {
            isLoadingNextPage = true
        } else {
            isLoading = true
        }
        errorMessage = nil

        defer {
            if isNextPage {
                isLoadingNextPage = false
            } else {
                isLoading = false
                hasLoadedOnce = true
            }
        }

        do {
            let snapshot = query
            let response = try await authenticated.perform { url, token in
                try await self.apiClient.fetchItems(serverURL: url, accessToken: token, query: snapshot)
            }
            if replace {
                items = response.items
            } else {
                items.append(contentsOf: response.items)
            }
            totalItems = response.totalItems
            totalPages = response.totalPages
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    // MARK: - Factories used to spin up child feature models

    func makeDetailModel(for itemID: Int64) -> ItemDetailFeatureModel {
        ItemDetailFeatureModel(
            itemID: itemID,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            offlineMovementStore: offlineMovementStore,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
            onReminderSourcesChanged: onReminderSourcesChanged,
            onItemUpdated: { [weak self] updated in
                self?.replaceItem(updated)
            },
            onItemArchived: { [weak self] archived in
                if self?.query.includeArchived == true {
                    self?.replaceItem(archived)
                } else {
                    self?.removeItem(id: archived.id)
                }
            }
        )
    }

    func makeCreateEditorModel() -> ItemEditorFeatureModel {
        ItemEditorFeatureModel(
            mode: .create,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func makeMovementModel(for item: ItemResponse) -> MovementFeatureModel {
        MovementFeatureModel(
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

    func makeHistoryModel(for itemID: Int64) -> ItemHistoryFeatureModel {
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

    func makeLocationManagementModel() -> LocationManagementFeatureModel {
        LocationManagementFeatureModel(
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }
}
