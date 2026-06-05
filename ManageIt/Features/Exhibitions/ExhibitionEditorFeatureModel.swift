import Foundation
import Observation

@MainActor
@Observable
final class ExhibitionEditorFeatureModel: Identifiable {
    enum Mode: Equatable {
        case create
        case edit(existing: ExhibitionDetailResponse)

        var title: String {
            switch self {
            case .create:
                return "New exhibition"
            case .edit:
                return "Edit exhibition"
            }
        }
    }

    let id: UUID = UUID()

    var mode: Mode
    var name: String
    var selectedLocationID: Int64?
    var startDate: BusinessDate?
    var endDate: BusinessDate?
    var locationOptions: [LocationResponse] = []
    var candidateItems: [ItemResponse] = []
    var selectedItemIDs: Set<Int64>
    var itemSearchText: String = ""
    var isLoadingDependencies: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var validationMessage: String?
    var saveSucceeded: Bool = false
    var savedExhibition: ExhibitionDetailResponse?

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
    private let onReminderSourcesChanged: () -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    init(
        mode: Mode,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onReminderSourcesChanged: @escaping () -> Void
    ) {
        self.mode = mode
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onReminderSourcesChanged = onReminderSourcesChanged
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
            self.selectedLocationID = nil
            self.startDate = .today
            self.endDate = .today
            self.selectedItemIDs = []
        case .edit(let existing):
            self.name = existing.name
            self.selectedLocationID = existing.location.id
            self.startDate = existing.startDate
            self.endDate = existing.endDate
            self.selectedItemIDs = Set(existing.items.map(\.id))
        }
    }

    var filteredCandidateItems: [ItemResponse] {
        let trimmed = itemSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return candidateItems
        }

        let query = trimmed.lowercased()
        return candidateItems.filter { item in
            item.title.lowercased().contains(query)
                || item.mainInventoryNumber.lowercased().contains(query)
                || item.currentPlacement.displayTargetName.lowercased().contains(query)
        }
    }

    var selectedItems: [ItemResponse] {
        candidateItems
            .filter { selectedItemIDs.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func loadDependenciesIfNeeded() async {
        guard locationOptions.isEmpty || candidateItems.isEmpty else { return }

        isLoadingDependencies = true
        errorMessage = nil
        defer { isLoadingDependencies = false }

        do {
            let locations = try await authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(
                    serverURL: url,
                    accessToken: token,
                    includeArchived: false
                )
            }
            let items = try await authenticated.perform { url, token in
                try await self.apiClient.fetchAllItems(
                    serverURL: url,
                    accessToken: token,
                    includeArchived: false,
                    pageSize: 100
                )
            }

            locationOptions = assignableLocations(from: locations)
            candidateItems = items.filter { !$0.archived }
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func toggleItemSelection(_ item: ItemResponse) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func submit() async {
        validationMessage = nil
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Exhibition name is required."
            return
        }
        guard let locationID = selectedLocationID else {
            validationMessage = "Choose a leaf exhibition location."
            return
        }
        guard let startDate else {
            validationMessage = "Start date is required."
            return
        }
        guard let endDate else {
            validationMessage = "End date is required."
            return
        }
        guard startDate <= endDate else {
            validationMessage = "The end date must be on or after the start date."
            return
        }
        guard !selectedItemIDs.isEmpty else {
            validationMessage = "Select at least one item for the exhibition."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let saved: ExhibitionDetailResponse
            switch mode {
            case .create:
                let request = ExhibitionCreateRequest(
                    name: trimmedName,
                    locationId: locationID,
                    startDate: startDate,
                    endDate: endDate,
                    itemIds: Array(selectedItemIDs).sorted()
                )
                saved = try await authenticated.perform { url, token in
                    try await self.apiClient.createExhibition(
                        serverURL: url,
                        accessToken: token,
                        request: request
                    )
                }
            case .edit(let existing):
                let request = ExhibitionUpdateRequest(
                    name: trimmedName,
                    locationId: locationID,
                    startDate: startDate,
                    endDate: endDate,
                    itemIds: Array(selectedItemIDs).sorted()
                )
                saved = try await authenticated.perform { url, token in
                    try await self.apiClient.updateExhibition(
                        serverURL: url,
                        accessToken: token,
                        exhibitionID: existing.id,
                        request: request
                    )
                }
            }

            savedExhibition = saved
            saveSucceeded = true
            onReminderSourcesChanged()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
