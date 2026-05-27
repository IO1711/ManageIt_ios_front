import SwiftUI

struct PlanningEditorView: View {
    let store: PlanningEditorFeatureModel
    let onCompleted: (ItemResponse) -> Void
    let onCancel: () -> Void

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 16) {
                organizationSection(store: store)
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
                        Text("Save planning")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fillWidth: true))
                .disabled(store.isSaving)
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Planning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
        }
        .onChange(of: store.saveSucceeded) { _, newValue in
            if newValue, let saved = store.savedItem {
                onCompleted(saved)
            }
        }
    }

    private func organizationSection(store: PlanningEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Promised organization")

            if let selected = store.selectedOrganization {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(AppTheme.primary)
                    Text(selected.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Button("Change") {
                        store.clearOrganization()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(AppTheme.primarySoft)
                )
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
        .museumPanel()
    }

    private func dateSection(store: PlanningEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Expected leave date")

            FormFieldContainer(title: "Date") {
                BusinessDatePickerField(date: Binding(
                    get: { store.expectedLeaveDate },
                    set: { store.expectedLeaveDate = $0 }
                ), allowClear: true)
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
