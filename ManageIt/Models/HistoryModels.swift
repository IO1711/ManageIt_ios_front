import Foundation

struct MovementOrganizationInput: Codable, Equatable {
    let id: Int64?
    let name: String?
}

/// Snapshot of the item's expected current placement on the iPhone at queue
/// time. Sent back during offline replay so the server can reject the write
/// if its database state has drifted since the queued move was authored
/// (`STALE_OFFLINE_MOVEMENT`).
struct ExpectedSourcePlacement: Codable, Equatable {
    let presenceType: ItemPresenceType
    let locationId: Int64?
    let organizationId: Int64?

    init(presenceType: ItemPresenceType, locationId: Int64?, organizationId: Int64?) {
        self.presenceType = presenceType
        self.locationId = locationId
        self.organizationId = organizationId
    }

    init(placement: ItemPlacement) {
        self.presenceType = placement.presenceType
        self.locationId = placement.location?.id
        self.organizationId = placement.organization?.id
    }
}

struct ItemMovementCreateRequest: Codable, Equatable {
    let presenceType: ItemPresenceType
    let locationId: Int64?
    let organization: MovementOrganizationInput?
    let moveInDate: BusinessDate
    let expectedReturnDate: BusinessDate?
    let expectedSourcePlacement: ExpectedSourcePlacement?
}

enum MovementEntryMode: Equatable {
    case internalMove
    case externalRental
    case returnToInternal

    var displayTitle: String {
        switch self {
        case .internalMove: return "Move to internal location"
        case .externalRental: return "Send to external organization"
        case .returnToInternal: return "Return to internal location"
        }
    }

    var requiresLocation: Bool {
        self == .internalMove || self == .returnToInternal
    }

    var requiresOrganization: Bool {
        self == .externalRental
    }
}

// MARK: - Local history row view model
//
// The backend success contract for `GET /api/items/{id}/history` is not finalized
// in Part III of the iOS source-of-truth. The view layer renders this local shape
// once a concrete row decoder is available (`itemHistoryDecoder` in the API client).

struct ItemHistoryEntry: Identifiable, Equatable {
    let id: Int64
    let presenceType: ItemPresenceType
    let location: ItemLocationSummary?
    let organization: ItemOrganizationSummary?
    let moveInDate: BusinessDate
    let expectedReturnDate: BusinessDate?
    let moveOutDate: BusinessDate?
    let movedByDevice: MovedByDevice?

    var isOpen: Bool { moveOutDate == nil }

    var targetName: String {
        switch presenceType {
        case .internal: return location?.displayPath ?? "—"
        case .external: return organization?.name ?? "—"
        }
    }
}

/// Decoder shape for whatever the backend returns. Defensive: tolerates either
/// a bare array or `{ "entries": [...] }`. Once the source-of-truth fills in
/// the exact response, this can collapse to the canonical shape.
struct ItemHistoryListResponse: Decodable {
    let entries: [ItemHistoryEntry]

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try? keyed.decode([ItemHistoryEntry].self, forKey: .entries) {
            self.entries = nested
            return
        }
        let single = try decoder.singleValueContainer()
        self.entries = (try? single.decode([ItemHistoryEntry].self)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case entries }
}

extension ItemHistoryEntry: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case presenceType
        case location
        case organization
        case moveInDate
        case expectedReturnDate
        case moveOutDate
        case movedByDevice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int64.self, forKey: .id)
        self.presenceType = try c.decode(ItemPresenceType.self, forKey: .presenceType)
        self.location = try c.decodeIfPresent(ItemLocationSummary.self, forKey: .location)
        self.organization = try c.decodeIfPresent(ItemOrganizationSummary.self, forKey: .organization)
        self.moveInDate = try c.decode(BusinessDate.self, forKey: .moveInDate)
        self.expectedReturnDate = try c.decodeIfPresent(BusinessDate.self, forKey: .expectedReturnDate)
        self.moveOutDate = try c.decodeIfPresent(BusinessDate.self, forKey: .moveOutDate)
        self.movedByDevice = try c.decodeIfPresent(MovedByDevice.self, forKey: .movedByDevice)
    }
}
