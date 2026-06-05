import Foundation

enum OfflineMovementEntryStatus: String, Codable, Equatable {
    case queued
    case rejected
}

struct OfflineMovementStatusPresentation: Equatable {
    let text: String
    let kind: StatusTag.Kind
    let message: String
    let canDismiss: Bool
}

struct OfflineMovementOutboxEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let itemId: Int64
    let itemTitle: String
    let itemMainInventoryNumber: String
    let localHistoryEntryId: Int64
    let queuedAt: Date
    let request: ItemMovementCreateRequest
    let sourceLocation: ItemLocationSummary?
    let sourceOrganization: ItemOrganizationSummary?
    let sourceExpectedReturnDate: BusinessDate?
    let targetLocation: ItemLocationSummary?
    let targetOrganization: ItemOrganizationSummary?
    let actorDevice: MovedByDeviceSummary
    var status: OfflineMovementEntryStatus
    var rejectionCode: String?
    var rejectionMessage: String?

    var itemPlacement: ItemPlacement {
        ItemPlacement(
            presenceType: request.presenceType,
            location: targetLocation,
            organization: targetOrganization,
            expectedReturnDate: request.expectedReturnDate
        )
    }

    var optimisticPlanning: ItemPlanning? {
        guard request.presenceType == .external else { return nil }
        return ItemPlanning(promisedOrganization: nil, expectedLeaveDate: nil)
    }
}

extension Notification.Name {
    static let offlineMovementStoreDidChange = Notification.Name("OfflineMovementStore.didChange")
    static let offlineMovementServerSnapshotDidChange = Notification.Name("OfflineMovementStore.serverSnapshotDidChange")
}

enum OfflineMovementNotificationKey {
    static let itemId = "itemId"
    static let item = "item"
    static let history = "history"
}

@MainActor
final class OfflineMovementStore {
    private let preferences: AppPreferences
    private var outbox: [OfflineMovementOutboxEntry]
    private var cachedLocations: [LocationResponse]
    private var isSyncing = false

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.outbox = preferences.loadOfflineMovementOutbox()
        self.cachedLocations = preferences.loadCachedLocations()
    }

    func clearAll() {
        outbox = []
        cachedLocations = []
        persist()
        postDidChange()
    }

    func updateCachedLocations(_ locations: [LocationResponse]) {
        cachedLocations = sortLocationsByPath(locations)
        preferences.saveCachedLocations(cachedLocations)
        postDidChange()
    }

    func cachedAssignableLocations() -> [LocationResponse] {
        assignableLocations(from: cachedLocations)
    }

    func cachedLocation(by id: Int64) -> LocationResponse? {
        cachedLocations.first(where: { $0.id == id })
    }

    func statusPresentation(for itemId: Int64) -> OfflineMovementStatusPresentation? {
        guard let entry = outboxEntry(for: itemId) else {
            return nil
        }

        switch entry.status {
        case .queued:
            return OfflineMovementStatusPresentation(
                text: "Queued sync",
                kind: .planned,
                message: "Saved locally on this iPhone. ManageIt will replay this movement when the museum server is reachable again.",
                canDismiss: false
            )
        case .rejected:
            return OfflineMovementStatusPresentation(
                text: "Sync rejected",
                kind: .rejected,
                message: entry.rejectionMessage ?? "This offline movement was rejected during replay and needs review before you create another one.",
                canDismiss: true
            )
        }
    }

    func applyOverlay(to item: ItemResponse) -> ItemResponse {
        guard let entry = outboxEntry(for: item.id), entry.status == .queued else {
            return item
        }

        return ItemResponse(
            id: item.id,
            mainInventoryNumber: item.mainInventoryNumber,
            title: item.title,
            secondaryInventoryNumbers: item.secondaryInventoryNumbers,
            authors: item.authors,
            currentPlacement: entry.itemPlacement,
            planning: entry.optimisticPlanning ?? item.planning,
            archived: item.archived
        )
    }

    func applyOverlay(to history: [ItemHistoryEntry], itemId: Int64) -> [ItemHistoryEntry] {
        guard let entry = outboxEntry(for: itemId) else {
            return history
        }

        var rows = history
        let localRow = makeLocalHistoryEntry(from: entry)

        switch entry.status {
        case .queued:
            if let openIndex = rows.lastIndex(where: { $0.isOpen && $0.localSyncState == nil }) {
                rows[openIndex] = rows[openIndex].closing(at: entry.request.moveInDate)
            }
        case .rejected:
            break
        }

        rows.removeAll { $0.id == localRow.id }
        rows.append(localRow)
        return rows.sorted { lhs, rhs in
            if lhs.moveInDate != rhs.moveInDate {
                return lhs.moveInDate < rhs.moveInDate
            }
            return lhs.id < rhs.id
        }
    }

    func queueOfflineMovement(
        item: ItemResponse,
        request: ItemMovementCreateRequest,
        storedContext: StoredDeviceContext,
        availableLocations: [LocationResponse]
    ) throws {
        if hasUnsynchronizedMovement(for: item.id) {
            throw ManageItError.validationError(
                "This item already has an offline movement waiting for sync or review."
            )
        }

        if request.presenceType == .external {
            guard let promisedOrganization = item.planning.promisedOrganization else {
                throw ManageItError.validationError(
                    "Offline send-to-external is allowed only when the item already has synced planning data."
                )
            }

            let queuedOrganizationID = request.organization?.id
            if queuedOrganizationID != promisedOrganization.id {
                throw ManageItError.validationError(
                    "Offline send-to-external must use the synced planned organization."
                )
            }
        }

        let expectedSourcePlacement = expectedSourcePlacement(for: item.currentPlacement)
        let targetLocation = request.locationId
            .flatMap { locationID in
                availableLocations.first(where: { $0.id == locationID }) ?? cachedLocation(by: locationID)
            }
            .map(Self.itemLocationSummary)
        let targetOrganization = targetOrganizationSummary(for: item, request: request)

        if request.presenceType == .internal && targetLocation == nil {
            throw ManageItError.validationError(
                "The selected destination location is not available in this iPhone's cached hierarchy."
            )
        }
        if request.presenceType == .external && targetOrganization == nil {
            throw ManageItError.validationError(
                "The receiving organization is not available for offline replay."
            )
        }

        let queuedRequest = ItemMovementCreateRequest(
            presenceType: request.presenceType,
            locationId: request.locationId,
            organization: request.organization,
            moveInDate: request.moveInDate,
            expectedReturnDate: request.expectedReturnDate,
            expectedSourcePlacement: expectedSourcePlacement
        )

        let entry = OfflineMovementOutboxEntry(
            id: UUID(),
            itemId: item.id,
            itemTitle: item.title,
            itemMainInventoryNumber: item.mainInventoryNumber,
            localHistoryEntryId: -Int64(Date().timeIntervalSince1970 * 1_000_000),
            queuedAt: Date(),
            request: queuedRequest,
            sourceLocation: item.currentPlacement.location,
            sourceOrganization: item.currentPlacement.organization,
            sourceExpectedReturnDate: item.currentPlacement.expectedReturnDate,
            targetLocation: targetLocation,
            targetOrganization: targetOrganization,
            actorDevice: MovedByDeviceSummary(
                id: storedContext.deviceId,
                friendlyName: storedContext.friendlyName,
                deviceType: storedContext.deviceType
            ),
            status: .queued,
            rejectionCode: nil,
            rejectionMessage: nil
        )

        outbox.append(entry)
        persist()
        postDidChange()
    }

    func dismissRejectedEntry(for itemId: Int64) {
        guard let index = outbox.firstIndex(where: { $0.itemId == itemId && $0.status == .rejected }) else {
            return
        }
        outbox.remove(at: index)
        persist()
        postDidChange()
    }

    func syncQueuedMovements(
        authenticated: AuthenticatedAPI,
        apiClient: ManageItAPIClient
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        while let entry = outbox.first(where: { $0.status == .queued }) {
            do {
                _ = try await authenticated.perform { url, token in
                    try await apiClient.createMovement(
                        serverURL: url,
                        accessToken: token,
                        itemID: entry.itemId,
                        request: entry.request
                    )
                }

                removeEntry(id: entry.id)
                await refreshServerSnapshot(for: entry.itemId, authenticated: authenticated, apiClient: apiClient)
            } catch let error as ManageItError {
                if error.isTransportFailure {
                    return
                }

                if AuthenticatedAPI.isFatalAuth(error) {
                    return
                }

                markRejected(entryID: entry.id, from: error)
                await refreshServerSnapshot(for: entry.itemId, authenticated: authenticated, apiClient: apiClient)
            } catch {
                return
            }
        }
    }

    func hasUnsynchronizedMovement(for itemId: Int64) -> Bool {
        outboxEntry(for: itemId) != nil
    }

    private func outboxEntry(for itemId: Int64) -> OfflineMovementOutboxEntry? {
        outbox.last(where: { $0.itemId == itemId })
    }

    private func removeEntry(id: UUID) {
        outbox.removeAll { $0.id == id }
        persist()
        postDidChange()
    }

    private func markRejected(entryID: UUID, from error: ManageItError) {
        guard let index = outbox.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        outbox[index].status = .rejected

        switch error {
        case .backend(let code, let message):
            outbox[index].rejectionCode = code
            if code == "OFFLINE_MOVEMENT_STALE_SOURCE" {
                outbox[index].rejectionMessage = "Sync was rejected because the item's current server placement changed on another device before this iPhone replayed the queued move."
            } else {
                outbox[index].rejectionMessage = message
            }
        default:
            outbox[index].rejectionCode = nil
            outbox[index].rejectionMessage = AuthenticatedAPI.userFacing(error)
        }

        persist()
        postDidChange()
    }

    private func refreshServerSnapshot(
        for itemId: Int64,
        authenticated: AuthenticatedAPI,
        apiClient: ManageItAPIClient
    ) async {
        do {
            let item = try await authenticated.perform { url, token in
                try await apiClient.fetchItem(serverURL: url, accessToken: token, itemID: itemId)
            }
            let history = try await authenticated.perform { url, token in
                try await apiClient.fetchItemHistory(serverURL: url, accessToken: token, itemID: itemId)
            }
            NotificationCenter.default.post(
                name: .offlineMovementServerSnapshotDidChange,
                object: self,
                userInfo: [
                    OfflineMovementNotificationKey.itemId: itemId,
                    OfflineMovementNotificationKey.item: item,
                    OfflineMovementNotificationKey.history: history
                ]
            )
        } catch {
            // Keep the outbox state even if the follow-up refresh cannot complete.
        }
    }

    private func persist() {
        preferences.saveOfflineMovementOutbox(outbox)
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: .offlineMovementStoreDidChange, object: self)
    }

    private func expectedSourcePlacement(for placement: ItemPlacement) -> MovementExpectedSourcePlacementInput {
        MovementExpectedSourcePlacementInput(
            presenceType: placement.presenceType,
            locationId: placement.location?.id,
            organizationId: placement.organization?.id
        )
    }

    private func targetOrganizationSummary(
        for item: ItemResponse,
        request: ItemMovementCreateRequest
    ) -> ItemOrganizationSummary? {
        guard request.presenceType == .external else {
            return nil
        }

        if let promised = item.planning.promisedOrganization,
           promised.id == request.organization?.id {
            return promised
        }

        guard let organization = request.organization else {
            return nil
        }

        if let id = organization.id {
            return ItemOrganizationSummary(id: id, name: organization.name ?? "External organization")
        }

        guard let name = organization.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }

        return ItemOrganizationSummary(id: -1, name: name)
    }

    private func makeLocalHistoryEntry(from entry: OfflineMovementOutboxEntry) -> ItemHistoryEntry {
        ItemHistoryEntry(
            id: entry.localHistoryEntryId,
            presenceType: entry.request.presenceType,
            location: entry.targetLocation,
            organization: entry.targetOrganization,
            moveInDate: entry.request.moveInDate,
            expectedReturnDate: entry.request.expectedReturnDate,
            moveOutDate: nil,
            movedByDevice: entry.actorDevice,
            createdAt: entry.queuedAt,
            localSyncState: entry.status == .queued ? .queued : .rejected,
            localSyncMessage: entry.rejectionMessage
        )
    }

    private static func itemLocationSummary(from location: LocationResponse) -> ItemLocationSummary {
        ItemLocationSummary(id: location.id, name: location.name, fullPath: location.fullPath)
    }
}
