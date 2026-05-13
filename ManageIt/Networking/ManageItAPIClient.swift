import Foundation

struct ManageItAPIClient {
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

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

    private func sendRequest<Response: Decodable, Body: Encodable>(
        serverURL: URL,
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let endpoint = try buildURL(serverURL: serverURL, path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
            if let backendError = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw ManageItError.backend(
                    code: backendError.error.code,
                    message: backendError.error.message
                )
            }

            throw ManageItError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ManageItError.invalidResponse
        }
    }

    private func buildURL(serverURL: URL, path: String) throws -> URL {
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
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

private struct APIErrorBody: Decodable {
    let code: String
    let message: String
}
