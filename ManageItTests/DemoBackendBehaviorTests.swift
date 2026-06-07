import XCTest
@testable import ManageIt

/// End-to-end tests that drive the DemoAPIProtocol to verify the backend
/// business rules (leaf-only placement, archived reservation, overlap, stale
/// replay) actually hold from the iOS client's perspective.
@MainActor
final class DemoBackendBehaviorTests: XCTestCase {

    private let serverURL = URL(string: "http://demo.manageit.local")!
    private var accessToken: String = ""

    override func setUp() async throws {
        DemoAPIProtocol.simulateOffline = false
        DemoAPIProtocol.enable()

        // refresh a session so we have an access token
        let refresh = try await client().refreshDeviceSession(
            serverURL: serverURL,
            request: DeviceTokenRefreshRequest(refreshToken: "demo")
        )
        accessToken = refresh.accessToken
    }

    private func client() -> ManageItAPIClient {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [DemoAPIProtocol.self]
        let session = URLSession(configuration: configuration)
        return ManageItAPIClient(urlSession: session)
    }

    // MARK: - Leaf-only enforcement

    func testCreateItemRejectsNonLeafLocation() async throws {
        // location 1 = "Hall A" has children → not a leaf
        let request = ItemCreateRequest(
            mainInventoryNumber: "INV-TEST-001",
            title: "Should fail",
            secondaryInventoryNumbers: [],
            authors: [ItemAuthorInput(id: 1, name: nil)],
            initialLocationId: 1,
            moveInDate: try BusinessDate(year: 2026, month: 5, day: 27)
        )
        do {
            _ = try await client().createItem(serverURL: serverURL, accessToken: accessToken, request: request)
            XCTFail("non-leaf placement should be rejected")
        } catch let error as ManageItError {
            guard case let .backend(code, _) = error else {
                return XCTFail("expected backend error, got \(error)")
            }
            XCTAssertEqual(code, "NON_LEAF_LOCATION")
        }
    }

    func testCreateItemAcceptsLeafLocation() async throws {
        // location 4 = "Gallery 2" is a root leaf
        let request = ItemCreateRequest(
            mainInventoryNumber: "INV-TEST-LEAF-\(UUID().uuidString.prefix(6))",
            title: "Should succeed",
            secondaryInventoryNumbers: [],
            authors: [ItemAuthorInput(id: 1, name: nil)],
            initialLocationId: 4,
            moveInDate: try BusinessDate(year: 2026, month: 5, day: 27)
        )
        let created = try await client().createItem(serverURL: serverURL, accessToken: accessToken, request: request)
        XCTAssertEqual(created.currentPlacement.location?.id, 4)
    }

    func testMoveToNonLeafLocationRejected() async throws {
        let request = ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 1, // Hall A, not leaf
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 6, day: 1),
            expectedReturnDate: nil,
            expectedSourcePlacement: nil
        )
        do {
            _ = try await client().createMovement(serverURL: serverURL, accessToken: accessToken, itemID: 1, request: request)
            XCTFail()
        } catch let error as ManageItError {
            guard case let .backend(code, _) = error else { return XCTFail() }
            XCTAssertEqual(code, "NON_LEAF_LOCATION")
        }
    }

    // MARK: - Archived items rule 7

    func testArchivedItemMainNumberStillConflicts() async throws {
        // Item id 7 is seeded as archived with inventory number INV-2025-099.
        let response = try await client().checkMainInventoryNumberConflict(
            serverURL: serverURL,
            accessToken: accessToken,
            mainInventoryNumber: "INV-2025-099"
        )
        XCTAssertFalse(response.available, "archived items must still reserve the number")
        XCTAssertEqual(response.conflictingItem?.id, 7)
    }

    func testUnusedNumberIsAvailable() async throws {
        let response = try await client().checkMainInventoryNumberConflict(
            serverURL: serverURL,
            accessToken: accessToken,
            mainInventoryNumber: "INV-DOES-NOT-EXIST-\(UUID().uuidString)"
        )
        XCTAssertTrue(response.available)
        XCTAssertNil(response.conflictingItem)
    }

    // MARK: - Exhibition overlap

    func testCreateExhibitionWithOverlappingItemRejected() async throws {
        // Seeded exhibition id=1 covers item 3 in 2026-05 → 2026-07.
        // Try to create another covering item 3 in 2026-06.
        let overlap = ExhibitionCreateRequest(
            name: "Overlap test",
            locationId: 8, // Shelf 1 (where item 3 lives)
            startDate: try BusinessDate(year: 2026, month: 6, day: 1),
            endDate: try BusinessDate(year: 2026, month: 6, day: 30),
            itemIds: [3]
        )
        do {
            _ = try await client().createExhibition(serverURL: serverURL, accessToken: accessToken, request: overlap)
            XCTFail("overlap should be rejected")
        } catch let error as ManageItError {
            guard case let .backend(code, _) = error else { return XCTFail() }
            XCTAssertEqual(code, "ITEM_EXHIBITION_OVERLAP")
        }
    }

    func testCreateExhibitionRequiresLeafLocation() async throws {
        let request = ExhibitionCreateRequest(
            name: "Bad location",
            locationId: 1, // Hall A, not leaf
            startDate: try BusinessDate(year: 2027, month: 1, day: 1),
            endDate: try BusinessDate(year: 2027, month: 1, day: 31),
            itemIds: [1]
        )
        do {
            _ = try await client().createExhibition(serverURL: serverURL, accessToken: accessToken, request: request)
            XCTFail()
        } catch let error as ManageItError {
            guard case let .backend(code, _) = error else { return XCTFail() }
            XCTAssertEqual(code, "NON_LEAF_LOCATION")
        }
    }

    func testCreateExhibitionStartAfterEndRejected() async throws {
        let request = ExhibitionCreateRequest(
            name: "Backwards",
            locationId: 4,
            startDate: try BusinessDate(year: 2027, month: 5, day: 1),
            endDate: try BusinessDate(year: 2027, month: 4, day: 1),
            itemIds: [1]
        )
        do {
            _ = try await client().createExhibition(serverURL: serverURL, accessToken: accessToken, request: request)
            XCTFail()
        } catch let error as ManageItError {
            guard case let .backend(code, _) = error else { return XCTFail() }
            XCTAssertEqual(code, "VALIDATION_ERROR")
        }
    }

    // MARK: - Item history includes movedByDevice

    func testItemHistoryIncludesMovedByDevice() async throws {
        let entries = try await client().fetchItemHistory(serverURL: serverURL, accessToken: accessToken, itemID: 1)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertNotNil(entries.first?.movedByDevice?.friendlyName)
    }

    // MARK: - Stale offline replay rejection

    func testStaleReplayProducesStaleEnvelope() async throws {
        // Build a replay that claims the item used to be at the wrong location.
        let request = ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 9,
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 6, day: 1),
            expectedReturnDate: nil,
            expectedSourcePlacement: ExpectedSourcePlacement(
                presenceType: .internal,
                locationId: 999, // wrong source
                organizationId: nil
            )
        )
        do {
            _ = try await client().createMovement(serverURL: serverURL, accessToken: accessToken, itemID: 1, request: request)
            XCTFail("stale replay should be rejected")
        } catch let error as ManageItError {
            guard case let .backend(code, _) = error else { return XCTFail() }
            XCTAssertEqual(code, "STALE_OFFLINE_MOVEMENT")
        }
    }

    func testReplayWithCorrectSourceSucceeds() async throws {
        // Item id 1 currently sits at location 4.
        let request = ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 7, // leaf
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 7, day: 1),
            expectedReturnDate: nil,
            expectedSourcePlacement: ExpectedSourcePlacement(
                presenceType: .internal,
                locationId: 4,
                organizationId: nil
            )
        )
        let updated = try await client().createMovement(serverURL: serverURL, accessToken: accessToken, itemID: 1, request: request)
        XCTAssertEqual(updated.currentPlacement.location?.id, 7)
    }

    // MARK: - simulateOffline toggle

    func testSimulateOfflineFailsMovementWithTransportError() async throws {
        DemoAPIProtocol.simulateOffline = true
        defer { DemoAPIProtocol.simulateOffline = false }

        let request = ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 9,
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 6, day: 1),
            expectedReturnDate: nil,
            expectedSourcePlacement: nil
        )
        do {
            _ = try await client().createMovement(serverURL: serverURL, accessToken: accessToken, itemID: 5, request: request)
            XCTFail("simulateOffline should fail")
        } catch let error as ManageItError {
            guard case .transportFailure = error else {
                return XCTFail("expected .transportFailure, got \(error)")
            }
        } catch {
            XCTFail("expected ManageItError, got \(error)")
        }
    }
}
