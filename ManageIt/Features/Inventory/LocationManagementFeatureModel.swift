import Foundation
import Observation

@MainActor
@Observable
final class LocationManagementFeatureModel {
    var locations: [LocationResponse] = []
    var includeArchived: Bool = false
    var draftLocationName: String = ""
    var draftParent: LocationResponse?
    var editingLocationID: Int64?
    var editingName: String = ""
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?

    /// Built from the flat `locations` list — used by the tree picker for parent
    /// selection and the management list display.
    var tree: [LocationTreeNode] { LocationTreeBuilder.build(from: locations) }

    var storedContext: StoredDeviceContext

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    let offlineSyncCoordinator: OfflineSyncCoordinator

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    init(
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        offlineSyncCoordinator: OfflineSyncCoordinator,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.offlineSyncCoordinator = offlineSyncCoordinator
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(serverURL: url, accessToken: token, includeArchived: self.includeArchived)
            }
            self.locations = result
            // Refresh the offline cache only with the unfiltered list to avoid
            // leaking archived items into picker fallbacks.
            if !includeArchived {
                offlineSyncCoordinator.updateLocationCache(result)
            }
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func toggleIncludeArchived(_ include: Bool) {
        includeArchived = include
        Task { await load() }
    }

    func createLocation() async {
        let trimmed = draftLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parentId = draftParent?.id
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await authenticated.perform { url, token in
                try await self.apiClient.createLocation(
                    serverURL: url,
                    accessToken: token,
                    request: LocationCreateRequest(name: trimmed, parentLocationId: parentId)
                )
            }
            locations.append(created)
            draftLocationName = ""
            draftParent = nil
            // Reload so paths and parent references refresh for the new node and its siblings.
            await load()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func selectDraftParent(_ location: LocationResponse?) {
        draftParent = location
    }

    func beginEditing(_ location: LocationResponse) {
        editingLocationID = location.id
        editingName = location.name
    }

    func cancelEditing() {
        editingLocationID = nil
        editingName = ""
    }

    func saveEditing() async {
        guard let id = editingLocationID else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await authenticated.perform { url, token in
                try await self.apiClient.updateLocation(serverURL: url, accessToken: token, locationID: id, request: LocationUpdateRequest(name: trimmed))
            }
            if let idx = locations.firstIndex(where: { $0.id == id }) {
                locations[idx] = updated
            }
            editingLocationID = nil
            editingName = ""
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func archiveLocation(_ location: LocationResponse) async {
        do {
            let archived = try await authenticated.perform { url, token in
                try await self.apiClient.archiveLocation(serverURL: url, accessToken: token, locationID: location.id)
            }
            if let idx = locations.firstIndex(where: { $0.id == archived.id }) {
                if includeArchived {
                    locations[idx] = archived
                } else {
                    locations.remove(at: idx)
                }
            }
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
