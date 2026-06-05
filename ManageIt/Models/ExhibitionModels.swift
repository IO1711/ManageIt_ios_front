import Foundation

enum ExhibitionPhase: String, Codable, Equatable {
    case planned = "PLANNED"
    case active = "ACTIVE"
    case ended = "ENDED"

    var displayName: String {
        switch self {
        case .planned:
            return "Planned"
        case .active:
            return "Active"
        case .ended:
            return "Ended"
        }
    }
}

struct ExhibitionSummaryResponse: Decodable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let locationId: Int64
    let locationPath: String
    let startDate: BusinessDate
    let endDate: BusinessDate
    let phase: ExhibitionPhase
    let itemCount: Int
}

struct ExhibitionDetailResponse: Decodable, Equatable, Identifiable {
    struct LocationSummary: Codable, Equatable, Hashable {
        let id: Int64
        let name: String
        let fullPath: String

        var displayName: String {
            fullPath.isEmpty ? name : fullPath
        }
    }

    struct ItemSummary: Codable, Equatable, Identifiable, Hashable {
        let id: Int64
        let mainInventoryNumber: String
        let title: String
    }

    let id: Int64
    let name: String
    let location: LocationSummary
    let startDate: BusinessDate
    let endDate: BusinessDate
    let phase: ExhibitionPhase
    let items: [ItemSummary]
}

struct ExhibitionCreateRequest: Encodable, Equatable {
    let name: String
    let locationId: Int64
    let startDate: BusinessDate
    let endDate: BusinessDate
    let itemIds: [Int64]
}

struct ExhibitionUpdateRequest: Encodable, Equatable {
    let name: String
    let locationId: Int64
    let startDate: BusinessDate
    let endDate: BusinessDate
    let itemIds: [Int64]
}
