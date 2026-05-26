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

    var storedContext: StoredDeviceContext

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private let onItemUpdated: (ItemResponse) -> Void

    @ObservationIgnored
    private let onItemArchived: (ItemResponse) -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    init(
        itemID: Int64,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onItemUpdated: @escaping (ItemResponse) -> Void,
        onItemArchived: @escaping (ItemResponse) -> Void
    ) {
        self.itemID = itemID
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onItemUpdated = onItemUpdated
        self.onItemArchived = onItemArchived

        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    var role: DeviceRole { sessionModel.activeSession?.context.role ?? storedContext.role }

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
        guard let item else { return nil }
        return MovementFeatureModel(
            itemID: item.id,
            currentPresence: item.currentPlacement.presenceType,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func makeHistoryModel() -> ItemHistoryFeatureModel {
        ItemHistoryFeatureModel(
            itemID: itemID,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }
}
