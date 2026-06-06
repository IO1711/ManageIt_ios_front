import XCTest
@testable import ManageIt

final class DecoderTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - ItemResponse backward compatibility

    func testItemResponseDecodesWithoutCurrentExhibition() throws {
        let json = """
        {
          "id": 1,
          "mainInventoryNumber": "INV-001",
          "title": "Sample",
          "secondaryInventoryNumbers": [],
          "authors": [{"id": 1, "name": "A"}],
          "currentPlacement": {
            "presenceType": "INTERNAL",
            "location": {"id": 5, "name": "Shelf 1", "path": "Hall > Shelf 1"},
            "organization": null
          },
          "planning": {
            "promisedOrganization": null,
            "expectedLeaveDate": null
          },
          "archived": false
        }
        """
        let item = try decode(ItemResponse.self, json: json)
        XCTAssertNil(item.currentExhibition)
        XCTAssertEqual(item.currentPlacement.location?.displayPath, "Hall > Shelf 1")
    }

    func testItemResponseDecodesWithCurrentExhibition() throws {
        let json = """
        {
          "id": 1,
          "mainInventoryNumber": "INV-001",
          "title": "Sample",
          "secondaryInventoryNumbers": [],
          "authors": [],
          "currentPlacement": {"presenceType": "INTERNAL", "location": null, "organization": null},
          "planning": {"promisedOrganization": null, "expectedLeaveDate": null},
          "archived": false,
          "currentExhibition": {
            "id": 7,
            "name": "Summer Show",
            "startDate": "2026-06-01",
            "endDate": "2026-08-31"
          }
        }
        """
        let item = try decode(ItemResponse.self, json: json)
        XCTAssertEqual(item.currentExhibition?.id, 7)
        XCTAssertEqual(item.currentExhibition?.name, "Summer Show")
        XCTAssertEqual(item.currentExhibition?.endDate.encodedString, "2026-08-31")
    }

    // MARK: - ItemHistoryListResponse tolerance

    func testHistoryDecoderAcceptsObjectShape() throws {
        let json = """
        {
          "entries": [
            {
              "id": 1,
              "presenceType": "INTERNAL",
              "location": {"id": 5, "name": "Shelf 1"},
              "moveInDate": "2026-01-01"
            }
          ]
        }
        """
        let response = try decode(ItemHistoryListResponse.self, json: json)
        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries[0].location?.name, "Shelf 1")
    }

    func testHistoryDecoderAcceptsBareArray() throws {
        let json = """
        [
          {
            "id": 1,
            "presenceType": "EXTERNAL",
            "organization": {"id": 9, "name": "Museum of Rome"},
            "moveInDate": "2026-04-10",
            "expectedReturnDate": "2026-08-10"
          }
        ]
        """
        let response = try decode(ItemHistoryListResponse.self, json: json)
        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries[0].organization?.name, "Museum of Rome")
        XCTAssertEqual(response.entries[0].expectedReturnDate?.encodedString, "2026-08-10")
    }

    func testHistoryEntryDecodesMovedByDevice() throws {
        let json = """
        {
          "entries": [
            {
              "id": 1,
              "presenceType": "INTERNAL",
              "location": {"id": 5, "name": "Shelf 1"},
              "moveInDate": "2026-01-01",
              "movedByDevice": {
                "id": "11111111-1111-1111-1111-111111111111",
                "friendlyName": "Demo iPhone",
                "deviceType": "IOS_APP"
              }
            }
          ]
        }
        """
        let response = try decode(ItemHistoryListResponse.self, json: json)
        let actor = response.entries[0].movedByDevice
        XCTAssertEqual(actor?.friendlyName, "Demo iPhone")
        XCTAssertEqual(actor?.deviceType, .iosApp)
    }

    func testHistoryEntryWithoutMovedByDeviceIsNil() throws {
        let json = """
        {
          "entries": [
            {"id": 1, "presenceType": "INTERNAL", "location": {"id": 5, "name": "S1"}, "moveInDate": "2026-01-01"}
          ]
        }
        """
        let response = try decode(ItemHistoryListResponse.self, json: json)
        XCTAssertNil(response.entries[0].movedByDevice)
    }

    // MARK: - ExhibitionListResponse tolerance

    func testExhibitionsDecoderAcceptsObjectShape() throws {
        let json = """
        {
          "exhibitions": [
            {
              "id": 1, "name": "X", "locationId": 5, "locationPath": "Hall > Shelf 1",
              "startDate": "2026-01-01", "endDate": "2026-02-01",
              "phase": "PLANNED", "itemCount": 3
            }
          ]
        }
        """
        let response = try decode(ExhibitionListResponse.self, json: json)
        XCTAssertEqual(response.exhibitions.count, 1)
        XCTAssertEqual(response.exhibitions[0].phase, .planned)
    }

    func testExhibitionsDecoderAcceptsBareArray() throws {
        let json = """
        [
          {
            "id": 1, "name": "X", "locationId": 5, "locationPath": "Hall > Shelf 1",
            "startDate": "2026-01-01", "endDate": "2026-02-01",
            "phase": "ACTIVE", "itemCount": 3
          }
        ]
        """
        let response = try decode(ExhibitionListResponse.self, json: json)
        XCTAssertEqual(response.exhibitions.count, 1)
    }

    // MARK: - LocationResponse fields

    func testLocationResponseDecodesHierarchyFields() throws {
        let json = """
        {
          "id": 8, "name": "Shelf 1", "archived": false,
          "parentLocationId": 6, "path": "Hall A > Display Case 1 > Shelf 1",
          "assignable": true
        }
        """
        let location = try decode(LocationResponse.self, json: json)
        XCTAssertEqual(location.parentLocationId, 6)
        XCTAssertEqual(location.displayPath, "Hall A > Display Case 1 > Shelf 1")
        XCTAssertTrue(location.isAssignable)
    }

    func testLocationResponseFallsBackWhenPathMissing() throws {
        let json = """
        {"id": 1, "name": "Hall A", "archived": false, "parentLocationId": null, "path": null, "assignable": false}
        """
        let location = try decode(LocationResponse.self, json: json)
        XCTAssertEqual(location.displayPath, "Hall A")
        XCTAssertFalse(location.isAssignable)
    }

    // MARK: - ConflictingItem path field

    func testConflictingItemDecodesPathField() throws {
        let json = """
        {
          "id": 45, "title": "Mask", "currentPresenceType": "INTERNAL",
          "currentLocationName": "Grid A", "currentLocationPath": "Storage > Shelf B > Grid A"
        }
        """
        let conflict = try decode(ConflictingItem.self, json: json)
        XCTAssertEqual(conflict.displayPlacement, "Storage > Shelf B > Grid A")
    }

    // MARK: - Error envelope

    func testItemMainNumberConflictDecodes() throws {
        let json = """
        {
          "available": false,
          "mainInventoryNumber": "INV-2026-001",
          "conflictingItem": {
            "id": 45, "title": "Mask", "currentPresenceType": "INTERNAL",
            "currentLocationName": "Grid A", "currentLocationPath": "Storage > Grid A"
          }
        }
        """
        let response = try decode(ItemMainNumberConflictResponse.self, json: json)
        XCTAssertFalse(response.available)
        XCTAssertEqual(response.conflictingItem?.id, 45)
    }

    // MARK: - Round-trip for outbox

    func testItemMovementCreateRequestRoundTripsExpectedSourcePlacement() throws {
        let request = ItemMovementCreateRequest(
            presenceType: .internal,
            locationId: 8,
            organization: nil,
            moveInDate: try BusinessDate(year: 2026, month: 5, day: 27),
            expectedReturnDate: nil,
            expectedSourcePlacement: ExpectedSourcePlacement(
                presenceType: .internal,
                locationId: 4,
                organizationId: nil
            )
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ItemMovementCreateRequest.self, from: data)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.expectedSourcePlacement?.locationId, 4)
    }
}
