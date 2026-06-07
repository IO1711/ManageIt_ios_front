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
    let path: String?

    /// Display path with fallback to name for older payloads.
    var displayPath: String { path ?? name }
}

struct ItemOrganizationSummary: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
}

struct ItemPlacement: Codable, Equatable {
    let presenceType: ItemPresenceType
    let location: ItemLocationSummary?
    let organization: ItemOrganizationSummary?

    var displayTargetName: String {
        switch presenceType {
        case .internal:
            return location?.displayPath ?? "—"
        case .external:
            return organization?.name ?? "—"
        }
    }
}

struct ItemPlanning: Codable, Equatable {
    let promisedOrganization: ItemOrganizationSummary?
    let expectedLeaveDate: BusinessDate?
}

/// Slim summary of the exhibition an item is currently in, surfaced on item
/// detail per architecture section 12.3.
struct CurrentExhibitionSummary: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let startDate: BusinessDate
    let endDate: BusinessDate
}

struct ItemResponse: Codable, Equatable, Identifiable {
    let id: Int64
    let mainInventoryNumber: String
    let title: String
    let secondaryInventoryNumbers: [String]
    let authors: [ItemAuthorSummary]
    let currentPlacement: ItemPlacement
    let planning: ItemPlanning
    let archived: Bool
    /// Active exhibition the item is currently part of, or `nil` when not in
    /// any active exhibition. Optional so older backend responses still decode.
    let currentExhibition: CurrentExhibitionSummary?

    var authorNames: String {
        if authors.isEmpty { return "—" }
        return authors.map(\.name).joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case id, mainInventoryNumber, title, secondaryInventoryNumbers
        case authors, currentPlacement, planning, archived, currentExhibition
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int64.self, forKey: .id)
        self.mainInventoryNumber = try c.decode(String.self, forKey: .mainInventoryNumber)
        self.title = try c.decode(String.self, forKey: .title)
        self.secondaryInventoryNumbers = try c.decode([String].self, forKey: .secondaryInventoryNumbers)
        self.authors = try c.decode([ItemAuthorSummary].self, forKey: .authors)
        self.currentPlacement = try c.decode(ItemPlacement.self, forKey: .currentPlacement)
        self.planning = try c.decode(ItemPlanning.self, forKey: .planning)
        self.archived = try c.decode(Bool.self, forKey: .archived)
        self.currentExhibition = try c.decodeIfPresent(CurrentExhibitionSummary.self, forKey: .currentExhibition)
    }

    init(
        id: Int64,
        mainInventoryNumber: String,
        title: String,
        secondaryInventoryNumbers: [String],
        authors: [ItemAuthorSummary],
        currentPlacement: ItemPlacement,
        planning: ItemPlanning,
        archived: Bool,
        currentExhibition: CurrentExhibitionSummary? = nil
    ) {
        self.id = id
        self.mainInventoryNumber = mainInventoryNumber
        self.title = title
        self.secondaryInventoryNumbers = secondaryInventoryNumbers
        self.authors = authors
        self.currentPlacement = currentPlacement
        self.planning = planning
        self.archived = archived
        self.currentExhibition = currentExhibition
    }
}

struct ItemListResponse: Codable, Equatable {
    let items: [ItemResponse]
    let page: Int
    let size: Int
    let totalItems: Int64
    let totalPages: Int
}

struct ItemAuthorInput: Codable, Equatable {
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
    let currentLocationPath: String?

    /// Best available human-readable description of where the conflicting item lives.
    var displayPlacement: String {
        currentLocationPath ?? currentLocationName ?? "—"
    }
}
