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

    var storedContext: StoredDeviceContext

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let preferences: AppPreferences

    @ObservationIgnored
    let reminderCoordinator: ReminderCoordinator

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    @ObservationIgnored
    private var searchDebounceTask: Task<Void, Never>?

    init(
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        preferences: AppPreferences,
        reminderCoordinator: ReminderCoordinator,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.preferences = preferences
        self.reminderCoordinator = reminderCoordinator
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated

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
            reminderCoordinator: reminderCoordinator,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
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
