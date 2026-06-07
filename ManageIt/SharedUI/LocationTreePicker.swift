import SwiftUI

/// Sheet-presented hierarchical location picker. Drills into children level by
/// level. Only leaf, non-archived, assignable locations can be selected — every
/// item placement and movement target must be a leaf per the architecture.
struct LocationTreePicker: View {
    let allLocations: [LocationResponse]
    let onSelect: (LocationResponse) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            LocationTreeLevelView(
                allLocations: allLocations,
                parent: nil,
                onSelect: { location in
                    onSelect(location)
                }
            )
            .navigationTitle("Choose location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
            .background(AppTheme.canvas.ignoresSafeArea())
        }
    }
}

private struct LocationTreeLevelView: View {
    let allLocations: [LocationResponse]
    let parent: LocationResponse?
    let onSelect: (LocationResponse) -> Void

    var body: some View {
        let children = childrenForCurrentLevel()

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let parent {
                    parentBreadcrumb(parent: parent)
                }

                if children.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(children) { child in
                            row(for: child)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle(parent?.name ?? "Locations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func childrenForCurrentLevel() -> [LocationResponse] {
        allLocations
            .filter { $0.parentLocationId == parent?.id }
            .filter { !$0.archived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func hasChildren(_ location: LocationResponse) -> Bool {
        allLocations.contains { $0.parentLocationId == location.id }
    }

    @ViewBuilder
    private func row(for location: LocationResponse) -> some View {
        let isLeaf = !hasChildren(location)
        let assignable = isLeaf && location.isAssignable

        if hasChildren(location) {
            NavigationLink {
                LocationTreeLevelView(
                    allLocations: allLocations,
                    parent: location,
                    onSelect: onSelect
                )
            } label: {
                LocationRowLabel(
                    location: location,
                    isLeaf: false,
                    isAssignable: false
                )
            }
            .buttonStyle(.plain)
        } else if assignable {
            Button {
                onSelect(location)
            } label: {
                LocationRowLabel(
                    location: location,
                    isLeaf: true,
                    isAssignable: true
                )
            }
            .buttonStyle(.plain)
        } else {
            LocationRowLabel(
                location: location,
                isLeaf: isLeaf,
                isAssignable: false
            )
        }
    }

    private func parentBreadcrumb(parent: LocationResponse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title: "Current branch")
            Text(parent.displayPath)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(AppTheme.primarySoft)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.mutedInk)
            Text("No sub-locations yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Ask an admin to create child locations here, or pick a leaf elsewhere in the tree.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}

private struct LocationRowLabel: View {
    let location: LocationResponse
    let isLeaf: Bool
    let isAssignable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isLeaf ? "mappin.circle.fill" : "folder.fill")
                .foregroundStyle(isAssignable ? AppTheme.primary : AppTheme.mutedInk)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                if isLeaf {
                    if isAssignable {
                        Text("Tap to select this location")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.approvedText)
                    } else if location.archived {
                        Text("Archived")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.expiredText)
                    } else {
                        Text("Not assignable")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                } else {
                    Text("Has sub-locations — tap to open")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            Spacer()
            if !isLeaf {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.subtleInk)
                    .font(.system(size: 13, weight: .semibold))
            } else if isAssignable {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(AppTheme.primary)
                    .font(.system(size: 18))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(AppTheme.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

/// Compact button that opens the picker. Reused by ItemEditor and Movement
/// forms so the form layout stays consistent.
struct LocationTreeField: View {
    let title: String
    let selected: LocationResponse?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title)
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if let selected {
                            Text(selected.displayPath)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                            if selected.name != selected.displayPath {
                                Text(selected.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        } else {
                            Text("Select leaf location")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.subtleInk)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.subtleInk)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(AppTheme.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
