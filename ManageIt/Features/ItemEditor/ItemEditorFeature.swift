import SwiftUI

struct ItemEditorView: View {
    let store: ItemEditorFeatureModel
    let onCompleted: (ItemResponse) -> Void
    let onCancel: () -> Void

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 16) {
                mainFieldsSection(store: store)
                authorsSection(store: store)
                if !store.isEditMode {
                    locationAndDateSection(store: store)
                }
                if let validation = store.validationMessage {
                    inlineMessage(text: validation, tone: .rejected)
                }
                if let error = store.errorMessage {
                    inlineMessage(text: error, tone: .rejected)
                }
                actionSection
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
            await store.loadCreateDependencies()
        }
        .onChange(of: store.saveSucceeded) { _, newValue in
            if newValue, let saved = store.savedItem {
                onCompleted(saved)
            }
        }
    }

    private func mainFieldsSection(store: ItemEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Item details")

            FormFieldContainer(title: "Main inventory number") {
                TextField("INV-2026-001", text: $store.mainInventoryNumber)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: store.mainInventoryNumber) { _, _ in
                        Task { await store.checkMainNumberConflict() }
                    }
            }
            if let conflict = store.mainNumberConflict, conflict.available == false,
               let conflicting = conflict.conflictingItem {
                inlineMessage(
                    text: "Already used by “\(conflicting.title)” at \(conflicting.currentLocationName ?? "—").",
                    tone: .rejected
                )
            }

            FormFieldContainer(title: "Title") {
                TextField("Item title", text: $store.title)
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(title: "Secondary inventory numbers")
                if !store.secondaryInventoryNumbers.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(store.secondaryInventoryNumbers.enumerated()), id: \.offset) { idx, num in
                            HStack(spacing: 6) {
                                Text(num)
                                    .font(.system(size: 12, weight: .medium))
                                Button {
                                    store.removeSecondaryNumber(at: idx)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.primarySoft))
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add a secondary number", text: $store.secondaryDraft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(AppTheme.paper)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    Button("Add", action: store.addSecondaryNumber)
                        .buttonStyle(SoftButtonStyle())
                        .disabled(store.secondaryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .museumPanel()
    }

    private func authorsSection(store: ItemEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Authors")

            if !store.selectedAuthors.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(store.selectedAuthors) { author in
                        AuthorChip(author: author) {
                            store.removeAuthor(id: author.id)
                        }
                    }
                }
            }

            FormFieldContainer(title: "Search or create author") {
                TextField("Start typing…", text: $store.authorQuery)
                    .autocorrectionDisabled()
                    .onChange(of: store.authorQuery) { _, newValue in
                        store.searchAuthors(query: newValue)
                    }
            }

            if !store.authorSuggestions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.authorSuggestions) { suggestion in
                        Button {
                            store.addAuthor(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                Text(suggestion.name)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10).fill(AppTheme.canvas)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !store.authorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !store.authorSuggestions.contains(where: { $0.name.lowercased() == store.authorQuery.lowercased() }) {
                Button {
                    Task { await store.createAuthor(name: store.authorQuery) }
                } label: {
                    Label("Create \"\(store.authorQuery)\"", systemImage: "plus.circle")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .museumPanel()
    }

    private func locationAndDateSection(store: ItemEditorFeatureModel) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Initial placement")

            FormFieldContainer(title: "Internal location") {
                Picker("Initial location", selection: Binding(
                    get: { store.initialLocationID ?? -1 },
                    set: { store.initialLocationID = $0 == -1 ? nil : $0 }
                )) {
                    Text("Select location").tag(Int64(-1))
                    ForEach(store.availableLocations) { location in
                        Text(location.displayLabel).tag(location.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(AppTheme.ink)
            }

            FormFieldContainer(title: "Move-in date") {
                BusinessDatePickerField(date: Binding(
                    get: { store.moveInDate },
                    set: { store.moveInDate = $0 }
                ))
            }
        }
        .museumPanel()
    }

    private var actionSection: some View {
        Button {
            Task { await store.submit() }
        } label: {
            if store.isSaving {
                ProgressView().tint(.white)
            } else {
                Text(store.isEditMode ? "Save changes" : "Create item")
            }
        }
        .buttonStyle(PrimaryButtonStyle(fillWidth: true))
        .disabled(store.isSaving)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppTheme.ink)
    }

    private enum InlineTone { case rejected, neutral }

    private func inlineMessage(text: String, tone: InlineTone) -> some View {
        let foreground = tone == .rejected ? AppTheme.rejectedText : AppTheme.mutedInk
        let background = tone == .rejected ? AppTheme.rejectedBg : AppTheme.disabledBg
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone == .rejected ? "exclamationmark.circle.fill" : "info.circle.fill")
            Text(text)
                .font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(foreground)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(background)
        )
    }
}

struct AuthorChip: View {
    let author: AuthorResponse
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 10))
            Text(author.name)
                .font(.system(size: 13, weight: .medium))
            Button(action: onRemove) {
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

struct BusinessDatePickerField: View {
    @Binding var date: BusinessDate?
    var allowClear: Bool = false

    @State private var pickerDate: Date = Date()

    var body: some View {
        HStack {
            DatePicker(
                "",
                selection: $pickerDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(AppTheme.primary)
            .onChange(of: pickerDate) { _, newValue in
                date = (try? BusinessDate(dateComponents: Calendar.current.dateComponents([.year, .month, .day], from: newValue)))
            }
            .onAppear {
                if let resolved = date?.date() {
                    pickerDate = resolved
                }
            }

            if allowClear, date != nil {
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.subtleInk)
                }
            }
        }
    }
}
