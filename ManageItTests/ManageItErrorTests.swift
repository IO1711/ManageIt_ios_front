import XCTest
@testable import ManageIt

final class ManageItErrorTests: XCTestCase {

    func testExhibitionOverlapHasFriendlyMessage() {
        let error = ManageItError.backend(
            code: "ITEM_EXHIBITION_OVERLAP",
            message: "raw server message"
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("overlapping"), "should mention overlap; got: \(description)")
        XCTAssertFalse(description.contains("raw server message"))
    }

    func testNotAtExhibitionLocationHasFriendlyMessage() {
        let error = ManageItError.backend(
            code: "ITEM_NOT_AT_EXHIBITION_LOCATION",
            message: "raw"
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.localizedCaseInsensitiveContains("not currently"))
    }

    func testNonLeafLocationHasFriendlyMessage() {
        let error = ManageItError.backend(code: "NON_LEAF_LOCATION", message: "raw")
        XCTAssertTrue((error.errorDescription ?? "").localizedCaseInsensitiveContains("leaf"))
    }

    func testStaleOfflineHasFriendlyMessage() {
        let error = ManageItError.backend(code: "STALE_OFFLINE_MOVEMENT", message: "raw")
        XCTAssertTrue((error.errorDescription ?? "").localizedCaseInsensitiveContains("offline"))
    }

    func testUnknownCodeFallsBackToServerMessage() {
        let error = ManageItError.backend(code: "WHATEVER", message: "Server says this verbatim")
        XCTAssertEqual(error.errorDescription, "Server says this verbatim")
    }

    func testDeviceRevokedHasOwnDescription() {
        let error = ManageItError.deviceRevoked
        XCTAssertTrue((error.errorDescription ?? "").localizedCaseInsensitiveContains("revoked"))
    }

    func testUnauthorizedHasOwnDescription() {
        let error = ManageItError.unauthorized
        XCTAssertTrue((error.errorDescription ?? "").localizedCaseInsensitiveContains("session"))
    }

    func testTransportFailureIncludesEndpoint() {
        let error = ManageItError.transportFailure(
            endpoint: "http://demo.manageit.local/api/items",
            details: "URLError"
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("/api/items"))
        XCTAssertTrue(description.contains("URLError"))
    }

    func testValidationErrorPassesThroughMessage() {
        let error = ManageItError.validationError("Title is required.")
        XCTAssertEqual(error.errorDescription, "Title is required.")
    }
}
