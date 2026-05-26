import SwiftUI

struct InventoryFeatureView: View {
    let store: InventoryFeatureModel
    let onSelectItem: (Int64) -> Void
    let onCreateItem: () -> Void

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            searchBar(text: $store.query.searchText)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if store.role.isAdmin {
                Toggle(isOn: Binding(
                    get: { store.query.includeArchived },
                    set: { store.setIncludeArchived($0) }
                )) {
                    Text("Show archived items")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.mutedInk)
                }
                .tint(AppTheme.primary)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }

            content
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            if !store.hasLoadedOnce {
                await store.loadFirstPage()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Inventory")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Search, edit, and move museum items.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            }
            Spacer()
            Button(action: onCreateItem) {
                Label("New item", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func searchBar(text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.mutedInk)
            TextField("Search inventory number, title, author, location…", text: text)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onChange(of: text.wrappedValue) { _, newValue in
                    store.updateSearchText(newValue)
                }
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    store.updateSearchText("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.subtleInk)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.errorMessage, store.items.isEmpty {
            errorState(message: message)
        } else if store.isLoading && store.items.isEmpty {
            ProgressView()
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
        } else if store.items.isEmpty && store.hasLoadedOnce {
            emptyState
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.items) { item in
                    Button {
                        onSelectItem(item.id)
                    } label: {
                        InventoryItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        Task { await store.loadNextPageIfNeeded(currentItemID: item.id) }
                    }
                }

                if store.isLoadingNextPage {
                    ProgressView()
                        .padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .refreshable {
            await store.reload()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.mutedInk)
            Text("No items match the current filters")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Adjust the search or create a new item to begin building the inventory.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .padding(.top, 60)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.rejectedText)
            Text("Could not load inventory")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await store.reload() }
            }
            .buttonStyle(SoftButtonStyle())
        }
        .padding(.horizontal, 30)
        .padding(.top, 50)
    }
}

struct InventoryItemRow: View {
    let item: ItemResponse

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.primarySoft)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: item.currentPlacement.presenceType == .external ? "paperplane.fill" : "building.columns.fill")
                        .foregroundStyle(AppTheme.primary)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    if item.archived {
                        StatusTag(text: "Archived", kind: .expired)
                    } else {
                        placementTag
                    }
                }

                Text(item.mainInventoryNumber)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.mutedInk)

                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                    Text(item.authorNames)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.subtleInk)

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                    Text(item.currentPlacement.displayTargetName)
                        .font(.system(size: 12))
                }
                .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private var placementTag: some View {
        switch item.currentPlacement.presenceType {
        case .internal:
            return StatusTag(text: "On-site", kind: .approved)
        case .external:
            return StatusTag(text: "On rental", kind: .planned)
        }
    }
}
