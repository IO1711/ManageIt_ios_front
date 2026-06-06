import XCTest
@testable import ManageIt

@MainActor
final class OfflineSyncCoordinatorTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "OfflineSyncCoordinatorTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func makeCoordinator() -> OfflineSyncCoordinator {
        OfflineSyncCoordinator(
            outbox: OfflineMovementOutbox(userDefaults: defaults),
            locationCache: OfflineLocationCache(userDefaults: defaults),
            apiClient: ManageItAPIClient()
        )
    }

    private func internalItem(id: Int64 = 1, locationId: Int64 = 1) -> ItemResponse {
        ItemResponse(
            id: id,
            mainInventoryNumber: "INV-\(id)",
            title: "Item \(id)",
            secondaryInventoryNumbers: [],
            authors: [],
            currentPlacement: ItemPlacement(
                presenceType: .internal,
                location: ItemLocationSummary(id: locationId, name: "Loc \(locationId)", path: nil),
                organization: nil
            ),
            planning: ItemPlanning(promisedOrganization: nil, expectedLeaveDate: nil),
            archived: false,
            currentExhibition: nil
        )
    }

    private func externalItem(plannedOrg: ItemOrganizationSummary? = nil) -> ItemResponse {
        ItemResponse(
            id: 2,
            mainInventoryNumber: "INV-2",
            title: "External item",
            secondaryInventoryNumbers: [],
            authors: [],
            currentPlacement: ItemPlacement(
                presenceType: .external,
                location: nil,
                organization: ItemOrganizationSummary(id: 5, name: "Org")
            ),
            planning: ItemPlanning(promisedOrganization: plannedOrg, expectedLeaveDate: nil),
            archived: false,
            currentExhibition: nil
        )
    }

    private func makeMovementRequest() throws -> ItemMovementCreateRequest {
        ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 8,
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 5, day: 27),
            expectedReturnDate: nil,
            expectedSourcePlacement: nil
        )
    }

    // MARK: - Eligibility matrix

    func testInternalMoveAlwaysEligible() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.isEligible(mode: .internalMove, item: internalItem()))
        XCTAssertTrue(coordinator.isEligible(mode: .internalMove, item: externalItem()))
    }

    func testReturnToInternalAlwaysEligible() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.isEligible(mode: .returnToInternal, item: externalItem()))
    }

    func testExternalRentalEligibleOnlyWithSyncedPlanning() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.isEligible(mode: .externalRental, item: internalItem()))

        let planned = ItemOrganizationSummary(id: 7, name: "Hermitage")
        let withPlanning = ItemResponse(
            id: 3,
            mainInventoryNumber: "INV-3",
            title: "Planned",
            secondaryInventoryNumbers: [],
            authors: [],
            currentPlacement: ItemPlacement(
                presenceType: .internal,
                location: ItemLocationSummary(id: 1, name: "L", path: nil),
                organization: nil
            ),
            planning: ItemPlanning(promisedOrganization: planned, expectedLeaveDate: nil),
            archived: false,
            currentExhibition: nil
        )
        XCTAssertTrue(coordinator.isEligible(mode: .externalRental, item: withPlanning))
    }

    // MARK: - Queue

    func testQueueMovementSuccessReplacesPlacement() throws {
        let coordinator = makeCoordinator()
        coordinator.updateLocationCache([
            LocationResponse(id: 8, name: "Shelf 2", archived: false, parentLocationId: 1, path: "Hall A > Shelf 2", assignable: true)
        ])

        let outcome = coordinator.queueMovement(
            item: internalItem(locationId: 1),
            mode: .internalMove,
            request: try makeMovementRequest()
        )
        guard case .success(let entry) = outcome else { return XCTFail("expected success") }

        XCTAssertEqual(entry.itemId, 1)
        XCTAssertEqual(entry.status, .queued)
        XCTAssertEqual(entry.optimisticItem.currentPlacement.location?.id, 8)
        XCTAssertEqual(entry.optimisticItem.currentPlacement.location?.displayPath, "Hall A > Shelf 2")
        XCTAssertEqual(coordinator.entries.count, 1)
        XCTAssertEqual(coordinator.queuedEntries.count, 1)
    }

    func testQueueMovementWritesExpectedSourcePlacement() throws {
        let coordinator = makeCoordinator()
        let outcome = coordinator.queueMovement(
            item: internalItem(locationId: 4),
            mode: .internalMove,
            request: try makeMovementRequest()
        )
        guard case .success(let entry) = outcome else { return XCTFail() }
        XCTAssertEqual(entry.request.expectedSourcePlacement?.locationId, 4)
        XCTAssertEqual(entry.request.expectedSourcePlacement?.presenceType, .internal)
    }

    func testQueueMovementSecondTimeReturnsAlreadyQueued() throws {
        let coordinator = makeCoordinator()
        _ = coordinator.queueMovement(item: internalItem(), mode: .internalMove, request: try makeMovementRequest())
        let second = coordinator.queueMovement(item: internalItem(), mode: .internalMove, request: try makeMovementRequest())
        guard case .alreadyQueued = second else { return XCTFail("second queue should be rejected") }
    }

    func testQueueMovementExternalRejectedWithoutPlanning() throws {
        let coordinator = makeCoordinator()
        let request = ItemMovementCreateRequest(
            presenceType: .external,
            locationId: nil,
            organization: MovementOrganizationInput(id: 7, name: nil),
            moveInDate: try BusinessDate(year: 2026, month: 5, day: 27),
            expectedReturnDate: nil,
            expectedSourcePlacement: nil
        )
        let outcome = coordinator.queueMovement(
            item: internalItem(),
            mode: .externalRental,
            request: request
        )
        guard case .ineligibleExternal = outcome else { return XCTFail() }
        XCTAssertTrue(coordinator.entries.isEmpty)
    }

    // MARK: - Overlay

    func testOverlayReplacesQueuedItems() throws {
        let coordinator = makeCoordinator()
        coordinator.updateLocationCache([
            LocationResponse(id: 8, name: "Shelf 2", archived: false, parentLocationId: 1, path: "Hall A > Shelf 2", assignable: true)
        ])
        _ = coordinator.queueMovement(
            item: internalItem(id: 1, locationId: 1),
            mode: .internalMove,
            request: try makeMovementRequest()
        )

        let original = internalItem(id: 1, locationId: 1) // server still shows location 1
        let overlaid = coordinator.overlay([original, internalItem(id: 99, locationId: 1)])
        XCTAssertEqual(overlaid[0].currentPlacement.location?.id, 8, "queued item gets optimistic location")
        XCTAssertEqual(overlaid[1].currentPlacement.location?.id, 1, "untouched item stays")
    }

    func testOverlayIgnoresRejectedEntries() throws {
        let coordinator = makeCoordinator()
        _ = coordinator.queueMovement(item: internalItem(id: 1), mode: .internalMove, request: try makeMovementRequest())
        // Manually mark as rejected
        coordinator.entries[0].status = .rejected

        let original = internalItem(id: 1, locationId: 1)
        let overlaid = coordinator.overlay([original])
        XCTAssertEqual(overlaid[0].currentPlacement.location?.id, 1, "rejected entry should not overlay")
    }

    // MARK: - Optimistic history entry

    func testOptimisticHistoryEntryHasNegativeIdAndCorrectPlacement() throws {
        let coordinator = makeCoordinator()
        let outcome = coordinator.queueMovement(
            item: internalItem(),
            mode: .internalMove,
            request: try makeMovementRequest()
        )
        guard case .success(let entry) = outcome else { return XCTFail() }

        let history = coordinator.optimisticHistoryEntry(for: entry)
        XCTAssertLessThan(history.id, 0, "synthetic history rows must use negative ids")
        XCTAssertEqual(history.presenceType, .internal)
        XCTAssertEqual(history.location?.id, 8)
        XCTAssertNil(history.moveOutDate, "queued row stays open")
        XCTAssertNil(history.movedByDevice)
    }

    // MARK: - Discard

    func testDiscardRemovesEntry() throws {
        let coordinator = makeCoordinator()
        guard case .success(let entry) = coordinator.queueMovement(
            item: internalItem(),
            mode: .internalMove,
            request: try makeMovementRequest()
        ) else { return XCTFail() }

        XCTAssertEqual(coordinator.entries.count, 1)
        coordinator.discard(entryId: entry.id)
        XCTAssertTrue(coordinator.entries.isEmpty)
    }

    // MARK: - Persistence

    func testQueuedEntriesPersistAcrossCoordinatorInstances() throws {
        let first = makeCoordinator()
        _ = first.queueMovement(item: internalItem(), mode: .internalMove, request: try makeMovementRequest())

        let second = makeCoordinator()
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries[0].itemId, 1)
    }

    // MARK: - Cache

    func testLocationCacheRoundTripsThroughCoordinator() {
        let coordinator = makeCoordinator()
        let locations = [
            LocationResponse(id: 1, name: "Hall A", archived: false, parentLocationId: nil, path: "Hall A", assignable: false)
        ]
        coordinator.updateLocationCache(locations)

        let restored = makeCoordinator()
        XCTAssertEqual(restored.cachedLocations.count, 1)
        XCTAssertEqual(restored.cachedLocations[0].name, "Hall A")
    }

    // MARK: - Reset

    func testResetForLogoutClearsEverything() throws {
        let coordinator = makeCoordinator()
        _ = coordinator.queueMovement(item: internalItem(), mode: .internalMove, request: try makeMovementRequest())
        coordinator.updateLocationCache([
            LocationResponse(id: 1, name: "X", archived: false, parentLocationId: nil, path: nil, assignable: true)
        ])

        coordinator.resetForLogout()
        XCTAssertTrue(coordinator.entries.isEmpty)
        XCTAssertTrue(coordinator.cachedLocations.isEmpty)

        let reborn = makeCoordinator()
        XCTAssertTrue(reborn.entries.isEmpty, "reset wipes UserDefaults too")
        XCTAssertTrue(reborn.cachedLocations.isEmpty)
    }
}
