import SwiftUI

struct MovementEntryView: View {
    let store: MovementFeatureModel
    let onCompleted: (ItemResponse) -> Void
    let onCancel: () -> Void

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 16) {
                modePickerSection(store: store)
                targetSection(store: store)
                dateSection(store: store)

                if let validation = store.validationMessage {
                    inlineMessage(text: validation)
                }
                if let error = store.errorMessage {
                    inlineMessage(text: error)
                }

                Button {
                    Task { await store.submit() }
                } label: {
                    if store.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save movement")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fillWidth: true))
                .disabled(store.isSaving)
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Move item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
        }
        .task {
            if store.availableLocations.isEmpty {
                await store.loadDependencies()
            }
        }
        .onChange(of: store.saveSucceeded) { _, newValue in
            if newValue, let saved = store.savedItem {
                onCompleted(saved)
            }
        }
    }

    private func modePickerSection(store: MovementFeatureModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Choose movement type")

            ForEach([MovementEntryMode.internalMove, .externalRental, .returnToInternal], id: \.displayTitle) { mode in
                Button {
                    store.setMode(mode)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: store.mode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(store.mode == mode ? AppTheme.primary : AppTheme.subtleInk)
                        Text(mode.displayTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(store.mode == mode ? AppTheme.primarySoft : AppTheme.paper)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .museumPanel()
    }

    @ViewBuilder
    private func targetSection(store: MovementFeatureModel) -> some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            if store.mode.requiresLocation {
                sectionHeader("Internal location")
                FormFieldContainer(title: "Destination") {
                    Picker("Destination", selection: Binding(
                        get: { store.selectedLocationID ?? -1 },
                        set: { store.selectedLocationID = $0 == -1 ? nil : $0 }
                    )) {
                        Text("Select location").tag(Int64(-1))
                        ForEach(store.availableLocations) { location in
                            Text(location.name).tag(location.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(AppTheme.ink)
                }
            } else {
                sectionHeader("External organization")
                if let selected = store.selectedOrganization {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(AppTheme.primary)
                        Text(selected.name)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("Change") {
                            store.selectedOrganization = nil
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.primarySoft))
                } else {
                    FormFieldContainer(title: "Search organization") {
                        TextField("Start typing…", text: $store.organizationQuery)
                            .autocorrectionDisabled()
                            .onChange(of: store.organizationQuery) { _, value in
                                store.searchOrganizations(query: value)
                            }
                    }

                    if !store.organizationSuggestions.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(store.organizationSuggestions) { suggestion in
                                Button {
                                    store.selectOrganization(suggestion)
                                } label: {
                                    HStack {
                                        Image(systemName: "building.2")
                                        Text(suggestion.name)
                                        Spacer()
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundStyle(AppTheme.primary)
                                    }
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.canvas))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !store.organizationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !store.organizationSuggestions.contains(where: { $0.name.lowercased() == store.organizationQuery.lowercased() }) {
                        Button {
                            Task { await store.createOrganization(name: store.organizationQuery) }
                        } label: {
                            Label("Create \"\(store.organizationQuery)\"", systemImage: "plus.circle")
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
        .museumPanel()
    }

    private func dateSection(store: MovementFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Dates")
            FormFieldContainer(title: "Move-in date") {
                BusinessDatePickerField(date: Binding(
                    get: { store.moveInDate },
                    set: { store.moveInDate = $0 }
                ))
            }
            if store.mode == .externalRental {
                FormFieldContainer(title: "Expected return date (optional)") {
                    BusinessDatePickerField(date: Binding(
                        get: { store.expectedReturnDate },
                        set: { store.expectedReturnDate = $0 }
                    ), allowClear: true)
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
