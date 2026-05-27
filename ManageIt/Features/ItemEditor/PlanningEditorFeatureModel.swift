import Foundation
import Observation

@MainActor
@Observable
final class PlanningEditorFeatureModel {
    var itemID: Int64
    var selectedOrganization: OrganizationResponse?
    var organizationQuery: String = ""
    var organizationSuggestions: [OrganizationResponse] = []
    var expectedLeaveDate: BusinessDate?
    var isSaving: Bool = false
    var errorMessage: String?
    var validationMessage: String?
    var saveSucceeded: Bool = false
    var savedItem: ItemResponse?

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
    private var orgSearchTask: Task<Void, Never>?

    init(
        itemID: Int64,
        initialPlanning: ItemPlanning,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.itemID = itemID
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

        if let promised = initialPlanning.promisedOrganization {
            self.selectedOrganization = OrganizationResponse(id: promised.id, name: promised.name, archived: false)
        }
        self.expectedLeaveDate = initialPlanning.expectedLeaveDate
    }

    func searchOrganizations(query: String) {
        organizationQuery = query
        orgSearchTask?.cancel()
        orgSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.performOrganizationSearch(query: query)
        }
    }

    private func performOrganizationSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            organizationSuggestions = []
            return
        }
        do {
            let results = try await authenticated.perform { url, token in
                try await self.apiClient.fetchOrganizations(serverURL: url, accessToken: token, query: query, includeArchived: false)
            }
            self.organizationSuggestions = results
        } catch {
            // suggestion search is non-critical
        }
    }

    func selectOrganization(_ organization: OrganizationResponse) {
        selectedOrganization = organization
        organizationQuery = ""
        organizationSuggestions = []
    }

    func clearOrganization() {
        selectedOrganization = nil
        organizationQuery = ""
        organizationSuggestions = []
    }

    func createOrganization(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let response = try await authenticated.perform { url, token in
                try await self.apiClient.createOrganization(serverURL: url, accessToken: token, request: OrganizationCreateRequest(name: trimmed))
            }
            selectOrganization(response)
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func submit() async {
        validationMessage = nil
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let organization: ItemPlanningOrganizationInput? = {
            if let selected = selectedOrganization {
                return ItemPlanningOrganizationInput(id: selected.id, name: nil)
            }
            return nil
        }()

        let request = ItemPlanningUpdateRequest(
            promisedOrganization: organization,
            expectedLeaveDate: expectedLeaveDate
        )

        do {
            let updated = try await authenticated.perform { url, token in
                try await self.apiClient.updateItemPlanning(serverURL: url, accessToken: token, itemID: self.itemID, request: request)
            }
            savedItem = updated
            saveSucceeded = true
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
