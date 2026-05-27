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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Museum locations")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Admin-only. Locations cannot be hard-deleted because they may have movement history.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func createLocationSection(store: LocationManagementFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Add new location")
            HStack(spacing: 10) {
                TextField("e.g. Storage 2, Hall B", text: $store.draftLocationName)
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
                VStack(spacing: 10) {
                    ForEach(store.locations) { location in
                        locationRow(store: store, location: location)
                    }
                }
            }
        }
        .museumPanel()
    }

    @ViewBuilder
    private func locationRow(store: LocationManagementFeatureModel, location: LocationResponse) -> some View {
        @Bindable var store = store

        if store.editingLocationID == location.id {
            HStack(spacing: 10) {
                TextField("Location name", text: $store.editingName)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.paper))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(AppTheme.cardBorder, lineWidth: 1)
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(location.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        if location.archived {
                            StatusTag(text: "Archived", kind: .expired)
                        }
                    }
                }
                Spacer()
                if !location.archived {
                    Menu {
                        Button("Rename") {
                            store.beginEditing(location)
                        }
                        Button("Archive", role: .destructive) {
                            Task { await store.archiveLocation(location) }
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
