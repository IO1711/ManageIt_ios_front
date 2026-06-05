import SwiftUI

struct LocationManagementView: View {
    let store: LocationManagementFeatureModel

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

                rootComposerSection(store: store)
                locationTreeSection(store: store)

                if let successMessage = store.successMessage {
                    inlineMessage(text: successMessage, tone: .success)
                }

                if let errorMessage = store.errorMessage {
                    inlineMessage(text: errorMessage, tone: .error)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Museum location hierarchy")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Admins can add root locations or grow the nested tree in place. Only leaf locations are assignable to items and exhibitions.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rootComposerSection(store: LocationManagementFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Add root location")
                Spacer()
                Button {
                    store.toggleRootComposer()
                } label: {
                    Label(
                        store.rootComposerOpen ? "Close" : "New root",
                        systemImage: store.rootComposerOpen ? "xmark.circle" : "plus.circle"
                    )
                }
                .buttonStyle(SoftButtonStyle())
            }

            if store.rootComposerOpen {
                LocationComposerCard(
                    title: "Create root location",
                    placeholder: "Main Hall, Archive Room, East Wing...",
                    value: $store.rootDraftLocationName,
                    saveTitle: "Add root",
                    isSaving: store.isSaving,
                    onSave: { Task { await store.createRootLocation() } },
                    onCancel: { store.toggleRootComposer() }
                )
            }
        }
        .museumPanel()
    }

    private func locationTreeSection(store: LocationManagementFeatureModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Existing hierarchy")
                Spacer()
                Button("Refresh") {
                    Task { await store.load() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            }

            if store.isLoading && store.locationTree.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if store.locationTree.isEmpty {
                Text("No locations yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.locationTree) { node in
                        LocationTreeNodeView(store: store, node: node, depth: 0)
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

    private enum InlineTone {
        case success
        case error
    }

    private func inlineMessage(text: String, tone: InlineTone) -> some View {
        let foreground = tone == .success ? AppTheme.approvedText : AppTheme.rejectedText
        let background = tone == .success ? AppTheme.approvedBg : AppTheme.rejectedBg
        let icon = tone == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill"

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(foreground)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(background))
    }
}

private struct LocationTreeNodeView: View {
    let store: LocationManagementFeatureModel
    let node: LocationTreeNode
    let depth: Int

    var body: some View {
        @Bindable var store = store
        let location = node.location

        VStack(alignment: .leading, spacing: 10) {
            if store.editingLocationID == location.id {
                HStack(spacing: 10) {
                    TextField("Location name", text: $store.editingName)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.paper))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )

                    Button("Save") {
                        Task { await store.saveEditing() }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(store.isSaving)

                    Button("Cancel") {
                        store.cancelEditing()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.mutedInk)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: location.assignable ? "circle.grid.2x2.fill" : "square.split.bottomrightquarter")
                        .foregroundStyle(location.assignable ? AppTheme.primary : AppTheme.mutedInk)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(location.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)

                            if location.archived {
                                StatusTag(text: "Archived", kind: .expired)
                            } else if location.assignable {
                                StatusTag(text: "Leaf", kind: .approved)
                            } else {
                                StatusTag(text: "Branch", kind: .neutral)
                            }
                        }

                        Text(location.displayLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    if !location.archived {
                        Button {
                            store.toggleChildComposer(for: location)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 19))
                                .foregroundStyle(AppTheme.primary)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Rename") {
                                store.beginEditing(location)
                            }
                            Button("Archive", role: .destructive) {
                                Task { await store.archiveLocation(location) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 19))
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.canvas)
                )
            }

            if store.openChildParentID == location.id {
                LocationComposerCard(
                    title: "Add a child under \(location.name)",
                    placeholder: "Shelf, Grid, Drawer...",
                    value: Binding(
                        get: { store.childDrafts[location.id] ?? "" },
                        set: { store.updateChildDraft(parentID: location.id, value: $0) }
                    ),
                    saveTitle: "Add child",
                    isSaving: store.isSaving,
                    onSave: { Task { await store.createChildLocation(parent: location) } },
                    onCancel: { store.toggleChildComposer(for: location) }
                )
            }

            if !node.children.isEmpty {
                VStack(spacing: 10) {
                    ForEach(node.children) { child in
                        LocationTreeNodeView(store: store, node: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.leading, CGFloat(depth) * 8)
    }
}

private struct LocationComposerCard: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    let saveTitle: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            TextField(placeholder, text: $value)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button(action: onSave) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(saveTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.primarySoft)
        )
    }
}
