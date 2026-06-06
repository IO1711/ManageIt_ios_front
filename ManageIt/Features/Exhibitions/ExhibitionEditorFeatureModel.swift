import Foundation
import Observation

@MainActor
@Observable
final class ExhibitionEditorFeatureModel: Identifiable {
    let id = UUID()

    enum EditorMode: Equatable {
        case create
        case edit(original: ExhibitionResponse)

        var title: String {
            switch self {
            case .create: return "New exhibition"
            case .edit: return "Edit exhibition"
            }
        }
    }

    var mode: EditorMode
    var name: String
    var selectedLocation: LocationResponse?
    var availableLocations: [LocationResponse] = []
    var startDate: BusinessDate?
    var endDate: BusinessDate?
    var selectedItems: [ExhibitionItemSummary]
    var itemQuery: String = ""
    var itemSuggestions: [ItemResponse] = []
    var isSaving: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    var validationMessage: String?
    var saveSucceeded: Bool = false
    var savedExhibition: ExhibitionResponse?

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
    private var authenticated: AuthenticatedAPI

    @ObservationIgnored
    private var itemSearchTask: Task<Void, Never>?

    init(
        mode: EditorMode,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.mode = mode
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )

        switch mode {
        case .create:
            self.name = ""
            self.selectedItems = []
            self.startDate = .today
            self.endDate = .today
        case .edit(let original):
            self.name = original.name
            self.selectedItems = original.items ?? []
            self.startDate = original.startDate
            self.endDate = original.endDate
        }
    }

    var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// True when the chosen date range covers today — in that case every linked
    /// item must already sit at the exhibition leaf location per architecture
    /// rules. Surfaces in the UI as a per-item warning and blocks submit.
    var willBeActive: Bool {
        guard let start = startDate, let end = endDate else { return false }
        let today = BusinessDate.today
        return start <= today && today <= end
    }

    func itemPlacementWarning(_ item: ExhibitionItemSummary) -> String? {
        guard willBeActive, let locationId = selectedLocation?.id else { return nil }
        guard let placement = item.currentPlacement else {
            return "Current placement unknown — verify before saving."
        }
        if placement.presenceType != .internal {
            return "Currently external — must be returned to \(selectedLocation?.displayPath ?? "exhibition location") before activating."
        }
        if placement.location?.id != locationId {
            let target = selectedLocation?.displayPath ?? "exhibition location"
            return "Currently at \(placement.displayTargetName) — move it to \(target) before activating."
        }
        return nil
    }

    var hasPlacementIssues: Bool {
        guard willBeActive else { return false }
        return selectedItems.contains(where: { itemPlacementWarning($0) != nil })
    }

    func loadDependencies() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let locationsTask = authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(serverURL: url, accessToken: token, includeArchived: false)
            }
            let locations = try await locationsTask
            self.availableLocations = locations

            // Hydrate the location reference for edit mode now that we know the tree.
            if case .edit(let original) = mode {
                if let loc = locations.first(where: { $0.id == original.locationId }) {
                    self.selectedLocation = loc
                }
            }
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func selectLocation(_ location: LocationResponse) {
        selectedLocation = location
    }

    func searchItems(query: String) {
        itemQuery = query
        itemSearchTask?.cancel()
        itemSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.performItemSearch(query: query)
        }
    }

    private func performItemSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            itemSuggestions = []
            return
        }
        do {
            var listQuery = InventoryListQuery()
            listQuery.searchText = query
            listQuery.size = 10
            let response = try await authenticated.perform { url, token in
                try await self.apiClient.fetchItems(serverURL: url, accessToken: token, query: listQuery)
            }
            let alreadySelected = Set(selectedItems.map(\.id))
            self.itemSuggestions = response.items.filter { !alreadySelected.contains($0.id) }
        } catch {
            // non-critical
        }
    }

    func addItem(_ item: ItemResponse) {
        guard !selectedItems.contains(where: { $0.id == item.id }) else { return }
        let summary = ExhibitionItemSummary(
            id: item.id,
            mainInventoryNumber: item.mainInventoryNumber,
            title: item.title,
            archived: item.archived,
            currentPlacement: item.currentPlacement
        )
        selectedItems.append(summary)
        itemQuery = ""
        itemSuggestions = []
    }

    func removeItem(id: Int64) {
        selectedItems.removeAll { $0.id == id }
    }

    func submit() async {
        validationMessage = nil
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            validationMessage = "Name is required."
            return
        }
        guard let location = selectedLocation, location.isAssignable, !location.archived else {
            validationMessage = "Choose a leaf internal location."
            return
        }
        guard let start = startDate else {
            validationMessage = "Start date is required."
            return
        }
        guard let end = endDate else {
            validationMessage = "End date is required."
            return
        }
        guard start <= end else {
            validationMessage = "Start date must be on or before end date."
            return
        }
        if selectedItems.isEmpty {
            validationMessage = "Add at least one item to the exhibition."
            return
        }
        if willBeActive && hasPlacementIssues {
            validationMessage = "One or more items are not currently at the exhibition location. Move them first, then save."
            return
        }

        let itemIds = selectedItems.map(\.id)

        isSaving = true
        defer { isSaving = false }

        do {
            let result: ExhibitionResponse
            switch mode {
            case .create:
                let request = ExhibitionCreateRequest(
                    name: trimmedName,
                    locationId: location.id,
                    startDate: start,
                    endDate: end,
                    itemIds: itemIds
                )
                result = try await authenticated.perform { url, token in
                    try await self.apiClient.createExhibition(serverURL: url, accessToken: token, request: request)
                }
            case .edit(let original):
                let request = ExhibitionUpdateRequest(
                    name: trimmedName,
                    locationId: location.id,
                    startDate: start,
                    endDate: end,
                    itemIds: itemIds
                )
                result = try await authenticated.perform { url, token in
                    try await self.apiClient.updateExhibition(serverURL: url, accessToken: token, id: original.id, request: request)
                }
            }
            savedExhibition = result
            saveSucceeded = true
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
