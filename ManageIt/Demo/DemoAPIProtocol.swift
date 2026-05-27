#if DEBUG
import Foundation

// MARK: - URL Protocol

/// Intercepts all requests targeted at `demo.manageit.local` and serves canned JSON
/// from an in-memory `DemoDataStore`. Activated via `DemoAPIProtocol.enable()`.
final class DemoAPIProtocol: URLProtocol {
    nonisolated(unsafe) static var isEnabled = false
    nonisolated(unsafe) static let store = DemoDataStore()

    static let demoHost = "demo.manageit.local"
    static let demoServerAddress = "http://demo.manageit.local"

    override class func canInit(with request: URLRequest) -> Bool {
        guard isEnabled else { return false }
        return request.url?.host == demoHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, payload) = DemoAPIProtocol.store.respond(to: request)
        let url = request.url!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let payload {
            client?.urlProtocol(self, didLoad: payload)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func enable() {
        guard !isEnabled else { return }
        URLProtocol.registerClass(DemoAPIProtocol.self)
        isEnabled = true
    }
}

// MARK: - Data Store

final class DemoDataStore: @unchecked Sendable {
    private let lock = NSLock()

    private var items: [DemoItem]
    private var locations: [DemoLocation]
    private var authors: [DemoAuthor]
    private var organizations: [DemoOrg]
    private var history: [Int64: [DemoHistory]]
    private var nextItemId: Int64
    private var nextLocationId: Int64
    private var nextAuthorId: Int64
    private var nextOrgId: Int64
    private var nextHistoryId: Int64

    init() {
        let seed = DemoSeed.build()
        items = seed.items
        locations = seed.locations
        authors = seed.authors
        organizations = seed.organizations
        history = seed.history
        nextItemId = (seed.items.map(\.id).max() ?? 0) + 1
        nextLocationId = (seed.locations.map(\.id).max() ?? 0) + 1
        nextAuthorId = (seed.authors.map(\.id).max() ?? 0) + 1
        nextOrgId = (seed.organizations.map(\.id).max() ?? 0) + 1
        nextHistoryId = (seed.history.values.flatMap { $0 }.map(\.id).max() ?? 0) + 1
    }

    func respond(to request: URLRequest) -> (Int, Data?) {
        lock.lock()
        defer { lock.unlock() }

        guard let url = request.url else { return (404, nil) }
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let bodyData = request.httpBody ?? Self.readStream(request.httpBodyStream)

        // Static routes first
        if method == "POST" && path == "/api/auth/refresh" {
            return success(refreshResponseJSON())
        }
        if method == "POST" && path == "/api/auth/logout" {
            return (200, nil)
        }
        if method == "GET" && path == "/api/auth/me" {
            return success(meResponseJSON())
        }
        if method == "GET" && path == "/api/items/conflicts/main-number" {
            return success(conflictJSON(url: url))
        }
        if method == "GET" && path == "/api/items" {
            return success(itemListJSON(url: url))
        }
        if method == "POST" && path == "/api/items" {
            if let item = createItem(bodyData: bodyData) {
                return success(itemJSON(item))
            }
            return (400, nil)
        }
        if method == "GET" && path == "/api/locations" {
            let include = url.queryValue("includeArchived") == "true"
            let filtered = include ? locations : locations.filter { !$0.archived }
            return success(arrayData(filtered.map(locationDict)))
        }
        if method == "POST" && path == "/api/locations" {
            if let loc = createLocation(bodyData: bodyData) {
                return success(dictData(locationDict(loc)))
            }
            return (400, nil)
        }
        if method == "GET" && path == "/api/authors" {
            let q = url.queryValue("q")?.lowercased() ?? ""
            let filtered = authors.filter { !$0.archived && (q.isEmpty || $0.name.lowercased().contains(q)) }
            return success(arrayData(filtered.map(authorDict)))
        }
        if method == "POST" && path == "/api/authors" {
            if let a = createAuthor(bodyData: bodyData) {
                return success(dictData(authorDict(a)))
            }
            return (400, nil)
        }
        if method == "GET" && path == "/api/organizations" {
            let q = url.queryValue("q")?.lowercased() ?? ""
            let filtered = organizations.filter { !$0.archived && (q.isEmpty || $0.name.lowercased().contains(q)) }
            return success(arrayData(filtered.map(orgDict)))
        }
        if method == "POST" && path == "/api/organizations" {
            if let o = createOrg(bodyData: bodyData) {
                return success(dictData(orgDict(o)))
            }
            return (400, nil)
        }

        // Path-suffix routes
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/history"), method == "GET" {
            return success(historyJSON(itemId: id))
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/movements"), method == "POST" {
            if let item = createMovement(itemId: id, bodyData: bodyData) {
                return success(itemJSON(item))
            }
            return (404, nil)
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/planning"), method == "PATCH" {
            if let item = updatePlanning(itemId: id, bodyData: bodyData) {
                return success(itemJSON(item))
            }
            return (404, nil)
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/archive"), method == "POST" {
            if let item = archiveItem(itemId: id) {
                return success(itemJSON(item))
            }
            return (404, nil)
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: nil) {
            if method == "GET", let item = items.first(where: { $0.id == id }) {
                return success(itemJSON(item))
            }
            if method == "PUT", let item = updateItem(itemId: id, bodyData: bodyData) {
                return success(itemJSON(item))
            }
        }
        if let id = extractTrailingId(path: path, prefix: "/api/locations/", suffix: "/archive"), method == "POST" {
            if let loc = archiveLocation(id: id) {
                return success(dictData(locationDict(loc)))
            }
            return (404, nil)
        }
        if let id = extractTrailingId(path: path, prefix: "/api/locations/", suffix: nil), method == "PUT" {
            if let loc = updateLocation(id: id, bodyData: bodyData) {
                return success(dictData(locationDict(loc)))
            }
            return (404, nil)
        }

        return (404, nil)
    }

    // MARK: - Item mutations

    private func createItem(bodyData: Data?) -> DemoItem? {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let id = nextItemId; nextItemId += 1
        let authorIds: [Int64] = {
            guard let arr = json["authors"] as? [[String: Any]] else { return [] }
            return arr.compactMap { input -> Int64? in
                if let aid = (input["id"] as? Int).map(Int64.init) ?? (input["id"] as? Int64) {
                    return aid
                }
                if let name = input["name"] as? String, !name.isEmpty {
                    if let existing = authors.first(where: { $0.name.lowercased() == name.lowercased() }) {
                        return existing.id
                    }
                    let newAuthor = DemoAuthor(id: nextAuthorId, name: name, archived: false)
                    nextAuthorId += 1
                    authors.append(newAuthor)
                    return newAuthor.id
                }
                return nil
            }
        }()
        let locationId = (json["initialLocationId"] as? Int).map(Int64.init) ?? (json["initialLocationId"] as? Int64)
        let item = DemoItem(
            id: id,
            mainInventoryNumber: (json["mainInventoryNumber"] as? String) ?? "INV-DEMO-\(id)",
            title: (json["title"] as? String) ?? "New item",
            secondaryInventoryNumbers: (json["secondaryInventoryNumbers"] as? [String]) ?? [],
            authorIds: authorIds,
            presenceType: "INTERNAL",
            locationId: locationId,
            organizationId: nil,
            promisedOrgId: nil,
            expectedLeaveDate: nil,
            archived: false
        )
        items.append(item)
        if let moveIn = json["moveInDate"] as? String, let lid = locationId {
            let entry = DemoHistory(
                id: nextHistoryId,
                presenceType: "INTERNAL",
                locationId: lid,
                organizationId: nil,
                moveInDate: moveIn,
                moveOutDate: nil,
                expectedReturnDate: nil
            )
            nextHistoryId += 1
            history[item.id, default: []].append(entry)
        }
        return item
    }

    private func updateItem(itemId: Int64, bodyData: Data?) -> DemoItem? {
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var item = items[idx]
        if let v = json["mainInventoryNumber"] as? String { item.mainInventoryNumber = v }
        if let v = json["title"] as? String { item.title = v }
        if let v = json["secondaryInventoryNumbers"] as? [String] { item.secondaryInventoryNumbers = v }
        if let arr = json["authors"] as? [[String: Any]] {
            item.authorIds = arr.compactMap { input -> Int64? in
                if let aid = (input["id"] as? Int).map(Int64.init) ?? (input["id"] as? Int64) {
                    return aid
                }
                if let name = input["name"] as? String, !name.isEmpty {
                    if let existing = authors.first(where: { $0.name.lowercased() == name.lowercased() }) {
                        return existing.id
                    }
                    let newAuthor = DemoAuthor(id: nextAuthorId, name: name, archived: false)
                    nextAuthorId += 1
                    authors.append(newAuthor)
                    return newAuthor.id
                }
                return nil
            }
        }
        items[idx] = item
        return item
    }

    private func updatePlanning(itemId: Int64, bodyData: Data?) -> DemoItem? {
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var item = items[idx]
        if let orgInput = json["promisedOrganization"] as? [String: Any] {
            if let oid = (orgInput["id"] as? Int).map(Int64.init) ?? (orgInput["id"] as? Int64) {
                item.promisedOrgId = oid
            } else if let name = orgInput["name"] as? String {
                if let existing = organizations.first(where: { $0.name.lowercased() == name.lowercased() }) {
                    item.promisedOrgId = existing.id
                } else {
                    let new = DemoOrg(id: nextOrgId, name: name, archived: false)
                    nextOrgId += 1
                    organizations.append(new)
                    item.promisedOrgId = new.id
                }
            }
        } else if json.keys.contains("promisedOrganization") {
            item.promisedOrgId = nil
        }
        if let date = json["expectedLeaveDate"] as? String {
            item.expectedLeaveDate = date
        } else if json.keys.contains("expectedLeaveDate") {
            item.expectedLeaveDate = nil
        }
        items[idx] = item
        return item
    }

    private func archiveItem(itemId: Int64) -> DemoItem? {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return nil }
        items[idx].archived = true
        return items[idx]
    }

    private func createMovement(itemId: Int64, bodyData: Data?) -> DemoItem? {
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var item = items[idx]
        let presenceType = (json["presenceType"] as? String) ?? "INTERNAL"
        let moveInDate = (json["moveInDate"] as? String) ?? "2026-01-01"

        // Close previous open row
        var rows = history[item.id] ?? []
        if let openIdx = rows.firstIndex(where: { $0.moveOutDate == nil }) {
            rows[openIdx].moveOutDate = moveInDate
        }

        if presenceType == "INTERNAL" {
            let locationId = (json["locationId"] as? Int).map(Int64.init) ?? (json["locationId"] as? Int64)
            item.presenceType = "INTERNAL"
            item.locationId = locationId
            item.organizationId = nil
            item.promisedOrgId = nil
            item.expectedLeaveDate = nil
            rows.append(DemoHistory(
                id: nextHistoryId,
                presenceType: "INTERNAL",
                locationId: locationId,
                organizationId: nil,
                moveInDate: moveInDate,
                moveOutDate: nil,
                expectedReturnDate: nil
            ))
            nextHistoryId += 1
        } else {
            var orgId: Int64? = nil
            if let orgInput = json["organization"] as? [String: Any] {
                if let oid = (orgInput["id"] as? Int).map(Int64.init) ?? (orgInput["id"] as? Int64) {
                    orgId = oid
                } else if let name = orgInput["name"] as? String {
                    if let existing = organizations.first(where: { $0.name.lowercased() == name.lowercased() }) {
                        orgId = existing.id
                    } else {
                        let new = DemoOrg(id: nextOrgId, name: name, archived: false)
                        nextOrgId += 1
                        organizations.append(new)
                        orgId = new.id
                    }
                }
            }
            item.presenceType = "EXTERNAL"
            item.organizationId = orgId
            item.locationId = nil
            item.promisedOrgId = nil
            item.expectedLeaveDate = nil
            rows.append(DemoHistory(
                id: nextHistoryId,
                presenceType: "EXTERNAL",
                locationId: nil,
                organizationId: orgId,
                moveInDate: moveInDate,
                moveOutDate: nil,
                expectedReturnDate: json["expectedReturnDate"] as? String
            ))
            nextHistoryId += 1
        }

        history[item.id] = rows
        items[idx] = item
        return item
    }

    // MARK: - Location mutations

    private func createLocation(bodyData: Data?) -> DemoLocation? {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else { return nil }
        let loc = DemoLocation(id: nextLocationId, name: name, archived: false)
        nextLocationId += 1
        locations.append(loc)
        return loc
    }

    private func updateLocation(id: Int64, bodyData: Data?) -> DemoLocation? {
        guard let idx = locations.firstIndex(where: { $0.id == id }),
              let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else { return nil }
        locations[idx].name = name
        return locations[idx]
    }

    private func archiveLocation(id: Int64) -> DemoLocation? {
        guard let idx = locations.firstIndex(where: { $0.id == id }) else { return nil }
        locations[idx].archived = true
        return locations[idx]
    }

    // MARK: - Author / Org create

    private func createAuthor(bodyData: Data?) -> DemoAuthor? {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else { return nil }
        if let existing = authors.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }
        let a = DemoAuthor(id: nextAuthorId, name: name, archived: false)
        nextAuthorId += 1
        authors.append(a)
        return a
    }

    private func createOrg(bodyData: Data?) -> DemoOrg? {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else { return nil }
        if let existing = organizations.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }
        let o = DemoOrg(id: nextOrgId, name: name, archived: false)
        nextOrgId += 1
        organizations.append(o)
        return o
    }

    // MARK: - JSON builders

    private func refreshResponseJSON() -> Data {
        let body: [String: Any] = [
            "deviceId": "11111111-1111-1111-1111-111111111111",
            "role": "ADMIN",
            "deviceType": "IOS_APP",
            "friendlyName": "Demo iPhone",
            "accessToken": "demo-access-token",
            "accessTokenExpiresAt": isoTimestamp(addingHours: 1),
            "refreshTokenExpiresAt": isoTimestamp(addingHours: 24 * 30)
        ]
        return dictData(body)
    }

    private func meResponseJSON() -> Data {
        let body: [String: Any] = [
            "authenticated": true,
            "deviceId": "11111111-1111-1111-1111-111111111111",
            "role": "ADMIN",
            "deviceType": "IOS_APP",
            "friendlyName": "Demo iPhone"
        ]
        return dictData(body)
    }

    private func conflictJSON(url: URL) -> Data {
        let number = url.queryValue("mainInventoryNumber") ?? ""
        let conflict = items.first(where: { $0.mainInventoryNumber.lowercased() == number.lowercased() && !$0.archived })
        var body: [String: Any] = [
            "available": conflict == nil,
            "mainInventoryNumber": number,
            "conflictingItem": NSNull()
        ]
        if let conflict {
            let locName = conflict.locationId.flatMap { lid in locations.first(where: { $0.id == lid })?.name }
            body["conflictingItem"] = [
                "id": conflict.id,
                "title": conflict.title,
                "currentPresenceType": conflict.presenceType,
                "currentLocationName": locName ?? NSNull()
            ] as [String: Any]
        }
        return dictData(body)
    }

    private func itemListJSON(url: URL) -> Data {
        let q = url.queryValue("q")?.lowercased() ?? ""
        let includeArchived = url.queryValue("includeArchived") == "true"
        let page = Int(url.queryValue("page") ?? "0") ?? 0
        let size = Int(url.queryValue("size") ?? "20") ?? 20

        var filtered = items
        if !includeArchived {
            filtered = filtered.filter { !$0.archived }
        }
        if !q.isEmpty {
            filtered = filtered.filter { item in
                if item.title.lowercased().contains(q) { return true }
                if item.mainInventoryNumber.lowercased().contains(q) { return true }
                if item.secondaryInventoryNumbers.contains(where: { $0.lowercased().contains(q) }) { return true }
                let names = item.authorIds.compactMap { aid in authors.first(where: { $0.id == aid })?.name.lowercased() }
                if names.contains(where: { $0.contains(q) }) { return true }
                if let lid = item.locationId, let loc = locations.first(where: { $0.id == lid }), loc.name.lowercased().contains(q) { return true }
                return false
            }
        }

        let start = page * size
        let end = min(start + size, filtered.count)
        let slice = start < filtered.count ? Array(filtered[start..<end]) : []
        let totalItems = filtered.count
        let totalPages = totalItems == 0 ? 0 : Int((Double(totalItems) / Double(size)).rounded(.up))

        let body: [String: Any] = [
            "items": slice.map(itemDict),
            "page": page,
            "size": size,
            "totalItems": totalItems,
            "totalPages": totalPages
        ]
        return dictData(body)
    }

    private func historyJSON(itemId: Int64) -> Data {
        let rows = (history[itemId] ?? []).sorted { lhs, rhs in lhs.moveInDate > rhs.moveInDate }
        let payload = rows.map { row -> [String: Any] in
            var dict: [String: Any] = [
                "id": row.id,
                "presenceType": row.presenceType,
                "moveInDate": row.moveInDate,
                "location": NSNull(),
                "organization": NSNull(),
                "moveOutDate": row.moveOutDate as Any? ?? NSNull(),
                "expectedReturnDate": row.expectedReturnDate as Any? ?? NSNull()
            ]
            if let lid = row.locationId, let loc = locations.first(where: { $0.id == lid }) {
                dict["location"] = ["id": loc.id, "name": loc.name]
            }
            if let oid = row.organizationId, let org = organizations.first(where: { $0.id == oid }) {
                dict["organization"] = ["id": org.id, "name": org.name]
            }
            return dict
        }
        let body: [String: Any] = ["entries": payload]
        return dictData(body)
    }

    private func itemJSON(_ item: DemoItem) -> Data {
        dictData(itemDict(item))
    }

    private func itemDict(_ item: DemoItem) -> [String: Any] {
        var placement: [String: Any] = [
            "presenceType": item.presenceType,
            "location": NSNull(),
            "organization": NSNull()
        ]
        if let lid = item.locationId, let loc = locations.first(where: { $0.id == lid }) {
            placement["location"] = ["id": loc.id, "name": loc.name]
        }
        if let oid = item.organizationId, let org = organizations.first(where: { $0.id == oid }) {
            placement["organization"] = ["id": org.id, "name": org.name]
        }
        var planning: [String: Any] = [
            "promisedOrganization": NSNull(),
            "expectedLeaveDate": NSNull()
        ]
        if let pid = item.promisedOrgId, let org = organizations.first(where: { $0.id == pid }) {
            planning["promisedOrganization"] = ["id": org.id, "name": org.name]
        }
        if let date = item.expectedLeaveDate {
            planning["expectedLeaveDate"] = date
        }
        let authorsArr: [[String: Any]] = item.authorIds.compactMap { aid in
            guard let a = authors.first(where: { $0.id == aid }) else { return nil }
            return ["id": a.id, "name": a.name]
        }
        return [
            "id": item.id,
            "mainInventoryNumber": item.mainInventoryNumber,
            "title": item.title,
            "secondaryInventoryNumbers": item.secondaryInventoryNumbers,
            "authors": authorsArr,
            "currentPlacement": placement,
            "planning": planning,
            "archived": item.archived
        ]
    }

    private func locationDict(_ loc: DemoLocation) -> [String: Any] {
        ["id": loc.id, "name": loc.name, "archived": loc.archived]
    }

    private func authorDict(_ a: DemoAuthor) -> [String: Any] {
        ["id": a.id, "name": a.name, "archived": a.archived]
    }

    private func orgDict(_ o: DemoOrg) -> [String: Any] {
        ["id": o.id, "name": o.name, "archived": o.archived]
    }

    // MARK: - Helpers

    private func success(_ data: Data) -> (Int, Data?) { (200, data) }

    private func dictData(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data()
    }

    private func arrayData(_ array: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: array, options: [])) ?? Data()
    }

    private func extractTrailingId(path: String, prefix: String, suffix: String?) -> Int64? {
        guard path.hasPrefix(prefix) else { return nil }
        var trimmed = String(path.dropFirst(prefix.count))
        if let suffix {
            guard trimmed.hasSuffix(suffix) else { return nil }
            trimmed = String(trimmed.dropLast(suffix.count))
        }
        if trimmed.contains("/") { return nil }
        return Int64(trimmed)
    }

    private func isoTimestamp(addingHours hours: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(hours * 3600))
    }

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

// MARK: - In-memory models

private struct DemoItem {
    var id: Int64
    var mainInventoryNumber: String
    var title: String
    var secondaryInventoryNumbers: [String]
    var authorIds: [Int64]
    var presenceType: String
    var locationId: Int64?
    var organizationId: Int64?
    var promisedOrgId: Int64?
    var expectedLeaveDate: String?
    var archived: Bool
}

private struct DemoLocation { var id: Int64; var name: String; var archived: Bool }
private struct DemoAuthor { var id: Int64; var name: String; var archived: Bool }
private struct DemoOrg { var id: Int64; var name: String; var archived: Bool }

private struct DemoHistory {
    var id: Int64
    var presenceType: String
    var locationId: Int64?
    var organizationId: Int64?
    var moveInDate: String
    var moveOutDate: String?
    var expectedReturnDate: String?
}

private enum DemoSeed {
    static func build() -> (
        items: [DemoItem],
        locations: [DemoLocation],
        authors: [DemoAuthor],
        organizations: [DemoOrg],
        history: [Int64: [DemoHistory]]
    ) {
        let locations: [DemoLocation] = [
            DemoLocation(id: 1, name: "Hall A", archived: false),
            DemoLocation(id: 2, name: "Hall B", archived: false),
            DemoLocation(id: 3, name: "Storage 1", archived: false),
            DemoLocation(id: 4, name: "Gallery 2", archived: false),
            DemoLocation(id: 5, name: "Restoration room", archived: false),
            DemoLocation(id: 6, name: "Old wing (archived)", archived: true),
        ]
        let authors: [DemoAuthor] = [
            DemoAuthor(id: 1, name: "Ivan Shishkin", archived: false),
            DemoAuthor(id: 2, name: "Claude Monet", archived: false),
            DemoAuthor(id: 3, name: "Unknown Workshop", archived: false),
            DemoAuthor(id: 4, name: "Vincent van Gogh", archived: false),
            DemoAuthor(id: 5, name: "Pablo Picasso", archived: false),
        ]
        let orgs: [DemoOrg] = [
            DemoOrg(id: 1, name: "Museum of Rome", archived: false),
            DemoOrg(id: 2, name: "Hermitage", archived: false),
            DemoOrg(id: 3, name: "Louvre", archived: false),
            DemoOrg(id: 4, name: "Tate Modern", archived: false),
        ]
        let items: [DemoItem] = [
            DemoItem(
                id: 1,
                mainInventoryNumber: "INV-2026-001",
                title: "Landscape with river",
                secondaryInventoryNumbers: ["A-15"],
                authorIds: [1],
                presenceType: "INTERNAL",
                locationId: 4,
                organizationId: nil,
                promisedOrgId: nil,
                expectedLeaveDate: nil,
                archived: false
            ),
            DemoItem(
                id: 2,
                mainInventoryNumber: "INV-2026-002",
                title: "Water Lilies study",
                secondaryInventoryNumbers: [],
                authorIds: [2],
                presenceType: "EXTERNAL",
                locationId: nil,
                organizationId: 1,
                promisedOrgId: nil,
                expectedLeaveDate: nil,
                archived: false
            ),
            DemoItem(
                id: 3,
                mainInventoryNumber: "INV-2026-003",
                title: "Mask of the Harvest Festival",
                secondaryInventoryNumbers: ["TEMP-77", "B-9"],
                authorIds: [3],
                presenceType: "INTERNAL",
                locationId: 1,
                organizationId: nil,
                promisedOrgId: 2,
                expectedLeaveDate: "2026-06-15",
                archived: false
            ),
            DemoItem(
                id: 4,
                mainInventoryNumber: "INV-2026-004",
                title: "Starry Night sketch",
                secondaryInventoryNumbers: [],
                authorIds: [4],
                presenceType: "INTERNAL",
                locationId: 3,
                organizationId: nil,
                promisedOrgId: nil,
                expectedLeaveDate: nil,
                archived: false
            ),
            DemoItem(
                id: 5,
                mainInventoryNumber: "INV-2026-005",
                title: "Bronze figurine, archaic",
                secondaryInventoryNumbers: ["TEMP-12"],
                authorIds: [3],
                presenceType: "INTERNAL",
                locationId: 2,
                organizationId: nil,
                promisedOrgId: nil,
                expectedLeaveDate: nil,
                archived: false
            ),
            DemoItem(
                id: 6,
                mainInventoryNumber: "INV-2026-006",
                title: "Cubist composition",
                secondaryInventoryNumbers: [],
                authorIds: [5],
                presenceType: "INTERNAL",
                locationId: 4,
                organizationId: nil,
                promisedOrgId: 4,
                expectedLeaveDate: "2026-09-01",
                archived: false
            ),
            DemoItem(
                id: 7,
                mainInventoryNumber: "INV-2025-099",
                title: "Forgotten relic",
                secondaryInventoryNumbers: [],
                authorIds: [3],
                presenceType: "INTERNAL",
                locationId: 3,
                organizationId: nil,
                promisedOrgId: nil,
                expectedLeaveDate: nil,
                archived: true
            ),
        ]
        let history: [Int64: [DemoHistory]] = [
            1: [
                DemoHistory(id: 1, presenceType: "INTERNAL", locationId: 4, organizationId: nil, moveInDate: "2024-05-15", moveOutDate: nil, expectedReturnDate: nil)
            ],
            2: [
                DemoHistory(id: 2, presenceType: "INTERNAL", locationId: 2, organizationId: nil, moveInDate: "2023-09-01", moveOutDate: "2026-04-10", expectedReturnDate: nil),
                DemoHistory(id: 3, presenceType: "EXTERNAL", locationId: nil, organizationId: 1, moveInDate: "2026-04-10", moveOutDate: nil, expectedReturnDate: "2026-08-10"),
            ],
            3: [
                DemoHistory(id: 4, presenceType: "INTERNAL", locationId: 5, organizationId: nil, moveInDate: "2025-06-01", moveOutDate: "2025-12-01", expectedReturnDate: nil),
                DemoHistory(id: 5, presenceType: "INTERNAL", locationId: 1, organizationId: nil, moveInDate: "2025-12-01", moveOutDate: nil, expectedReturnDate: nil),
            ],
            4: [
                DemoHistory(id: 6, presenceType: "INTERNAL", locationId: 3, organizationId: nil, moveInDate: "2024-02-12", moveOutDate: nil, expectedReturnDate: nil)
            ],
            5: [
                DemoHistory(id: 7, presenceType: "INTERNAL", locationId: 2, organizationId: nil, moveInDate: "2025-01-20", moveOutDate: nil, expectedReturnDate: nil)
            ],
            6: [
                DemoHistory(id: 8, presenceType: "INTERNAL", locationId: 4, organizationId: nil, moveInDate: "2025-11-05", moveOutDate: nil, expectedReturnDate: nil)
            ],
        ]
        return (items, locations, authors, orgs, history)
    }
}

// MARK: - URL helpers

private extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

#endif
