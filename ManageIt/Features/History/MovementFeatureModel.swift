import Foundation
import Observation

@MainActor
@Observable
final class MovementFeatureModel {
    var itemID: Int64
    var mode: MovementEntryMode
    var selectedLocationID: Int64?
    var availableLocations: [LocationResponse] = []
    var selectedOrganization: OrganizationResponse?
    var organizationQuery: String = ""
    var organizationSuggestions: [OrganizationResponse] = []
    var moveInDate: BusinessDate? = .today
    var expectedReturnDate: BusinessDate?
    var isSaving: Bool = false
    var isLoading: Bool = false
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
        currentPresence: ItemPresenceType,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.itemID = itemID
        self.mode = currentPresence == .external ? .returnToInternal : .internalMove
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

    func loadDependencies() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let locations = try await authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(serverURL: url, accessToken: token, includeArchived: false)
            }
            self.availableLocations = locations
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func setMode(_ newMode: MovementEntryMode) {
        mode = newMode
        if newMode.requiresLocation {
            selectedOrganization = nil
            organizationQuery = ""
            organizationSuggestions = []
            expectedReturnDate = nil
        } else {
            selectedLocationID = nil
        }
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
            // ignore
        }
    }

    func selectOrganization(_ organization: OrganizationResponse) {
        selectedOrganization = organization
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

        guard let date = moveInDate else {
            validationMessage = "Movement date is required."
            return
        }

        let presenceType: ItemPresenceType
        let locationId: Int64?
        let organization: MovementOrganizationInput?

        switch mode {
        case .internalMove, .returnToInternal:
            guard let locationID = selectedLocationID else {
                validationMessage = "Choose a destination location."
                return
            }
            presenceType = .internal
            locationId = locationID
            organization = nil
        case .externalRental:
            guard let selectedOrg = selectedOrganization else {
                validationMessage = "Choose or create the receiving organization."
                return
            }
            presenceType = .external
            locationId = nil
            organization = MovementOrganizationInput(id: selectedOrg.id, name: nil)
        }

        let request = ItemMovementCreateRequest(
            presenceType: presenceType,
            locationId: locationId,
            organization: organization,
            moveInDate: date,
            expectedReturnDate: mode == .externalRental ? expectedReturnDate : nil
        )

        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await authenticated.perform { url, token in
                try await self.apiClient.createMovement(serverURL: url, accessToken: token, itemID: self.itemID, request: request)
            }
            savedItem = updated
            saveSucceeded = true
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }
}
