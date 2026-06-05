import Foundation
import Observation

@MainActor
@Observable
final class LocationManagementFeatureModel {
    var locations: [LocationResponse] = []
    var includeArchived: Bool = false
    var rootComposerOpen: Bool = false
    var rootDraftLocationName: String = ""
    var openChildParentID: Int64?
    var childDrafts: [Int64: String] = [:]
    var editingLocationID: Int64?
    var editingName: String = ""
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

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

    init(
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
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
    }

    var locationTree: [LocationTreeNode] {
        buildLocationTree(from: locations)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(
                    serverURL: url,
                    accessToken: token,
                    includeArchived: self.includeArchived
                )
            }
            self.locations = sortLocationsByPath(result)
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func toggleIncludeArchived(_ include: Bool) {
        includeArchived = include
        Task { await load() }
    }

    func toggleRootComposer() {
        rootComposerOpen.toggle()
        if rootComposerOpen {
            openChildParentID = nil
        } else {
            rootDraftLocationName = ""
        }
        errorMessage = nil
        successMessage = nil
    }

    func toggleChildComposer(for location: LocationResponse) {
        rootComposerOpen = false
        errorMessage = nil
        successMessage = nil
        if openChildParentID == location.id {
            openChildParentID = nil
            childDrafts[location.id] = ""
        } else {
            openChildParentID = location.id
        }
    }

    func updateChildDraft(parentID: Int64, value: String) {
        childDrafts[parentID] = value
        if errorMessage != nil {
            errorMessage = nil
        }
    }

    func createRootLocation() async {
        await createLocation(
            draftName: rootDraftLocationName,
            parentLocationID: nil,
            successCopy: "Root location added."
        )
    }

    func createChildLocation(parent: LocationResponse) async {
        await createLocation(
            draftName: childDrafts[parent.id] ?? "",
            parentLocationID: parent.id,
            successCopy: "Added a sub-location under \(parent.name)."
        )
    }

    private func createLocation(
        draftName: String,
        parentLocationID: Int64?,
        successCopy: String
    ) async {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = parentLocationID == nil
                ? "A root location name is required."
                : "A sub-location name is required."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            _ = try await authenticated.perform { url, token in
                try await self.apiClient.createLocation(
                    serverURL: url,
                    accessToken: token,
                    request: LocationCreateRequest(
                        name: trimmed,
                        parentLocationId: parentLocationID
                    )
                )
            }
            rootDraftLocationName = ""
            rootComposerOpen = false
            if let parentLocationID {
                childDrafts[parentLocationID] = ""
            }
            openChildParentID = nil
            successMessage = successCopy
            await load()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func beginEditing(_ location: LocationResponse) {
        editingLocationID = location.id
        editingName = location.name
        errorMessage = nil
        successMessage = nil
    }

    func cancelEditing() {
        editingLocationID = nil
        editingName = ""
    }

    func saveEditing() async {
        guard let id = editingLocationID else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Location name cannot be empty."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            _ = try await authenticated.perform { url, token in
                try await self.apiClient.updateLocation(
                    serverURL: url,
                    accessToken: token,
                    locationID: id,
                    request: LocationUpdateRequest(name: trimmed)
                )
            }
            editingLocationID = nil
            editingName = ""
            successMessage = "Location renamed."
            await load()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func archiveLocation(_ location: LocationResponse) async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            _ = try await authenticated.perform { url, token in
                try await self.apiClient.archiveLocation(
                    serverURL: url,
                    accessToken: token,
                    locationID: location.id
                )
            }
            successMessage = "\(location.name) archived."
            await load()
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
