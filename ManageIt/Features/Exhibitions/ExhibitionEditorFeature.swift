import SwiftUI

struct ExhibitionEditorView: View {
    let store: ExhibitionEditorFeatureModel
    let onCompleted: (ExhibitionResponse) -> Void
    let onCancel: () -> Void

    @State private var showLocationPicker = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 16) {
                nameSection(store: store)
                locationSection(store: store)
                datesSection(store: store)
                itemsSection(store: store)

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
                        Text(store.isEditMode ? "Save changes" : "Create exhibition")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fillWidth: true))
                .disabled(store.isSaving)
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
            if store.availableLocations.isEmpty {
                await store.loadDependencies()
            }
        }
        .onChange(of: store.saveSucceeded) { _, newValue in
            if newValue, let saved = store.savedExhibition {
                onCompleted(saved)
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationTreePicker(
                allLocations: store.availableLocations,
                onSelect: { selected in
                    store.selectLocation(selected)
                    showLocationPicker = false
                },
                onCancel: { showLocationPicker = false }
            )
        }
    }

    private func nameSection(store: ExhibitionEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Exhibition name")
            FormFieldContainer(title: "Name") {
                TextField("e.g. Autumn Masks 2026", text: $store.name)
                    .autocorrectionDisabled()
            }
        }
        .museumPanel()
    }

    private func locationSection(store: ExhibitionEditorFeatureModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Internal location")
            LocationTreeField(
                title: "Leaf location",
                selected: store.selectedLocation,
                onTap: { showLocationPicker = true }
            )
            Text("Active exhibitions require every linked item to currently sit at this exact leaf location.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .museumPanel()
    }

    private func datesSection(store: ExhibitionEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Dates")
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

    private func itemsSection(store: ExhibitionEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Linked items")

            if !store.selectedItems.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.selectedItems) { item in
                        let warning = store.itemPlacementWarning(item)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.fill")
                                    .foregroundStyle(warning == nil ? AppTheme.primary : AppTheme.rejectedText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(item.mainInventoryNumber)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.mutedInk)
                                }
                                Spacer()
                                Button {
                                    store.removeItem(id: item.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(AppTheme.rejectedText)
                                }
                                .buttonStyle(.plain)
                            }
                            if let warning {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                    Text(warning)
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(AppTheme.rejectedText)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(warning == nil ? AppTheme.canvas : AppTheme.rejectedBg)
                        )
                    }
                }
            }

            FormFieldContainer(title: "Search items to add") {
                TextField("Title, inventory number…", text: $store.itemQuery)
                    .autocorrectionDisabled()
                    .onChange(of: store.itemQuery) { _, value in
                        store.searchItems(query: value)
                    }
            }

            if !store.itemSuggestions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.itemSuggestions) { item in
                        Button {
                            store.addItem(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(item.mainInventoryNumber)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.mutedInk)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
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
