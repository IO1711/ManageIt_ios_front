import Foundation

struct InventoryListQuery: Equatable {
    var searchText: String = ""
    var includeArchived: Bool = false
    var page: Int = 0
    var size: Int = 20
    var sort: String? = nil
}

struct ManageItAPIClient {
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.decoder = ManageItAPIClient.makeTimestampDecoder()
        self.encoder = ManageItAPIClient.makeEncoder()
    }

    // MARK: - Pairing

    func scanPairing(
        serverURL: URL,
        request: MobilePairingScanRequest
    ) async throws -> MobilePairingStatusResponse {
        try await sendRequest(
            serverURL: serverURL,
            path: "/mobile/pairings/scan",
            method: "POST",
            body: request
        )
    }

    func fetchPairingStatus(
        serverURL: URL,
        pairingId: UUID
    ) async throws -> MobilePairingStatusResponse {
        try await sendRequest(
            serverURL: serverURL,
            path: "/mobile/pairings/\(pairingId.uuidString)",
            method: "GET",
            body: Optional<String>.none
        )
    }

    func completePairing(
        serverURL: URL,
        pairingId: UUID
    ) async throws -> MobilePairingCompleteResponse {
        try await sendRequest(
            serverURL: serverURL,
            path: "/mobile/pairings/\(pairingId.uuidString)/complete",
            method: "POST",
            body: Optional<String>.none
        )
    }

    // MARK: - Public bootstrap / session

    func refreshDeviceSession(
        serverURL: URL,
        request: DeviceTokenRefreshRequest
    ) async throws -> DeviceTokenRefreshResponse {
        try await sendRequest(
            serverURL: serverURL,
            path: "/auth/refresh",
            method: "POST",
            body: request
        )
    }

    func fetchCurrentSession(
        serverURL: URL,
        accessToken: String
    ) async throws -> DeviceSessionStatusResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/auth/me",
            method: "GET",
            accessToken: accessToken,
            body: Optional<String>.none
        )
    }

    func logoutCurrentSession(
        serverURL: URL,
        accessToken: String
    ) async throws {
        try await sendAuthenticatedRequestWithoutResponseBody(
            serverURL: serverURL,
            path: "/auth/logout",
            method: "POST",
            accessToken: accessToken,
            body: Optional<String>.none
        )
    }

    // MARK: - Inventory

    func fetchItems(
        serverURL: URL,
        accessToken: String,
        query: InventoryListQuery
    ) async throws -> ItemListResponse {
        var items: [URLQueryItem] = []
        let trimmed = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        if query.includeArchived {
            items.append(URLQueryItem(name: "includeArchived", value: "true"))
        }
        items.append(URLQueryItem(name: "page", value: String(query.page)))
        items.append(URLQueryItem(name: "size", value: String(query.size)))
        if let sort = query.sort, !sort.isEmpty {
            items.append(URLQueryItem(name: "sort", value: sort))
        }

        return try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items",
            method: "GET",
            accessToken: accessToken,
            queryItems: items,
            body: Optional<String>.none
        )
    }

    func fetchItem(
        serverURL: URL,
        accessToken: String,
        itemID: Int64
    ) async throws -> ItemResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/\(itemID)",
            method: "GET",
            accessToken: accessToken,
            body: Optional<String>.none
        )
    }

    func createItem(
        serverURL: URL,
        accessToken: String,
        request: ItemCreateRequest
    ) async throws -> ItemResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    func updateItem(
        serverURL: URL,
        accessToken: String,
        itemID: Int64,
        request: ItemUpdateRequest
    ) async throws -> ItemResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/\(itemID)",
            method: "PUT",
            accessToken: accessToken,
            body: request
        )
    }

    func updateItemPlanning(
        serverURL: URL,
        accessToken: String,
        itemID: Int64,
        request: ItemPlanningUpdateRequest
    ) async throws -> ItemResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/\(itemID)/planning",
            method: "PATCH",
            accessToken: accessToken,
            body: request
        )
    }

    func archiveItem(
        serverURL: URL,
        accessToken: String,
        itemID: Int64
    ) async throws -> ItemResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/\(itemID)/archive",
            method: "POST",
            accessToken: accessToken,
            body: Optional<String>.none
        )
    }

    func checkMainInventoryNumberConflict(
        serverURL: URL,
        accessToken: String,
        mainInventoryNumber: String
    ) async throws -> ItemMainNumberConflictResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/conflicts/main-number",
            method: "GET",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "mainInventoryNumber", value: mainInventoryNumber)],
            body: Optional<String>.none
        )
    }

    // MARK: - Lookups

    func fetchLocations(
        serverURL: URL,
        accessToken: String,
        includeArchived: Bool
    ) async throws -> [LocationResponse] {
        var items: [URLQueryItem] = []
        if includeArchived {
            items.append(URLQueryItem(name: "includeArchived", value: "true"))
        }
        return try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/locations",
            method: "GET",
            accessToken: accessToken,
            queryItems: items,
            body: Optional<String>.none
        )
    }

    func createLocation(
        serverURL: URL,
        accessToken: String,
        request: LocationCreateRequest
    ) async throws -> LocationResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/locations",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    func updateLocation(
        serverURL: URL,
        accessToken: String,
        locationID: Int64,
        request: LocationUpdateRequest
    ) async throws -> LocationResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/locations/\(locationID)",
            method: "PUT",
            accessToken: accessToken,
            body: request
        )
    }

    func archiveLocation(
        serverURL: URL,
        accessToken: String,
        locationID: Int64
    ) async throws -> LocationResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/locations/\(locationID)/archive",
            method: "POST",
            accessToken: accessToken,
            body: Optional<String>.none
        )
    }

    func fetchAuthors(
        serverURL: URL,
        accessToken: String,
        query: String,
        includeArchived: Bool
    ) async throws -> [AuthorResponse] {
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        if includeArchived {
            items.append(URLQueryItem(name: "includeArchived", value: "true"))
        }
        return try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/authors",
            method: "GET",
            accessToken: accessToken,
            queryItems: items,
            body: Optional<String>.none
        )
    }

    func createAuthor(
        serverURL: URL,
        accessToken: String,
        request: AuthorCreateRequest
    ) async throws -> AuthorResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/authors",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    func fetchOrganizations(
        serverURL: URL,
        accessToken: String,
        query: String,
        includeArchived: Bool
    ) async throws -> [OrganizationResponse] {
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        if includeArchived {
            items.append(URLQueryItem(name: "includeArchived", value: "true"))
        }
        return try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/organizations",
            method: "GET",
            accessToken: accessToken,
            queryItems: items,
            body: Optional<String>.none
        )
    }

    func createOrganization(
        serverURL: URL,
        accessToken: String,
        request: OrganizationCreateRequest
    ) async throws -> OrganizationResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/organizations",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    // MARK: - Exhibitions

    func fetchExhibitions(
        serverURL: URL,
        accessToken: String,
        phase: ExhibitionPhase? = nil
    ) async throws -> [ExhibitionResponse] {
        var items: [URLQueryItem] = []
        if let phase {
            items.append(URLQueryItem(name: "phase", value: phase.rawValue))
        }
        let response: ExhibitionListResponse = try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/exhibitions",
            method: "GET",
            accessToken: accessToken,
            queryItems: items,
            body: Optional<String>.none
        )
        return response.exhibitions
    }

    func fetchExhibition(
        serverURL: URL,
        accessToken: String,
        id: Int64
    ) async throws -> ExhibitionResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/exhibitions/\(id)",
            method: "GET",
            accessToken: accessToken,
            body: Optional<String>.none
        )
    }

    func createExhibition(
        serverURL: URL,
        accessToken: String,
        request: ExhibitionCreateRequest
    ) async throws -> ExhibitionResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/exhibitions",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    func updateExhibition(
        serverURL: URL,
        accessToken: String,
        id: Int64,
        request: ExhibitionUpdateRequest
    ) async throws -> ExhibitionResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/exhibitions/\(id)",
            method: "PUT",
            accessToken: accessToken,
            body: request
        )
    }

    // MARK: - Movement & History (response DTO is blocked in Part III)

    func createMovement(
        serverURL: URL,
        accessToken: String,
        itemID: Int64,
        request: ItemMovementCreateRequest
    ) async throws -> ItemResponse {
        try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/\(itemID)/movements",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    func fetchItemHistory(
        serverURL: URL,
        accessToken: String,
        itemID: Int64
    ) async throws -> [ItemHistoryEntry] {
        let response: ItemHistoryListResponse = try await sendAuthenticatedRequest(
            serverURL: serverURL,
            path: "/items/\(itemID)/history",
            method: "GET",
            accessToken: accessToken,
            body: Optional<String>.none
        )
        return response.entries
    }

    // MARK: - Helpers

    private func sendAuthenticatedRequest<Response: Decodable, Body: Encodable>(
        serverURL: URL,
        path: String,
        method: String,
        accessToken: String,
        queryItems: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        let endpoint = try buildURL(serverURL: serverURL, path: path, queryItems: queryItems)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await perform(request: request, endpoint: endpoint)
    }

    private func sendAuthenticatedRequestWithoutResponseBody<Body: Encodable>(
        serverURL: URL,
        path: String,
        method: String,
        accessToken: String,
        queryItems: [URLQueryItem] = [],
        body: Body?
    ) async throws {
        let endpoint = try buildURL(serverURL: serverURL, path: path, queryItems: queryItems)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw transportFailure(for: endpoint, error: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManageItError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw decodeBackendError(from: data, statusCode: httpResponse.statusCode)
        }
    }

    private func sendRequest<Response: Decodable, Body: Encodable>(
        serverURL: URL,
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let endpoint = try buildURL(serverURL: serverURL, path: path, queryItems: [])
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await perform(request: request, endpoint: endpoint)
    }

    private func perform<Response: Decodable>(
        request: URLRequest,
        endpoint: URL
    ) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw transportFailure(for: endpoint, error: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManageItError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw decodeBackendError(from: data, statusCode: httpResponse.statusCode)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ManageItError.invalidResponse
        }
    }

    private func decodeBackendError(from data: Data, statusCode: Int) -> ManageItError {
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            if envelope.error.code == "DEVICE_REVOKED" {
                return ManageItError.deviceRevoked
            }
            return ManageItError.backend(
                code: envelope.error.code,
                message: envelope.error.message
            )
        }

        if statusCode == 401 || statusCode == 403 {
            return ManageItError.unauthorized
        }

        return ManageItError.invalidResponse
    }

    private func buildURL(
        serverURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            throw ManageItError.invalidServerAddress
        }

        var basePath = components.path
        while basePath.hasSuffix("/") && basePath.count > 1 {
            basePath.removeLast()
        }

        if basePath.hasSuffix("/api") {
            basePath.removeLast(4)
        }

        components.path = basePath + "/api" + path

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw ManageItError.invalidServerAddress
        }

        return url
    }

    private func transportFailure(for endpoint: URL, error: Error) -> ManageItError {
        let nsError = error as NSError

        if let urlError = error as? URLError {
            return ManageItError.transportFailure(
                endpoint: endpoint.absoluteString,
                details: "\(transportFailureDetails(for: urlError)) [\(nsError.domain) \(nsError.code)]"
            )
        }

        return ManageItError.transportFailure(
            endpoint: endpoint.absoluteString,
            details: "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
        )
    }

    private func transportFailureDetails(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "The request timed out."
        case .notConnectedToInternet:
            return "The iPhone is not connected to the network."
        case .cannotFindHost:
            return "The iPhone could not find the host."
        case .cannotConnectToHost:
            return "The iPhone could not connect to the host."
        case .dnsLookupFailed:
            return "DNS lookup failed for the host."
        case .networkConnectionLost:
            return "The network connection was lost."
        case .secureConnectionFailed:
            return "A secure connection to the server could not be established."
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS blocked the request because App Transport Security requires HTTPS for this server configuration."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Codec factories

    static func makeTimestampDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let single = try container.singleValueContainer()
            let raw = try single.decode(String.self)
            if let parsed = TimestampCodec.parse(raw) {
                return parsed
            }
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Could not parse ISO 8601 timestamp: \(raw)"
            )
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TimestampCodec.encode(date))
        }
        return encoder
    }
}

// MARK: - Timestamp codec helper

enum TimestampCodec {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        withFractional.date(from: raw) ?? plain.date(from: raw)
    }

    static func encode(_ date: Date) -> String {
        plain.string(from: date)
    }
}

private struct EmptyResponse: Decodable {}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

private struct APIErrorBody: Decodable {
    let code: String
    let message: String
}
