import Foundation

struct LocationResponse: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let archived: Bool
    let parentLocationId: Int64?
    let path: String?
    let assignable: Bool?

    /// Display path with fallback to name for older payloads.
    var displayPath: String { path ?? name }

    /// Backend-confirmed assignability (only leaves are assignable). Defaults to
    /// `!archived` when the backend omitted the field.
    var isAssignable: Bool { assignable ?? !archived }
}

struct LocationCreateRequest: Encodable, Equatable {
    let name: String
    let parentLocationId: Int64?
}

struct LocationUpdateRequest: Encodable, Equatable {
    let name: String
}

struct AuthorResponse: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let archived: Bool
}

struct AuthorCreateRequest: Encodable, Equatable {
    let name: String
}

struct OrganizationResponse: Codable, Equatable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let archived: Bool
}

struct OrganizationCreateRequest: Encodable, Equatable {
    let name: String
}

// MARK: - Tree utilities

/// Light-weight in-memory view of the location tree. Used by the picker and the
/// admin management screen so they can drill into children and resolve leaves.
struct LocationTreeNode: Identifiable, Hashable {
    let location: LocationResponse
    let children: [LocationTreeNode]

    var id: Int64 { location.id }
    var isLeaf: Bool { children.isEmpty }
    /// True when the user can place an item here. Combines the backend
    /// `assignable` hint with the leaf check as a safety belt.
    var isSelectable: Bool { isLeaf && location.isAssignable && !location.archived }
}

enum LocationTreeBuilder {
    /// Builds the forest of root nodes from a flat list of `LocationResponse`s.
    /// Children are nested recursively and sorted alphabetically per level.
    static func build(from locations: [LocationResponse]) -> [LocationTreeNode] {
        let byParent: [Int64?: [LocationResponse]] = Dictionary(grouping: locations, by: { $0.parentLocationId })
        return buildChildren(parentId: nil, byParent: byParent)
    }

    private static func buildChildren(
        parentId: Int64?,
        byParent: [Int64?: [LocationResponse]]
    ) -> [LocationTreeNode] {
        let level = (byParent[parentId] ?? []).sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return level.map { location in
            LocationTreeNode(
                location: location,
                children: buildChildren(parentId: location.id, byParent: byParent)
            )
        }
    }
}
