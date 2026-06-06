import Foundation
import Observation

/// Coordinates the iPhone's offline movement outbox per architecture block #6.
///
/// Responsibilities:
/// - keep the dedicated persistent outbox in sync with in-memory `entries`
/// - cache the latest location hierarchy so offline forms still have data
/// - apply optimistic overlays to the inventory/detail UI for queued moves
/// - enforce the "one outstanding queued move per item" rule
/// - replay queued moves against the backend when connectivity is restored
@MainActor
@Observable
final class OfflineSyncCoordinator {
    var entries: [OfflineMovementEntry] = []
    var cachedLocations: [LocationResponse] = []
    var isReplaying: Bool = false
    var lastReplayAt: Date?
    var lastReplaySummary: String?

    @ObservationIgnored
    private let outbox: OfflineMovementOutbox

    @ObservationIgnored
    private let locationCache: OfflineLocationCache

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private weak var sessionModel: DeviceSessionModel?

    @ObservationIgnored
    private var currentContext: StoredDeviceContext?

    init(
        outbox: OfflineMovementOutbox,
        locationCache: OfflineLocationCache,
        apiClient: ManageItAPIClient
    ) {
        self.outbox = outbox
        self.locationCache = locationCache
        self.apiClient = apiClient
        self.entries = outbox.load()
        self.cachedLocations = locationCache.load()
    }

    // MARK: - Session attach

    func attachSession(_ session: DeviceSessionModel, context: StoredDeviceContext) {
        self.sessionModel = session
        self.currentContext = context
    }

    func detachSession() {
        sessionModel = nil
        currentContext = nil
    }

    func resetForLogout() {
        entries = []
        outbox.clear()
        cachedLocations = []
        locationCache.clear()
        lastReplayAt = nil
        lastReplaySummary = nil
    }

    // MARK: - Cache writes

    func updateLocationCache(_ locations: [LocationResponse]) {
        cachedLocations = locations
        locationCache.save(locations)
    }

    // MARK: - Lookup

    func entry(for itemId: Int64) -> OfflineMovementEntry? {
        entries.first(where: { $0.itemId == itemId })
    }

    var hasQueuedMoves: Bool {
        entries.contains(where: { $0.status != .rejected })
    }

    var rejectedEntries: [OfflineMovementEntry] {
        entries.filter { $0.status == .rejected }
    }

    var queuedEntries: [OfflineMovementEntry] {
        entries.filter { $0.status != .rejected }
    }

    // MARK: - Queue / discard

    enum QueueOutcome {
        case success(OfflineMovementEntry)
        case alreadyQueued
        case ineligibleExternal
    }

    /// Returns true if the given movement is offline-eligible for `item`.
    func isEligible(mode: MovementEntryMode, item: ItemResponse) -> Bool {
        switch mode {
        case .internalMove, .returnToInternal:
            return true
        case .externalRental:
            // External rentals offline-only when planning data is already synced.
            return item.planning.promisedOrganization != nil
        }
    }

    func queueMovement(
        item: ItemResponse,
        mode: MovementEntryMode,
        request rawRequest: ItemMovementCreateRequest
    ) -> QueueOutcome {
        // One outstanding per item — drop only if not yet rejected.
        if let existing = entries.first(where: { $0.itemId == item.id }), existing.status != .rejected {
            return .alreadyQueued
        }
        if !isEligible(mode: mode, item: item) {
            return .ineligibleExternal
        }

        let expectedSource = ExpectedSourcePlacement(placement: item.currentPlacement)
        let augmented = ItemMovementCreateRequest(
            presenceType: rawRequest.presenceType,
            locationId: rawRequest.locationId,
            organization: rawRequest.organization,
            moveInDate: rawRequest.moveInDate,
            expectedReturnDate: rawRequest.expectedReturnDate,
            expectedSourcePlacement: expectedSource
        )

        let optimistic = applyOptimisticPlacement(to: item, request: rawRequest)
        let entry = OfflineMovementEntry(
            id: UUID(),
            itemId: item.id,
            queuedAt: Date(),
            request: augmented,
            optimisticItem: optimistic,
            status: .queued,
            lastError: nil
        )
        entries.removeAll { $0.itemId == item.id }
        entries.append(entry)
        outbox.save(entries)
        return .success(entry)
    }

    func discard(entryId: UUID) {
        entries.removeAll { $0.id == entryId }
        outbox.save(entries)
    }

    // MARK: - Optimistic overlay

    /// Overlays optimistic placement for every item in the given list that
    /// has an outstanding (not rejected) queued movement.
    func overlay(_ items: [ItemResponse]) -> [ItemResponse] {
        items.map { item in
            if let entry = entries.first(where: { $0.itemId == item.id && $0.status != .rejected }) {
                return entry.optimisticItem
            }
            return item
        }
    }

    func overlay(_ item: ItemResponse) -> ItemResponse {
        if let entry = entries.first(where: { $0.itemId == item.id && $0.status != .rejected }) {
            return entry.optimisticItem
        }
        return item
    }

    /// Builds a synthetic `ItemHistoryEntry` for an outstanding queued movement
    /// so the History UI can show the in-flight row.
    func optimisticHistoryEntry(for entry: OfflineMovementEntry) -> ItemHistoryEntry {
        // Negative IDs guarantee no collision with backend rows.
        let syntheticId = -Int64(abs(entry.id.uuidString.hashValue) % Int(Int32.max))

        let location: ItemLocationSummary? = {
            guard entry.request.presenceType == .internal,
                  let lid = entry.request.locationId else { return nil }
            if let cached = cachedLocations.first(where: { $0.id == lid }) {
                return ItemLocationSummary(id: cached.id, name: cached.name, path: cached.path)
            }
            return ItemLocationSummary(id: lid, name: "Location \(lid)", path: nil)
        }()
        let organization: ItemOrganizationSummary? = {
            guard entry.request.presenceType == .external,
                  let oid = entry.request.organization?.id else { return nil }
            return ItemOrganizationSummary(id: oid, name: entry.request.organization?.name ?? "Organization \(oid)")
        }()

        return ItemHistoryEntry(
            id: syntheticId,
            presenceType: entry.request.presenceType,
            location: location,
            organization: organization,
            moveInDate: entry.request.moveInDate,
            expectedReturnDate: entry.request.expectedReturnDate,
            moveOutDate: nil,
            movedByDevice: nil
        )
    }

    // MARK: - Replay

    @discardableResult
    func replay() async -> ReplaySummary {
        guard let session = sessionModel, let context = currentContext else {
            return ReplaySummary(succeeded: 0, rejected: 0, stillOffline: entries.count)
        }
        let pendingEntries = entries.filter { $0.status != .rejected }
        guard !pendingEntries.isEmpty else {
            lastReplayAt = Date()
            let summary = ReplaySummary(succeeded: 0, rejected: rejectedEntries.count, stillOffline: 0)
            lastReplaySummary = summary.shortDescription
            return summary
        }

        isReplaying = true
        defer { isReplaying = false }

        var succeeded = 0
        var rejected = 0
        var stillOffline = 0
        var nextEntries: [OfflineMovementEntry] = entries

        for entry in pendingEntries {
            guard let idx = nextEntries.firstIndex(where: { $0.id == entry.id }) else { continue }
            nextEntries[idx].status = .syncing
            nextEntries[idx].lastError = nil

            do {
                let serverURL = try context.serverURL()
                let token = try await session.ensureValidAccessToken(storedContext: context)
                _ = try await apiClient.createMovement(
                    serverURL: serverURL,
                    accessToken: token,
                    itemID: entry.itemId,
                    request: entry.request
                )
                // success — drop entry
                nextEntries.removeAll { $0.id == entry.id }
                succeeded += 1
            } catch let error as ManageItError {
                switch error {
                case .transportFailure:
                    // still offline — leave queued
                    nextEntries[idx].status = .queued
                    stillOffline += 1
                default:
                    nextEntries[idx].status = .rejected
                    nextEntries[idx].lastError = error.errorDescription
                    rejected += 1
                }
            } catch {
                nextEntries[idx].status = .queued
                stillOffline += 1
            }
        }

        entries = nextEntries
        outbox.save(entries)
        lastReplayAt = Date()
        let summary = ReplaySummary(succeeded: succeeded, rejected: rejected, stillOffline: stillOffline)
        lastReplaySummary = summary.shortDescription
        return summary
    }

    // MARK: - Helpers

    private func applyOptimisticPlacement(
        to item: ItemResponse,
        request: ItemMovementCreateRequest
    ) -> ItemResponse {
        let placement: ItemPlacement
        switch request.presenceType {
        case .internal:
            let location: ItemLocationSummary? = {
                guard let lid = request.locationId else { return nil }
                if let cached = cachedLocations.first(where: { $0.id == lid }) {
                    return ItemLocationSummary(id: cached.id, name: cached.name, path: cached.path)
                }
                return ItemLocationSummary(id: lid, name: "Location \(lid)", path: nil)
            }()
            placement = ItemPlacement(presenceType: .internal, location: location, organization: nil)
        case .external:
            let org: ItemOrganizationSummary? = {
                guard let oid = request.organization?.id else { return nil }
                return ItemOrganizationSummary(id: oid, name: request.organization?.name ?? "Organization \(oid)")
            }()
            placement = ItemPlacement(presenceType: .external, location: nil, organization: org)
        }

        // External rentals clear planning data per business rules.
        let planning = request.presenceType == .external
            ? ItemPlanning(promisedOrganization: nil, expectedLeaveDate: nil)
            : item.planning

        return ItemResponse(
            id: item.id,
            mainInventoryNumber: item.mainInventoryNumber,
            title: item.title,
            secondaryInventoryNumbers: item.secondaryInventoryNumbers,
            authors: item.authors,
            currentPlacement: placement,
            planning: planning,
            archived: item.archived
        )
    }
}

struct ReplaySummary {
    let succeeded: Int
    let rejected: Int
    let stillOffline: Int

    var shortDescription: String {
        var parts: [String] = []
        if succeeded > 0 { parts.append("\(succeeded) synced") }
        if rejected > 0 { parts.append("\(rejected) rejected") }
        if stillOffline > 0 { parts.append("\(stillOffline) still offline") }
        if parts.isEmpty { parts.append("nothing to sync") }
        return parts.joined(separator: " • ")
    }
}
