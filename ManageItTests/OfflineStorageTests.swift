import XCTest
@testable import ManageIt

final class OfflineStorageTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "OfflineStorageTests"

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

    // MARK: - OfflineMovementOutbox

    private func makeItem(id: Int64 = 42) -> ItemResponse {
        ItemResponse(
            id: id,
            mainInventoryNumber: "INV-DEMO-\(id)",
            title: "Demo item",
            secondaryInventoryNumbers: [],
            authors: [],
            currentPlacement: ItemPlacement(
                presenceType: .internal,
                location: ItemLocationSummary(id: 1, name: "Shelf 1", path: "Hall > Shelf 1"),
                organization: nil
            ),
            planning: ItemPlanning(promisedOrganization: nil, expectedLeaveDate: nil),
            archived: false,
            currentExhibition: nil
        )
    }

    private func makeRequest() throws -> ItemMovementCreateRequest {
        ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 8,
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 5, day: 27),
            expectedReturnDate: nil,
            expectedSourcePlacement: ExpectedSourcePlacement(
                presenceType: .internal,
                locationId: 1,
                organizationId: nil
            )
        )
    }

    func testOutboxRoundTripsEntries() throws {
        let outbox = OfflineMovementOutbox(userDefaults: defaults)
        let entry = OfflineMovementEntry(
            id: UUID(),
            itemId: 42,
            queuedAt: Date(),
            request: try makeRequest(),
            optimisticItem: makeItem(),
            status: .queued,
            lastError: nil
        )
        outbox.save([entry])

        let restored = outbox.load()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, entry.id)
        XCTAssertEqual(restored[0].itemId, 42)
        XCTAssertEqual(restored[0].status, .queued)
        XCTAssertEqual(restored[0].request.expectedSourcePlacement?.locationId, 1)
    }

    func testOutboxPersistsAcrossInstances() throws {
        let original = OfflineMovementOutbox(userDefaults: defaults)
        let entry = OfflineMovementEntry(
            id: UUID(),
            itemId: 1,
            queuedAt: Date(),
            request: try makeRequest(),
            optimisticItem: makeItem(id: 1),
            status: .rejected,
            lastError: "Stale"
        )
        original.save([entry])

        let reincarnated = OfflineMovementOutbox(userDefaults: defaults)
        let entries = reincarnated.load()
        XCTAssertEqual(entries.first?.status, .rejected)
        XCTAssertEqual(entries.first?.lastError, "Stale")
    }

    func testOutboxClearRemovesData() throws {
        let outbox = OfflineMovementOutbox(userDefaults: defaults)
        outbox.save([
            OfflineMovementEntry(
                id: UUID(),
                itemId: 1,
                queuedAt: Date(),
                request: try makeRequest(),
                optimisticItem: makeItem(id: 1),
                status: .queued,
                lastError: nil
            )
        ])
        XCTAssertEqual(outbox.load().count, 1)
        outbox.clear()
        XCTAssertTrue(outbox.load().isEmpty)
    }

    func testEmptyOutboxLoadIsEmpty() {
        let outbox = OfflineMovementOutbox(userDefaults: defaults)
        XCTAssertTrue(outbox.load().isEmpty)
    }

    // MARK: - OfflineLocationCache

    func testLocationCacheRoundTrips() {
        let cache = OfflineLocationCache(userDefaults: defaults)
        let locations = [
            LocationResponse(id: 1, name: "Hall A", archived: false, parentLocationId: nil, path: "Hall A", assignable: false),
            LocationResponse(id: 2, name: "Shelf 1", archived: false, parentLocationId: 1, path: "Hall A > Shelf 1", assignable: true),
        ]
        cache.save(locations)

        let reloaded = OfflineLocationCache(userDefaults: defaults).load()
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.first(where: { $0.id == 2 })?.displayPath, "Hall A > Shelf 1")
    }

    func testLocationCacheEmptyByDefault() {
        XCTAssertTrue(OfflineLocationCache(userDefaults: defaults).load().isEmpty)
    }

    func testLocationCacheClearWorks() {
        let cache = OfflineLocationCache(userDefaults: defaults)
        cache.save([
            LocationResponse(id: 1, name: "X", archived: false, parentLocationId: nil, path: "X", assignable: true)
        ])
        XCTAssertEqual(cache.load().count, 1)
        cache.clear()
        XCTAssertTrue(cache.load().isEmpty)
    }

    // MARK: - AppPreferences

    func testInventoryQueryCacheRoundTrip() {
        let prefs = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(prefs.loadLastInventoryQuery(), "")
        prefs.saveLastInventoryQuery("mask")
        XCTAssertEqual(prefs.loadLastInventoryQuery(), "mask")
    }

    func testClearAllLocalContextWipes() {
        let prefs = AppPreferences(userDefaults: defaults)
        prefs.serverAddress = "http://demo.manageit.local"
        prefs.saveLastInventoryQuery("mask")

        prefs.clearAllLocalContext()
        XCTAssertEqual(prefs.serverAddress, "")
        XCTAssertEqual(prefs.loadLastInventoryQuery(), "")
        XCTAssertNil(prefs.loadDeviceContext())
    }

    func testDeviceContextRoundTrip() {
        let prefs = AppPreferences(userDefaults: defaults)
        let context = StoredDeviceContext(
            serverAddress: "http://demo.manageit.local",
            deviceId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            role: .admin,
            deviceType: .iosApp,
            friendlyName: "Demo iPhone",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        prefs.saveDeviceContext(context)

        let reloaded = prefs.loadDeviceContext()
        XCTAssertEqual(reloaded?.deviceId, context.deviceId)
        XCTAssertEqual(reloaded?.role, .admin)
        XCTAssertEqual(reloaded?.friendlyName, "Demo iPhone")
    }
}
