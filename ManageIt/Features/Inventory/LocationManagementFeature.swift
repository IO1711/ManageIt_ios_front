import SwiftUI

struct LocationManagementView: View {
    let store: LocationManagementFeatureModel

    @State private var showParentPicker = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 16) {
                header
                Toggle(isOn: Binding(
                    get: { store.includeArchived },
                    set: { store.toggleIncludeArchived($0) }
                )) {
                    Text("Show archived locations")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.mutedInk)
                }
                .tint(AppTheme.primary)
                .padding(.horizontal, 4)

                createLocationSection(store: store)
                locationList(store: store)

                if let error = store.errorMessage {
                    inlineMessage(text: error)
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.locations.isEmpty {
                await store.load()
            }
        }
        .refreshable {
            await store.load()
        }
        .sheet(isPresented: $showParentPicker) {
            ParentLocationPicker(
                allLocations: store.locations,
                selected: store.draftParent,
                onSelect: { parent in
                    store.selectDraftParent(parent)
                    showParentPicker = false
                },
                onClear: {
                    store.selectDraftParent(nil)
                    showParentPicker = false
                },
                onCancel: { showParentPicker = false }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Museum locations")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Admin-only. Locations form a hierarchy — only leaves can hold items. Locations cannot be hard-deleted because they may have history.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func createLocationSection(store: LocationManagementFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Add new location")

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(title: "Parent")
                Button {
                    showParentPicker = true
                } label: {
                    HStack {
                        if let parent = store.draftParent {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(parent.displayPath)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("Tap to change")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("(no parent — top-level)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("Tap to pick a parent location")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.subtleInk)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(AppTheme.paper)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField("e.g. Storage 2, Shelf 1", text: $store.draftLocationName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.paper))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                Button {
                    Task { await store.createLocation() }
                } label: {
                    if store.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Label("Add", systemImage: "plus")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.draftLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
            }
        }
        .museumPanel()
    }

    private func locationList(store: LocationManagementFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Existing locations")

            if store.isLoading && store.locations.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if store.locations.isEmpty {
                Text("No locations yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.tree) { node in
                        LocationTreeRow(node: node, depth: 0, store: store)
                    }
                }
            }
        }
        .museumPanel()
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppTheme.ink)
    }

    private func inlineMessage(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(AppTheme.rejectedText)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(AppTheme.rejectedBg)
        )
    }
}

private struct LocationTreeRow: View {
    let node: LocationTreeNode
    let depth: Int
    let store: LocationManagementFeatureModel

    @Bindable private var bindableStore: LocationManagementFeatureModel
    @State private var isExpanded: Bool = true

    init(node: LocationTreeNode, depth: Int, store: LocationManagementFeatureModel) {
        self.node = node
        self.depth = depth
        self.store = store
        _bindableStore = Bindable(store)
    }

    var body: some View {
        VStack(spacing: 4) {
            row
            if isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    LocationTreeRow(node: child, depth: depth + 1, store: store)
                }
            }
        }
    }

    @ViewBuilder
    private var row: some View {
        if store.editingLocationID == node.location.id {
            HStack(spacing: 10) {
                indentSpacer
                TextField("Location name", text: $bindableStore.editingName)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.paper))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                Button("Save") { Task { await store.saveEditing() } }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(store.isSaving)
                Button("Cancel") { store.cancelEditing() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        } else {
            HStack(spacing: 8) {
                indentSpacer

                Button {
                    if !node.children.isEmpty { isExpanded.toggle() }
                } label: {
                    Image(systemName: node.children.isEmpty
                        ? "mappin.circle.fill"
                        : (isExpanded ? "chevron.down" : "chevron.right"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(node.children.isEmpty ? AppTheme.primary : AppTheme.mutedInk)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(node.location.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        if node.location.archived {
                            StatusTag(text: "Archived", kind: .expired)
                        }
                    }
                    if node.children.isEmpty {
                        Text("Leaf")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.approvedText)
                    } else {
                        Text("\(node.children.count) child(ren)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
                Spacer()

                if !node.location.archived {
                    Menu {
                        Button("Rename") { store.beginEditing(node.location) }
                        Button("Add child here") {
                            store.selectDraftParent(node.location)
                        }
                        Button("Archive", role: .destructive) {
                            Task { await store.archiveLocation(node.location) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.canvas))
        }
    }

    private var indentSpacer: some View {
        Color.clear.frame(width: CGFloat(depth) * 14, height: 1)
    }
}

// MARK: - Parent picker

private struct ParentLocationPicker: View {
    let allLocations: [LocationResponse]
    let selected: LocationResponse?
    let onSelect: (LocationResponse) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        onClear()
                    } label: {
                        HStack {
                            Image(systemName: "tray")
                                .foregroundStyle(AppTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Top-level (no parent)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("Creates a root location")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                            Spacer()
                            if selected == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.paper))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(allLocations.filter { !$0.archived }, id: \.id) { loc in
                        Button {
                            onSelect(loc)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(AppTheme.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.displayPath)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    if loc.name != loc.displayPath {
                                        Text(loc.name)
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }
                                }
                                Spacer()
                                if selected?.id == loc.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.primary)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.paper))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.canvas.ignoresSafeArea())
            .navigationTitle("Choose parent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
