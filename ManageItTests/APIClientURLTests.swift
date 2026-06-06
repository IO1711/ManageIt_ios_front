import XCTest
@testable import ManageIt

/// URLProtocol that captures the most recent request and returns a canned JSON
/// body so we can assert what URL ManageItAPIClient builds.
final class RequestCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var responseBody: Data = Data("{}".utf8)
    nonisolated(unsafe) static var responseStatus: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let url = request.url ?? URL(string: "about:blank")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class APIClientURLTests: XCTestCase {

    private func makeClient() -> ManageItAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return ManageItAPIClient(urlSession: session)
    }

    private let serverURL = URL(string: "http://capture.manageit.local")!

    override func setUp() {
        super.setUp()
        RequestCapturingURLProtocol.lastRequest = nil
        RequestCapturingURLProtocol.responseStatus = 200
        RequestCapturingURLProtocol.responseBody = Data("{}".utf8)
    }

    // MARK: - URL building

    func testFetchItemsBuildsExpectedURL() async throws {
        RequestCapturingURLProtocol.responseBody = Data("""
        {"items":[],"page":0,"size":20,"totalItems":0,"totalPages":0}
        """.utf8)

        var query = InventoryListQuery()
        query.searchText = "mask"
        query.page = 2
        query.size = 10
        query.includeArchived = true
        query.sort = "title,asc"

        _ = try await makeClient().fetchItems(serverURL: serverURL, accessToken: "T", query: query)

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/api/items")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["q"], "mask")
        XCTAssertEqual(items["page"], "2")
        XCTAssertEqual(items["size"], "10")
        XCTAssertEqual(items["includeArchived"], "true")
        XCTAssertEqual(items["sort"], "title,asc")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer T")
    }

    func testFetchItemsOmitsEmptyQuery() async throws {
        RequestCapturingURLProtocol.responseBody = Data("""
        {"items":[],"page":0,"size":20,"totalItems":0,"totalPages":0}
        """.utf8)
        let query = InventoryListQuery()
        _ = try await makeClient().fetchItems(serverURL: serverURL, accessToken: "T", query: query)

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        let url = try XCTUnwrap(request.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertNil(items["q"], "empty query must not include q=")
        XCTAssertNil(items["includeArchived"], "default false must not include the param")
        XCTAssertEqual(items["page"], "0")
        XCTAssertEqual(items["size"], "20")
    }

    func testConflictCheckAlwaysIncludesArchived() async throws {
        RequestCapturingURLProtocol.responseBody = Data("""
        {"available":true,"mainInventoryNumber":"INV-001","conflictingItem":null}
        """.utf8)

        _ = try await makeClient().checkMainInventoryNumberConflict(
            serverURL: serverURL,
            accessToken: "T",
            mainInventoryNumber: "INV-001"
        )

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        let url = try XCTUnwrap(request.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["mainInventoryNumber"], "INV-001")
        XCTAssertEqual(items["includeArchived"], "true", "rule 7: archived numbers must still flag as conflict")
    }

    func testFetchExhibitionsWithPhaseFilter() async throws {
        RequestCapturingURLProtocol.responseBody = Data("[]".utf8)

        _ = try await makeClient().fetchExhibitions(serverURL: serverURL, accessToken: "T", phase: .active)

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        let url = try XCTUnwrap(request.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["phase"], "ACTIVE")
    }

    func testFetchLocationsIncludeArchivedToggle() async throws {
        RequestCapturingURLProtocol.responseBody = Data("[]".utf8)

        _ = try await makeClient().fetchLocations(serverURL: serverURL, accessToken: "T", includeArchived: true)

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["includeArchived"], "true")
    }

    func testServerUrlWithTrailingSlashIsNormalized() async throws {
        RequestCapturingURLProtocol.responseBody = Data("[]".utf8)
        let trailing = URL(string: "http://capture.manageit.local/")!

        _ = try await makeClient().fetchLocations(serverURL: trailing, accessToken: "T", includeArchived: false)

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/locations")
    }

    func testServerUrlWithApiSuffixIsNormalized() async throws {
        RequestCapturingURLProtocol.responseBody = Data("[]".utf8)
        let withSuffix = URL(string: "http://capture.manageit.local/api")!

        _ = try await makeClient().fetchLocations(serverURL: withSuffix, accessToken: "T", includeArchived: false)

        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/locations", "must not double up /api/api")
    }

    // MARK: - Error decoding

    func testBackendErrorEnvelopeDecodes() async {
        RequestCapturingURLProtocol.responseStatus = 409
        RequestCapturingURLProtocol.responseBody = Data("""
        {"error":{"code":"DUPLICATE_MAIN_INVENTORY_NUMBER","message":"already exists","details":{}}}
        """.utf8)

        do {
            _ = try await makeClient().fetchItem(serverURL: serverURL, accessToken: "T", itemID: 42)
            XCTFail("should throw")
        } catch let error as ManageItError {
            guard case let .backend(code, message) = error else {
                return XCTFail("expected .backend, got \(error)")
            }
            XCTAssertEqual(code, "DUPLICATE_MAIN_INVENTORY_NUMBER")
            XCTAssertEqual(message, "already exists")
        } catch {
            XCTFail("expected ManageItError, got \(error)")
        }
    }

    func testDeviceRevokedEnvelopeMapsToDedicatedError() async {
        RequestCapturingURLProtocol.responseStatus = 401
        RequestCapturingURLProtocol.responseBody = Data("""
        {"error":{"code":"DEVICE_REVOKED","message":"revoked","details":{}}}
        """.utf8)
        do {
            _ = try await makeClient().fetchItem(serverURL: serverURL, accessToken: "T", itemID: 42)
            XCTFail()
        } catch let error as ManageItError {
            guard case .deviceRevoked = error else {
                return XCTFail("expected .deviceRevoked, got \(error)")
            }
        } catch {
            XCTFail("expected ManageItError, got \(error)")
        }
    }

    func testNon2xxWithoutEnvelopeMapsToUnauthorizedFor401() async {
        RequestCapturingURLProtocol.responseStatus = 401
        RequestCapturingURLProtocol.responseBody = Data("not json".utf8)
        do {
            _ = try await makeClient().fetchItem(serverURL: serverURL, accessToken: "T", itemID: 1)
            XCTFail()
        } catch let error as ManageItError {
            guard case .unauthorized = error else {
                return XCTFail("expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("expected ManageItError, got \(error)")
        }
    }
}
