import Foundation

struct MovementOrganizationInput: Codable, Equatable {
    let id: Int64?
    let name: String?
}

struct MovementExpectedSourcePlacementInput: Codable, Equatable {
    let presenceType: ItemPresenceType
    let locationId: Int64?
    let organizationId: Int64?
}

struct ItemMovementCreateRequest: Codable, Equatable {
    let presenceType: ItemPresenceType
    let locationId: Int64?
    let organization: MovementOrganizationInput?
    let moveInDate: BusinessDate
    let expectedReturnDate: BusinessDate?
    let expectedSourcePlacement: MovementExpectedSourcePlacementInput?
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

struct MovedByDeviceSummary: Codable, Equatable, Hashable {
    let id: UUID
    let friendlyName: String
    let deviceType: DeviceType
}

enum OfflineMovementSyncState: String, Codable, Equatable {
    case queued
    case rejected
}

struct ItemHistoryEntry: Identifiable, Equatable {
    let id: Int64
    let presenceType: ItemPresenceType
    let location: ItemLocationSummary?
    let organization: ItemOrganizationSummary?
    let moveInDate: BusinessDate
    let expectedReturnDate: BusinessDate?
    let moveOutDate: BusinessDate?
    let movedByDevice: MovedByDeviceSummary?
    let createdAt: Date?
    let localSyncState: OfflineMovementSyncState?
    let localSyncMessage: String?

    var isOpen: Bool { moveOutDate == nil }

    var targetName: String {
        switch presenceType {
        case .internal: return location?.displayName ?? "—"
        case .external: return organization?.name ?? "—"
        }
    }

    var performerName: String {
        movedByDevice?.friendlyName ?? "Host admin created"
    }

    func closing(at moveOutDate: BusinessDate) -> ItemHistoryEntry {
        ItemHistoryEntry(
            id: id,
            presenceType: presenceType,
            location: location,
            organization: organization,
            moveInDate: moveInDate,
            expectedReturnDate: expectedReturnDate,
            moveOutDate: moveOutDate,
            movedByDevice: movedByDevice,
            createdAt: createdAt,
            localSyncState: localSyncState,
            localSyncMessage: localSyncMessage
        )
    }
}

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
        case createdAt
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
        self.movedByDevice = try c.decodeIfPresent(MovedByDeviceSummary.self, forKey: .movedByDevice)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.localSyncState = nil
        self.localSyncMessage = nil
    }
}
