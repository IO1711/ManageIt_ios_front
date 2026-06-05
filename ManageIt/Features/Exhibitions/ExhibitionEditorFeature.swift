import SwiftUI

struct ExhibitionEditorView: View {
    let store: ExhibitionEditorFeatureModel
    let onCompleted: (ExhibitionDetailResponse) -> Void
    let onCancel: () -> Void

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 16) {
                basicsSection(store: store)
                locationSection(store: store)
                itemsSection(store: store)

                if let validation = store.validationMessage {
                    inlineMessage(text: validation, tone: .rejected)
                }
                if let error = store.errorMessage {
                    inlineMessage(text: error, tone: .rejected)
                }

                Button {
                    Task { await store.submit() }
                } label: {
                    if store.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(store.mode.title)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fillWidth: true))
                .disabled(store.isSaving || store.isLoadingDependencies)
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle(store.mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
        }
        .task {
            await store.loadDependenciesIfNeeded()
        }
        .onChange(of: store.saveSucceeded) { _, newValue in
            if newValue, let saved = store.savedExhibition {
                onCompleted(saved)
            }
        }
    }

    private func basicsSection(store: ExhibitionEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Basics")

            FormFieldContainer(title: "Exhibition name") {
                TextField("Autumn Masks 2026", text: $store.name)
                    .autocorrectionDisabled()
            }

            FormFieldContainer(title: "Start date") {
                BusinessDatePickerField(date: Binding(
                    get: { store.startDate },
                    set: { store.startDate = $0 }
                ))
            }

            FormFieldContainer(title: "End date") {
                BusinessDatePickerField(date: Binding(
                    get: { store.endDate },
                    set: { store.endDate = $0 }
                ))
            }
        }
        .museumPanel()
    }

    private func locationSection(store: ExhibitionEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Exhibition location")

            if store.isLoadingDependencies && store.locationOptions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                FormFieldContainer(title: "Leaf location") {
                    Picker("Leaf location", selection: Binding(
                        get: { store.selectedLocationID ?? -1 },
                        set: { store.selectedLocationID = $0 == -1 ? nil : $0 }
                    )) {
                        Text("Select location").tag(Int64(-1))
                        ForEach(store.locationOptions) { location in
                            Text(location.displayLabel).tag(location.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(AppTheme.ink)
                }
            }
        }
        .museumPanel()
    }

    private func itemsSection(store: ExhibitionEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Linked items")

            if !store.selectedItems.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(store.selectedItems) { item in
                        HStack(spacing: 6) {
                            Text(item.mainInventoryNumber)
                                .font(.system(size: 12, weight: .bold))
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Button {
                                store.toggleItemSelection(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppTheme.primarySoft))
                    }
                }
            }

            FormFieldContainer(title: "Search items") {
                TextField("Title, inventory number, location…", text: $store.itemSearchText)
                    .autocorrectionDisabled()
            }

            if store.isLoadingDependencies && store.candidateItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.filteredCandidateItems) { item in
                        Button {
                            store.toggleItemSelection(item)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: store.selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(store.selectedItemIDs.contains(item.id) ? AppTheme.primary : AppTheme.subtleInk)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(item.mainInventoryNumber)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.mutedInk)
                                    Text(item.currentPlacement.displayTargetName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.subtleInk)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(store.selectedItemIDs.contains(item.id) ? AppTheme.primarySoft : AppTheme.canvas)
                            )
                        }
                        .buttonStyle(.plain)
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
        case rejected
    }

    private func inlineMessage(text: String, tone: InlineTone) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text)
                .font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(AppTheme.rejectedText)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(AppTheme.rejectedBg)
        )
    }
}
