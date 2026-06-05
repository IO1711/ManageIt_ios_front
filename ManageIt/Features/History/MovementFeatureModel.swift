import Foundation
import Observation

@MainActor
@Observable
final class MovementFeatureModel {
    let itemID: Int64
    let currentItem: ItemResponse

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
    var isUsingCachedLocations: Bool = false

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
    private let onReminderSourcesChanged: () -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    @ObservationIgnored
    private var orgSearchTask: Task<Void, Never>?

    init(
        currentItem: ItemResponse,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        offlineMovementStore: OfflineMovementStore,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onReminderSourcesChanged: @escaping () -> Void
    ) {
        self.itemID = currentItem.id
        self.currentItem = currentItem
        self.mode = currentItem.currentPlacement.presenceType == .external ? .returnToInternal : .internalMove
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.offlineMovementStore = offlineMovementStore
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
    }

    var offlineGuidanceMessage: String? {
        guard isUsingCachedLocations else { return nil }
        return "Using the last cached location hierarchy. Eligible moves will queue on this iPhone until the museum server is reachable again."
    }

    var offlineExternalGuidanceMessage: String? {
        guard mode == .externalRental, isUsingCachedLocations else { return nil }
        guard let promised = currentItem.planning.promisedOrganization else {
            return "Offline send-to-external is unavailable because this item has no synced planned organization yet."
        }
        return "Offline send-to-external uses the synced planned organization: \(promised.name)."
    }

    var usesOfflinePlannedOrganizationOnly: Bool {
        mode == .externalRental && isUsingCachedLocations
    }

    func loadDependencies() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let locations = try await authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(serverURL: url, accessToken: token, includeArchived: false)
            }
            offlineMovementStore.updateCachedLocations(locations)
            availableLocations = assignableLocations(from: locations)
            isUsingCachedLocations = false
        } catch let error as ManageItError {
            if error.isTransportFailure {
                let cachedLocations = offlineMovementStore.cachedAssignableLocations()
                if !cachedLocations.isEmpty {
                    availableLocations = cachedLocations
                    isUsingCachedLocations = true
                    prepareOfflineOrganizationIfNeeded()
                    return
                }

                errorMessage = """
                \(AuthenticatedAPI.userFacing(error))

                No cached location hierarchy is available on this iPhone yet, so offline movement cannot start.
                """
                return
            }

            errorMessage = AuthenticatedAPI.userFacing(error)
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
            prepareOfflineOrganizationIfNeeded()
        }
    }

    func searchOrganizations(query: String) {
        organizationQuery = query

        if usesOfflinePlannedOrganizationOnly {
            organizationSuggestions = []
            return
        }

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
            organizationSuggestions = results
        } catch {
            // Keep the last successful suggestions instead of surfacing noisy transient errors.
        }
    }

    func selectOrganization(_ organization: OrganizationResponse) {
        selectedOrganization = organization
        organizationQuery = ""
        organizationSuggestions = []
    }

    func createOrganization(name: String) async {
        if usesOfflinePlannedOrganizationOnly {
            errorMessage = "Offline send-to-external cannot create or search organizations. Use the synced planned organization once connectivity returns."
            return
        }

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
            if usesOfflinePlannedOrganizationOnly && currentItem.planning.promisedOrganization == nil {
                validationMessage = "Offline send-to-external is allowed only when this item already has synced planning data."
                return
            }
            guard let selectedOrg = selectedOrganization else {
                validationMessage = "Choose the receiving organization."
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
            expectedReturnDate: mode == .externalRental ? expectedReturnDate : nil,
            expectedSourcePlacement: nil
        )

        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await authenticated.perform { url, token in
                try await self.apiClient.createMovement(serverURL: url, accessToken: token, itemID: self.itemID, request: request)
            }
            savedItem = updated
            saveSucceeded = true
            onReminderSourcesChanged()
        } catch let error as ManageItError {
            if error.isTransportFailure {
                do {
                    try offlineMovementStore.queueOfflineMovement(
                        item: currentItem,
                        request: request,
                        storedContext: authenticated.currentContext(),
                        availableLocations: availableLocations
                    )
                    savedItem = currentItem
                    saveSucceeded = true
                    return
                } catch {
                    errorMessage = AuthenticatedAPI.userFacing(error)
                    return
                }
            }

            errorMessage = AuthenticatedAPI.userFacing(error)
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    private func prepareOfflineOrganizationIfNeeded() {
        guard usesOfflinePlannedOrganizationOnly else { return }
        organizationQuery = ""
        organizationSuggestions = []

        if let promised = currentItem.planning.promisedOrganization {
            selectedOrganization = OrganizationResponse(
                id: promised.id,
                name: promised.name,
                archived: false
            )
        } else {
            selectedOrganization = nil
        }
    }
}
