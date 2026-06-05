import Foundation

struct LocationTreeNode: Identifiable, Hashable {
    let location: LocationResponse
    let children: [LocationTreeNode]

    var id: Int64 { location.id }
}

func sortLocationsByPath(_ locations: [LocationResponse]) -> [LocationResponse] {
    locations.sorted { lhs, rhs in
        lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
    }
}

func assignableLocations(from locations: [LocationResponse]) -> [LocationResponse] {
    sortLocationsByPath(locations.filter(\.assignable))
}

func buildLocationTree(from locations: [LocationResponse]) -> [LocationTreeNode] {
    let sorted = sortLocationsByPath(locations)
    let groupedChildren = Dictionary(grouping: sorted, by: \.parentLocationId)

    func buildNode(for location: LocationResponse) -> LocationTreeNode {
        let children = (groupedChildren[location.id] ?? []).map(buildNode(for:))
        return LocationTreeNode(location: location, children: children)
    }

    return (groupedChildren[nil] ?? []).map(buildNode(for:))
}
