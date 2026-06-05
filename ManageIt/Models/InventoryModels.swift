import Foundation

enum ItemPresenceType: String, Codable, Equatable {
    case `internal` = "INTERNAL"
    case external = "EXTERNAL"
}

struct ItemAuthorSummary: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
}

struct ItemLocationSummary: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let fullPath: String

    var displayName: String {
        fullPath.isEmpty ? name : fullPath
    }
}

struct ItemOrganizationSummary: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
}

struct ItemPlacement: Codable, Equatable {
    let presenceType: ItemPresenceType
    let location: ItemLocationSummary?
    let organization: ItemOrganizationSummary?
    let expectedReturnDate: BusinessDate?

    var displayTargetName: String {
        switch presenceType {
        case .internal:
            return location?.displayName ?? "—"
        case .external:
            return organization?.name ?? "—"
        }
    }
}

struct ItemPlanning: Codable, Equatable {
    let promisedOrganization: ItemOrganizationSummary?
    let expectedLeaveDate: BusinessDate?
}

struct ItemResponse: Decodable, Equatable, Identifiable {
    let id: Int64
    let mainInventoryNumber: String
    let title: String
    let secondaryInventoryNumbers: [String]
    let authors: [ItemAuthorSummary]
    let currentPlacement: ItemPlacement
    let planning: ItemPlanning
    let archived: Bool

    var authorNames: String {
        if authors.isEmpty { return "—" }
        return authors.map(\.name).joined(separator: ", ")
    }
}

struct ItemListResponse: Decodable, Equatable {
    let items: [ItemResponse]
    let page: Int
    let size: Int
    let totalItems: Int64
    let totalPages: Int
}

struct ItemAuthorInput: Encodable, Equatable {
    let id: Int64?
    let name: String?
}

struct ItemCreateRequest: Encodable, Equatable {
    let mainInventoryNumber: String
    let title: String
    let secondaryInventoryNumbers: [String]
    let authors: [ItemAuthorInput]
    let initialLocationId: Int64
    let moveInDate: BusinessDate
}

struct ItemUpdateRequest: Encodable, Equatable {
    let mainInventoryNumber: String
    let title: String
    let secondaryInventoryNumbers: [String]
    let authors: [ItemAuthorInput]
}

struct ItemPlanningOrganizationInput: Encodable, Equatable {
    let id: Int64?
    let name: String?
}

struct ItemPlanningUpdateRequest: Encodable, Equatable {
    let promisedOrganization: ItemPlanningOrganizationInput?
    let expectedLeaveDate: BusinessDate?
}

struct ItemMainNumberConflictResponse: Decodable, Equatable {
    let available: Bool
    let mainInventoryNumber: String
    let conflictingItem: ConflictingItem?
}

struct ConflictingItem: Decodable, Equatable {
    let id: Int64
    let title: String
    let currentPresenceType: ItemPresenceType
    let currentLocationName: String?
}
