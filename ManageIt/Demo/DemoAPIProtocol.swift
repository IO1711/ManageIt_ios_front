#if DEBUG
import Foundation

final class DemoAPIProtocol: URLProtocol {
    nonisolated(unsafe) static var isEnabled = false
    static let store = DemoDataStore()

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

final class DemoDataStore: @unchecked Sendable {
    private let lock = NSLock()

    private var items: [DemoItem]
    private var locations: [DemoLocation]
    private var authors: [DemoAuthor]
    private var organizations: [DemoOrg]
    private var history: [Int64: [DemoHistory]]
    private var exhibitions: [DemoExhibition]
    private var nextItemId: Int64
    private var nextLocationId: Int64
    private var nextAuthorId: Int64
    private var nextOrgId: Int64
    private var nextHistoryId: Int64
    private var nextExhibitionId: Int64

    init() {
        let seed = DemoSeed.build()
        items = seed.items
        locations = seed.locations
        authors = seed.authors
        organizations = seed.organizations
        history = seed.history
        exhibitions = seed.exhibitions
        nextItemId = (seed.items.map(\.id).max() ?? 0) + 1
        nextLocationId = (seed.locations.map(\.id).max() ?? 0) + 1
        nextAuthorId = (seed.authors.map(\.id).max() ?? 0) + 1
        nextOrgId = (seed.organizations.map(\.id).max() ?? 0) + 1
        nextHistoryId = (seed.history.values.flatMap { $0 }.map(\.id).max() ?? 0) + 1
        nextExhibitionId = (seed.exhibitions.map(\.id).max() ?? 0) + 1
    }

    func respond(to request: URLRequest) -> (Int, Data?) {
        lock.lock()
        defer { lock.unlock() }

        guard let url = request.url else { return (404, nil) }
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let bodyData = request.httpBody ?? Self.readStream(request.httpBodyStream)

        if method == "POST" && path == "/api/auth/refresh" {
            return success(refreshResponseJSON())
        }
        if method == "POST" && path == "/api/auth/logout" {
            return (204, nil)
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
            guard let item = createItem(bodyData: bodyData) else { return (400, nil) }
            return success(itemJSON(item))
        }
        if method == "GET" && path == "/api/locations" {
            let includeArchived = url.queryValue("includeArchived") == "true"
            let filtered = includeArchived ? locations : locations.filter { !$0.archived }
            return success(arrayData(sortLocations(filtered).map(locationDict)))
        }
        if method == "POST" && path == "/api/locations" {
            guard let location = createLocation(bodyData: bodyData) else { return (400, nil) }
            return success(dictData(locationDict(location)))
        }
        if method == "GET" && path == "/api/authors" {
            let q = url.queryValue("q")?.lowercased() ?? ""
            let filtered = authors.filter { !$0.archived && (q.isEmpty || $0.name.lowercased().contains(q)) }
            return success(arrayData(filtered.map(authorDict)))
        }
        if method == "POST" && path == "/api/authors" {
            guard let author = createAuthor(bodyData: bodyData) else { return (400, nil) }
            return success(dictData(authorDict(author)))
        }
        if method == "GET" && path == "/api/organizations" {
            let q = url.queryValue("q")?.lowercased() ?? ""
            let filtered = organizations.filter { !$0.archived && (q.isEmpty || $0.name.lowercased().contains(q)) }
            return success(arrayData(filtered.map(orgDict)))
        }
        if method == "POST" && path == "/api/organizations" {
            guard let organization = createOrg(bodyData: bodyData) else { return (400, nil) }
            return success(dictData(orgDict(organization)))
        }
        if method == "GET" && path == "/api/exhibitions" {
            return success(arrayData(sortedExhibitions().map(exhibitionSummaryDict)))
        }
        if method == "POST" && path == "/api/exhibitions" {
            guard let exhibition = createExhibition(bodyData: bodyData) else { return (400, nil) }
            return success(dictData(exhibitionDetailDict(exhibition)))
        }

        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/history"), method == "GET" {
            return success(historyJSON(itemId: id))
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/movements"), method == "POST" {
            guard let item = createMovement(itemId: id, bodyData: bodyData) else { return (404, nil) }
            return success(itemJSON(item))
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/planning"), method == "PATCH" {
            guard let item = updatePlanning(itemId: id, bodyData: bodyData) else { return (404, nil) }
            return success(itemJSON(item))
        }
        if let id = extractTrailingId(path: path, prefix: "/api/items/", suffix: "/archive"), method == "POST" {
            guard let item = archiveItem(itemId: id) else { return (404, nil) }
            return success(itemJSON(item))
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
            guard let location = archiveLocation(id: id) else { return (404, nil) }
            return success(dictData(locationDict(location)))
        }
        if let id = extractTrailingId(path: path, prefix: "/api/locations/", suffix: nil), method == "PUT" {
            guard let location = updateLocation(id: id, bodyData: bodyData) else { return (404, nil) }
            return success(dictData(locationDict(location)))
        }
        if let id = extractTrailingId(path: path, prefix: "/api/exhibitions/", suffix: nil) {
            if method == "GET", let exhibition = exhibitions.first(where: { $0.id == id }) {
                return success(dictData(exhibitionDetailDict(exhibition)))
            }
            if method == "PUT", let exhibition = updateExhibition(id: id, bodyData: bodyData) {
                return success(dictData(exhibitionDetailDict(exhibition)))
            }
        }

        return (404, nil)
    }

    private func createItem(bodyData: Data?) -> DemoItem? {
        guard
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let id = nextItemId
        nextItemId += 1

        let authorIds = parseAuthorIDs(json["authors"] as? [[String: Any]])
        let locationId = parseInt64(json["initialLocationId"])
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

        if let moveInDate = json["moveInDate"] as? String, let locationId {
            history[item.id, default: []].append(
                DemoHistory(
                    id: nextHistoryId,
                    presenceType: "INTERNAL",
                    locationId: locationId,
                    organizationId: nil,
                    moveInDate: moveInDate,
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: .demoIOS
                )
            )
            nextHistoryId += 1
        }

        return item
    }

    private func updateItem(itemId: Int64, bodyData: Data?) -> DemoItem? {
        guard
            let idx = items.firstIndex(where: { $0.id == itemId }),
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var item = items[idx]
        if let value = json["mainInventoryNumber"] as? String { item.mainInventoryNumber = value }
        if let value = json["title"] as? String { item.title = value }
        if let value = json["secondaryInventoryNumbers"] as? [String] { item.secondaryInventoryNumbers = value }
        if let authorsJSON = json["authors"] as? [[String: Any]] {
            item.authorIds = parseAuthorIDs(authorsJSON)
        }
        items[idx] = item
        return item
    }

    private func updatePlanning(itemId: Int64, bodyData: Data?) -> DemoItem? {
        guard
            let idx = items.firstIndex(where: { $0.id == itemId }),
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var item = items[idx]

        if let orgInput = json["promisedOrganization"] as? [String: Any] {
            item.promisedOrgId = resolveOrganizationID(orgInput)
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
        guard
            let idx = items.firstIndex(where: { $0.id == itemId }),
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var item = items[idx]
        let presenceType = (json["presenceType"] as? String) ?? "INTERNAL"
        let moveInDate = (json["moveInDate"] as? String) ?? "2026-01-01"
        var rows = history[item.id] ?? []

        if let openIndex = rows.firstIndex(where: { $0.moveOutDate == nil }) {
            rows[openIndex].moveOutDate = moveInDate
        }

        if presenceType == "INTERNAL" {
            let locationId = parseInt64(json["locationId"])
            item.presenceType = "INTERNAL"
            item.locationId = locationId
            item.organizationId = nil
            item.promisedOrgId = nil
            item.expectedLeaveDate = nil

            rows.append(
                DemoHistory(
                    id: nextHistoryId,
                    presenceType: "INTERNAL",
                    locationId: locationId,
                    organizationId: nil,
                    moveInDate: moveInDate,
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: .demoIOS
                )
            )
        } else {
            let organizationId = resolveOrganizationID(json["organization"] as? [String: Any])
            item.presenceType = "EXTERNAL"
            item.organizationId = organizationId
            item.locationId = nil
            item.promisedOrgId = nil
            item.expectedLeaveDate = nil

            rows.append(
                DemoHistory(
                    id: nextHistoryId,
                    presenceType: "EXTERNAL",
                    locationId: nil,
                    organizationId: organizationId,
                    moveInDate: moveInDate,
                    moveOutDate: nil,
                    expectedReturnDate: json["expectedReturnDate"] as? String,
                    movedByDevice: .demoIOS
                )
            )
        }

        nextHistoryId += 1
        history[item.id] = rows
        items[idx] = item
        return item
    }

    private func createLocation(bodyData: Data?) -> DemoLocation? {
        guard
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String
        else {
            return nil
        }

        let location = DemoLocation(
            id: nextLocationId,
            name: name,
            parentLocationId: parseInt64(json["parentLocationId"]),
            archived: false
        )
        nextLocationId += 1
        locations.append(location)
        return location
    }

    private func updateLocation(id: Int64, bodyData: Data?) -> DemoLocation? {
        guard
            let idx = locations.firstIndex(where: { $0.id == id }),
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String
        else {
            return nil
        }

        locations[idx].name = name
        return locations[idx]
    }

    private func archiveLocation(id: Int64) -> DemoLocation? {
        guard let idx = locations.firstIndex(where: { $0.id == id }) else { return nil }
        locations[idx].archived = true
        return locations[idx]
    }

    private func createExhibition(bodyData: Data?) -> DemoExhibition? {
        guard
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String,
            let locationId = parseInt64(json["locationId"]),
            let startDate = json["startDate"] as? String,
            let endDate = json["endDate"] as? String,
            let itemIds = parseInt64Array(json["itemIds"])
        else {
            return nil
        }

        let exhibition = DemoExhibition(
            id: nextExhibitionId,
            name: name,
            locationId: locationId,
            startDate: startDate,
            endDate: endDate,
            itemIds: itemIds
        )
        nextExhibitionId += 1
        exhibitions.append(exhibition)
        return exhibition
    }

    private func updateExhibition(id: Int64, bodyData: Data?) -> DemoExhibition? {
        guard
            let idx = exhibitions.firstIndex(where: { $0.id == id }),
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String,
            let locationId = parseInt64(json["locationId"]),
            let startDate = json["startDate"] as? String,
            let endDate = json["endDate"] as? String,
            let itemIds = parseInt64Array(json["itemIds"])
        else {
            return nil
        }

        exhibitions[idx].name = name
        exhibitions[idx].locationId = locationId
        exhibitions[idx].startDate = startDate
        exhibitions[idx].endDate = endDate
        exhibitions[idx].itemIds = itemIds
        return exhibitions[idx]
    }

    private func createAuthor(bodyData: Data?) -> DemoAuthor? {
        guard
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String
        else {
            return nil
        }

        if let existing = authors.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }

        let author = DemoAuthor(id: nextAuthorId, name: name, archived: false)
        nextAuthorId += 1
        authors.append(author)
        return author
    }

    private func createOrg(bodyData: Data?) -> DemoOrg? {
        guard
            let data = bodyData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String
        else {
            return nil
        }

        if let existing = organizations.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }

        let organization = DemoOrg(id: nextOrgId, name: name, archived: false)
        nextOrgId += 1
        organizations.append(organization)
        return organization
    }

    private func refreshResponseJSON() -> Data {
        dictData([
            "deviceId": "11111111-1111-1111-1111-111111111111",
            "role": "ADMIN",
            "deviceType": "IOS_APP",
            "friendlyName": "Demo iPhone",
            "accessToken": "demo-access-token",
            "accessTokenExpiresAt": isoTimestamp(addingHours: 1),
            "refreshTokenExpiresAt": isoTimestamp(addingHours: 24 * 30)
        ])
    }

    private func meResponseJSON() -> Data {
        dictData([
            "authenticated": true,
            "deviceId": "11111111-1111-1111-1111-111111111111",
            "role": "ADMIN",
            "deviceType": "IOS_APP",
            "friendlyName": "Demo iPhone"
        ])
    }

    private func conflictJSON(url: URL) -> Data {
        let number = url.queryValue("mainInventoryNumber") ?? ""
        let conflict = items.first {
            $0.mainInventoryNumber.lowercased() == number.lowercased() && !$0.archived
        }
        var body: [String: Any] = [
            "available": conflict == nil,
            "mainInventoryNumber": number,
            "conflictingItem": NSNull()
        ]

        if let conflict {
            body["conflictingItem"] = [
                "id": conflict.id,
                "title": conflict.title,
                "currentPresenceType": conflict.presenceType,
                "currentLocationName": conflict.locationId.flatMap(locationFullPath(for:)) ?? NSNull()
            ]
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
                let authorNames = item.authorIds.compactMap { id in
                    authors.first(where: { $0.id == id })?.name.lowercased()
                }
                if authorNames.contains(where: { $0.contains(q) }) { return true }
                if let locationId = item.locationId,
                   let fullPath = locationFullPath(for: locationId),
                   fullPath.lowercased().contains(q) {
                    return true
                }
                if let organizationId = item.organizationId,
                   let organization = organizations.first(where: { $0.id == organizationId }),
                   organization.name.lowercased().contains(q) {
                    return true
                }
                return false
            }
        }

        let start = page * size
        let end = min(start + size, filtered.count)
        let pageItems = start < filtered.count ? Array(filtered[start..<end]) : []
        let totalItems = filtered.count
        let totalPages = totalItems == 0 ? 0 : Int((Double(totalItems) / Double(size)).rounded(.up))

        return dictData([
            "items": pageItems.map(itemDict),
            "page": page,
            "size": size,
            "totalItems": totalItems,
            "totalPages": totalPages
        ])
    }

    private func historyJSON(itemId: Int64) -> Data {
        let rows = (history[itemId] ?? []).sorted { lhs, rhs in
            if lhs.moveInDate != rhs.moveInDate {
                return lhs.moveInDate > rhs.moveInDate
            }
            return lhs.id > rhs.id
        }

        let payload = rows.map { row -> [String: Any] in
            var dict: [String: Any] = [
                "id": row.id,
                "presenceType": row.presenceType,
                "location": NSNull(),
                "organization": NSNull(),
                "moveInDate": row.moveInDate,
                "moveOutDate": row.moveOutDate as Any? ?? NSNull(),
                "expectedReturnDate": row.expectedReturnDate as Any? ?? NSNull(),
                "movedByDevice": NSNull(),
                "createdAt": isoTimestamp(forBusinessDate: row.moveInDate)
            ]

            if let locationId = row.locationId, let location = locationSummaryDict(for: locationId) {
                dict["location"] = location
            }
            if let organizationId = row.organizationId,
               let organization = organizations.first(where: { $0.id == organizationId }) {
                dict["organization"] = ["id": organization.id, "name": organization.name]
            }
            if let movedByDevice = row.movedByDevice {
                dict["movedByDevice"] = movedByDevice.dict
            }

            return dict
        }

        return dictData(["entries": payload])
    }

    private func itemJSON(_ item: DemoItem) -> Data {
        dictData(itemDict(item))
    }

    private func itemDict(_ item: DemoItem) -> [String: Any] {
        let openHistory = openHistoryRow(for: item.id)
        var placement: [String: Any] = [
            "presenceType": item.presenceType,
            "location": NSNull(),
            "organization": NSNull(),
            "expectedReturnDate": openHistory?.expectedReturnDate as Any? ?? NSNull()
        ]

        if let locationId = item.locationId, let location = locationSummaryDict(for: locationId) {
            placement["location"] = location
        }
        if let organizationId = item.organizationId,
           let organization = organizations.first(where: { $0.id == organizationId }) {
            placement["organization"] = ["id": organization.id, "name": organization.name]
        }

        var planning: [String: Any] = [
            "promisedOrganization": NSNull(),
            "expectedLeaveDate": item.expectedLeaveDate as Any? ?? NSNull()
        ]
        if let promisedOrgId = item.promisedOrgId,
           let organization = organizations.first(where: { $0.id == promisedOrgId }) {
            planning["promisedOrganization"] = ["id": organization.id, "name": organization.name]
        }

        let authorPayload: [[String: Any]] = item.authorIds.compactMap { authorId in
            guard let author = authors.first(where: { $0.id == authorId }) else { return nil }
            return ["id": author.id, "name": author.name]
        }

        return [
            "id": item.id,
            "mainInventoryNumber": item.mainInventoryNumber,
            "title": item.title,
            "secondaryInventoryNumbers": item.secondaryInventoryNumbers,
            "authors": authorPayload,
            "currentPlacement": placement,
            "planning": planning,
            "archived": item.archived
        ]
    }

    private func locationDict(_ location: DemoLocation) -> [String: Any] {
        [
            "id": location.id,
            "name": location.name,
            "parentLocationId": location.parentLocationId as Any? ?? NSNull(),
            "fullPath": locationFullPath(for: location.id) ?? location.name,
            "leaf": isLeaf(location.id),
            "assignable": isLeaf(location.id) && !location.archived,
            "archived": location.archived
        ]
    }

    private func exhibitionSummaryDict(_ exhibition: DemoExhibition) -> [String: Any] {
        [
            "id": exhibition.id,
            "name": exhibition.name,
            "locationId": exhibition.locationId,
            "locationPath": locationFullPath(for: exhibition.locationId) ?? "Unknown location",
            "startDate": exhibition.startDate,
            "endDate": exhibition.endDate,
            "phase": exhibitionPhase(for: exhibition),
            "itemCount": exhibition.itemIds.count
        ]
    }

    private func exhibitionDetailDict(_ exhibition: DemoExhibition) -> [String: Any] {
        let location = locations.first(where: { $0.id == exhibition.locationId })
        let locationPayload: [String: Any] = [
            "id": exhibition.locationId,
            "name": location?.name ?? "Unknown location",
            "fullPath": locationFullPath(for: exhibition.locationId) ?? "Unknown location"
        ]

        let itemsPayload: [[String: Any]] = exhibition.itemIds.compactMap { itemId in
            guard let item = items.first(where: { $0.id == itemId }) else { return nil }
            return [
                "id": item.id,
                "mainInventoryNumber": item.mainInventoryNumber,
                "title": item.title
            ]
        }

        return [
            "id": exhibition.id,
            "name": exhibition.name,
            "location": locationPayload,
            "startDate": exhibition.startDate,
            "endDate": exhibition.endDate,
            "phase": exhibitionPhase(for: exhibition),
            "items": itemsPayload
        ]
    }

    private func locationSummaryDict(for locationId: Int64) -> [String: Any]? {
        guard let location = locations.first(where: { $0.id == locationId }) else { return nil }
        return [
            "id": location.id,
            "name": location.name,
            "fullPath": locationFullPath(for: location.id) ?? location.name
        ]
    }

    private func openHistoryRow(for itemId: Int64) -> DemoHistory? {
        history[itemId]?.last(where: { $0.moveOutDate == nil })
    }

    private func resolveOrganizationID(_ orgInput: [String: Any]?) -> Int64? {
        guard let orgInput else { return nil }

        if let organizationId = parseInt64(orgInput["id"]) {
            return organizationId
        }

        if let name = orgInput["name"] as? String, !name.isEmpty {
            if let existing = organizations.first(where: { $0.name.lowercased() == name.lowercased() }) {
                return existing.id
            }
            let created = DemoOrg(id: nextOrgId, name: name, archived: false)
            nextOrgId += 1
            organizations.append(created)
            return created.id
        }

        return nil
    }

    private func parseAuthorIDs(_ authorsJSON: [[String: Any]]?) -> [Int64] {
        guard let authorsJSON else { return [] }

        return authorsJSON.compactMap { input in
            if let authorId = parseInt64(input["id"]) {
                return authorId
            }

            if let name = input["name"] as? String, !name.isEmpty {
                if let existing = authors.first(where: { $0.name.lowercased() == name.lowercased() }) {
                    return existing.id
                }
                let created = DemoAuthor(id: nextAuthorId, name: name, archived: false)
                nextAuthorId += 1
                authors.append(created)
                return created.id
            }

            return nil
        }
    }

    private func parseInt64(_ raw: Any?) -> Int64? {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? NSNumber { return value.int64Value }
        return nil
    }

    private func parseInt64Array(_ raw: Any?) -> [Int64]? {
        guard let array = raw as? [Any] else { return nil }
        return array.compactMap(parseInt64)
    }

    private func locationFullPath(for locationId: Int64) -> String? {
        guard let location = locations.first(where: { $0.id == locationId }) else { return nil }
        if let parentId = location.parentLocationId, let parentPath = locationFullPath(for: parentId) {
            return "\(parentPath) > \(location.name)"
        }
        return location.name
    }

    private func isLeaf(_ locationId: Int64) -> Bool {
        !locations.contains { $0.parentLocationId == locationId }
    }

    private func sortLocations(_ locations: [DemoLocation]) -> [DemoLocation] {
        locations.sorted { lhs, rhs in
            let lhsPath = locationFullPath(for: lhs.id) ?? lhs.name
            let rhsPath = locationFullPath(for: rhs.id) ?? rhs.name
            return lhsPath.localizedCaseInsensitiveCompare(rhsPath) == .orderedAscending
        }
    }

    private func sortedExhibitions() -> [DemoExhibition] {
        exhibitions.sorted { lhs, rhs in
            let lhsPhase = exhibitionPhaseOrder(exhibitionPhase(for: lhs))
            let rhsPhase = exhibitionPhaseOrder(exhibitionPhase(for: rhs))
            if lhsPhase != rhsPhase {
                return lhsPhase < rhsPhase
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func exhibitionPhase(for exhibition: DemoExhibition) -> String {
        let today = "2026-06-01"
        if exhibition.endDate < today {
            return "ENDED"
        }
        if exhibition.startDate > today {
            return "PLANNED"
        }
        return "ACTIVE"
    }

    private func exhibitionPhaseOrder(_ phase: String) -> Int {
        switch phase {
        case "ACTIVE":
            return 0
        case "PLANNED":
            return 1
        default:
            return 2
        }
    }

    private func authorDict(_ author: DemoAuthor) -> [String: Any] {
        ["id": author.id, "name": author.name, "archived": author.archived]
    }

    private func orgDict(_ organization: DemoOrg) -> [String: Any] {
        ["id": organization.id, "name": organization.name, "archived": organization.archived]
    }

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

    private func isoTimestamp(forBusinessDate date: String) -> String {
        "\(date)T10:00:00Z"
    }

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

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

private struct DemoLocation {
    var id: Int64
    var name: String
    var parentLocationId: Int64?
    var archived: Bool
}

private struct DemoAuthor {
    var id: Int64
    var name: String
    var archived: Bool
}

private struct DemoOrg {
    var id: Int64
    var name: String
    var archived: Bool
}

private struct DemoHistory {
    var id: Int64
    var presenceType: String
    var locationId: Int64?
    var organizationId: Int64?
    var moveInDate: String
    var moveOutDate: String?
    var expectedReturnDate: String?
    var movedByDevice: DemoMovedByDevice?
}

private struct DemoMovedByDevice {
    let id: String
    let friendlyName: String
    let deviceType: String

    static let demoIOS = DemoMovedByDevice(
        id: "11111111-1111-1111-1111-111111111111",
        friendlyName: "Demo iPhone",
        deviceType: "IOS_APP"
    )

    static let frontDeskWeb = DemoMovedByDevice(
        id: "3f56cde0-9b72-44fd-b74c-b0dfc039de3a",
        friendlyName: "Front Desk Chrome",
        deviceType: "WEB_BROWSER"
    )

    var dict: [String: Any] {
        [
            "id": id,
            "friendlyName": friendlyName,
            "deviceType": deviceType
        ]
    }
}

private struct DemoExhibition {
    var id: Int64
    var name: String
    var locationId: Int64
    var startDate: String
    var endDate: String
    var itemIds: [Int64]
}

private enum DemoSeed {
    static func build() -> (
        items: [DemoItem],
        locations: [DemoLocation],
        authors: [DemoAuthor],
        organizations: [DemoOrg],
        history: [Int64: [DemoHistory]],
        exhibitions: [DemoExhibition]
    ) {
        let locations: [DemoLocation] = [
            DemoLocation(id: 1, name: "Hall A", parentLocationId: nil, archived: false),
            DemoLocation(id: 2, name: "Shelf 1", parentLocationId: 1, archived: false),
            DemoLocation(id: 3, name: "Shelf 2", parentLocationId: 1, archived: false),
            DemoLocation(id: 4, name: "Gallery 2", parentLocationId: nil, archived: false),
            DemoLocation(id: 5, name: "Case 4", parentLocationId: 4, archived: false),
            DemoLocation(id: 6, name: "Restoration room", parentLocationId: nil, archived: false),
            DemoLocation(id: 7, name: "Old wing", parentLocationId: nil, archived: true)
        ]

        let authors: [DemoAuthor] = [
            DemoAuthor(id: 1, name: "Ivan Shishkin", archived: false),
            DemoAuthor(id: 2, name: "Claude Monet", archived: false),
            DemoAuthor(id: 3, name: "Unknown Workshop", archived: false),
            DemoAuthor(id: 4, name: "Vincent van Gogh", archived: false),
            DemoAuthor(id: 5, name: "Pablo Picasso", archived: false)
        ]

        let organizations: [DemoOrg] = [
            DemoOrg(id: 1, name: "Museum of Rome", archived: false),
            DemoOrg(id: 2, name: "Hermitage", archived: false),
            DemoOrg(id: 3, name: "Louvre", archived: false),
            DemoOrg(id: 4, name: "Tate Modern", archived: false)
        ]

        let items: [DemoItem] = [
            DemoItem(
                id: 1,
                mainInventoryNumber: "INV-2026-001",
                title: "Landscape with river",
                secondaryInventoryNumbers: ["A-15"],
                authorIds: [1],
                presenceType: "INTERNAL",
                locationId: 5,
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
                locationId: 2,
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
                locationId: 6,
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
                locationId: 3,
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
                locationId: 5,
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
                locationId: 6,
                organizationId: nil,
                promisedOrgId: nil,
                expectedLeaveDate: nil,
                archived: true
            )
        ]

        let history: [Int64: [DemoHistory]] = [
            1: [
                DemoHistory(
                    id: 1,
                    presenceType: "INTERNAL",
                    locationId: 5,
                    organizationId: nil,
                    moveInDate: "2024-05-15",
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: .frontDeskWeb
                )
            ],
            2: [
                DemoHistory(
                    id: 2,
                    presenceType: "INTERNAL",
                    locationId: 3,
                    organizationId: nil,
                    moveInDate: "2023-09-01",
                    moveOutDate: "2026-04-10",
                    expectedReturnDate: nil,
                    movedByDevice: nil
                ),
                DemoHistory(
                    id: 3,
                    presenceType: "EXTERNAL",
                    locationId: nil,
                    organizationId: 1,
                    moveInDate: "2026-04-10",
                    moveOutDate: nil,
                    expectedReturnDate: "2026-08-10",
                    movedByDevice: .frontDeskWeb
                )
            ],
            3: [
                DemoHistory(
                    id: 4,
                    presenceType: "INTERNAL",
                    locationId: 6,
                    organizationId: nil,
                    moveInDate: "2025-06-01",
                    moveOutDate: "2025-12-01",
                    expectedReturnDate: nil,
                    movedByDevice: .demoIOS
                ),
                DemoHistory(
                    id: 5,
                    presenceType: "INTERNAL",
                    locationId: 2,
                    organizationId: nil,
                    moveInDate: "2025-12-01",
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: .demoIOS
                )
            ],
            4: [
                DemoHistory(
                    id: 6,
                    presenceType: "INTERNAL",
                    locationId: 6,
                    organizationId: nil,
                    moveInDate: "2024-02-12",
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: .demoIOS
                )
            ],
            5: [
                DemoHistory(
                    id: 7,
                    presenceType: "INTERNAL",
                    locationId: 3,
                    organizationId: nil,
                    moveInDate: "2025-01-20",
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: nil
                )
            ],
            6: [
                DemoHistory(
                    id: 8,
                    presenceType: "INTERNAL",
                    locationId: 5,
                    organizationId: nil,
                    moveInDate: "2025-11-05",
                    moveOutDate: nil,
                    expectedReturnDate: nil,
                    movedByDevice: .frontDeskWeb
                )
            ]
        ]

        let exhibitions: [DemoExhibition] = [
            DemoExhibition(
                id: 1,
                name: "Summer Landscapes",
                locationId: 5,
                startDate: "2026-05-15",
                endDate: "2026-06-20",
                itemIds: [1, 6]
            ),
            DemoExhibition(
                id: 2,
                name: "Autumn Masks 2026",
                locationId: 2,
                startDate: "2026-09-12",
                endDate: "2026-10-20",
                itemIds: [3, 5]
            ),
            DemoExhibition(
                id: 3,
                name: "Bronze Stories",
                locationId: 3,
                startDate: "2026-03-01",
                endDate: "2026-04-05",
                itemIds: [5]
            )
        ]

        return (items, locations, authors, organizations, history, exhibitions)
    }
}

private extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

#endif
