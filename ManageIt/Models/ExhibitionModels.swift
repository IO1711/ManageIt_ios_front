import Foundation

enum ExhibitionPhase: String, Codable, Equatable, CaseIterable, Hashable {
    case planned = "PLANNED"
    case active = "ACTIVE"
    case ended = "ENDED"

    var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .active: return "Active"
        case .ended: return "Ended"
        }
    }
}

struct ExhibitionItemSummary: Codable, Equatable, Identifiable {
    let id: Int64
    let mainInventoryNumber: String
    let title: String
    let archived: Bool
    let currentPlacement: ItemPlacement?
}

struct ExhibitionResponse: Codable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let locationId: Int64
    let locationPath: String
    let startDate: BusinessDate
    let endDate: BusinessDate
    let phase: ExhibitionPhase
    let itemCount: Int
    /// Populated only by `GET /api/exhibitions/{id}`.
    let items: [ExhibitionItemSummary]?
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

/// Tolerant decoder for the list endpoint — accepts either a bare array or
/// `{ "exhibitions": [...] }` so the iPhone stays compatible with whichever
/// shape the backend ships first.
struct ExhibitionListResponse: Decodable {
    let exhibitions: [ExhibitionResponse]

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try? keyed.decode([ExhibitionResponse].self, forKey: .exhibitions) {
            self.exhibitions = nested
            return
        }
        let single = try decoder.singleValueContainer()
        self.exhibitions = (try? single.decode([ExhibitionResponse].self)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case exhibitions }
}

// MARK: - Move actor

struct MovedByDevice: Codable, Equatable, Hashable {
    let id: UUID
    let friendlyName: String
    let deviceType: DeviceType

    var deviceIconName: String {
        switch deviceType {
        case .iosApp: return "iphone.gen3"
        case .webBrowser: return "desktopcomputer"
        }
    }
}
