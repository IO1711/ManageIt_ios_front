import SwiftUI

struct ItemDetailView: View {
    let store: ItemDetailFeatureModel
    let onEdit: () -> Void
    let onUpdatePlanning: () -> Void
    let onCreateMovement: () -> Void
    let onShowFullHistory: () -> Void

    @State private var showArchiveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isLoading && store.item == nil {
                    ProgressView()
                        .padding(.top, 80)
                } else if let item = store.item {
                    headerSection(item: item)
                    metadataSection(item: item)
                    statusSection(item: item)
                    historySection
                    actionSection(item: item)
                } else if let message = store.errorMessage {
                    errorCard(message: message)
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.item == nil {
                await store.load()
            }
        }
        .refreshable {
            await store.reload()
        }
        .alert("Archive this item?", isPresented: $showArchiveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Archive", role: .destructive) {
                Task { await store.archiveItem() }
            }
        } message: {
            Text("The item will be hidden from the default inventory views. Archived items keep their main inventory number reserved.")
        }
    }

    private func headerSection(item: ItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if item.archived {
                    StatusTag(text: "Archived", kind: .expired)
                } else {
                    placementTag(for: item)
                }
            }
            Text(item.mainInventoryNumber)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .museumPanel()
    }

    private func metadataSection(item: ItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Metadata")

            detailRow(label: "Authors", value: item.authorNames)
            if !item.secondaryInventoryNumbers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(title: "Secondary inventory numbers")
                    FlowLayout(spacing: 6) {
                        ForEach(item.secondaryInventoryNumbers, id: \.self) { num in
                            Text(num)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.mutedInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(AppTheme.disabledBg)
                                )
                        }
                    }
                }
            }
        }
        .museumPanel()
    }

    private func statusSection(item: ItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Current / Planned Status")

            VStack(alignment: .leading, spacing: 12) {
                statusRow(
                    icon: item.currentPlacement.presenceType == .external ? "paperplane.fill" : "building.columns.fill",
                    label: item.currentPlacement.presenceType == .external ? "Currently rented to" : "Current location",
                    value: item.currentPlacement.displayTargetName,
                    tint: AppTheme.primary
                )

                if let promised = item.planning.promisedOrganization {
                    statusRow(
                        icon: "calendar.badge.plus",
                        label: "Promised organization",
                        value: promised.name,
                        tint: AppTheme.plannedText
                    )
                }

                if let leave = item.planning.expectedLeaveDate {
                    statusRow(
                        icon: "calendar",
                        label: "Expected leave date",
                        value: leave.formattedForDisplay(),
                        tint: AppTheme.plannedText
                    )
                }
            }
        }
        .museumPanel()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("History")
                Spacer()
                Button("See all", action: onShowFullHistory)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }

            if store.isLoadingHistory && store.historyEntries.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let message = store.historyErrorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.rejectedText)
            } else if store.historyEntries.isEmpty {
                Text("No history yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.historyEntries.prefix(3)) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
        .museumPanel()
    }

    private func actionSection(item: ItemResponse) -> some View {
        VStack(spacing: 10) {
            Button(action: onEdit) {
                Label("Edit metadata", systemImage: "square.and.pencil")
            }
            .buttonStyle(PrimaryButtonStyle(fillWidth: true))
            .disabled(item.archived)

            HStack(spacing: 10) {
                Button(action: onUpdatePlanning) {
                    Label("Planning", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(item.archived)

                Button(action: onCreateMovement) {
                    Label("Move", systemImage: "location.circle")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(item.archived)
            }
            .frame(maxWidth: .infinity)

            if store.role.isAdmin && !item.archived {
                Button(role: .destructive) {
                    showArchiveConfirmation = true
                } label: {
                    Label(store.isArchiving ? "Archiving…" : "Archive item", systemImage: "archivebox")
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(store.isArchiving)
            }
        }
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Could not load item", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.rejectedText)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
            Button("Retry") {
                Task { await store.reload() }
            }
            .buttonStyle(SoftButtonStyle())
        }
        .museumPanel()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppTheme.ink)
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title: label)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func statusRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }

    private func placementTag(for item: ItemResponse) -> some View {
        switch item.currentPlacement.presenceType {
        case .internal:
            return StatusTag(text: "On-site", kind: .approved)
        case .external:
            return StatusTag(text: "On rental", kind: .planned)
        }
    }
}

struct HistoryRow: View {
    let entry: ItemHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.presenceType == .external ? "paperplane.fill" : "mappin.and.ellipse")
                .foregroundStyle(AppTheme.primary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.targetName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if entry.isOpen {
                        StatusTag(text: "Current", kind: .approved)
                    }
                }
                HStack(spacing: 6) {
                    Text(entry.moveInDate.formattedForDisplay())
                    if let out = entry.moveOutDate {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                        Text(out.formattedForDisplay())
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedInk)

                if let expected = entry.expectedReturnDate {
                    Text("Expected return: \(expected.formattedForDisplay())")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.plannedText)
                }

                if let actor = entry.movedByDevice {
                    HStack(spacing: 4) {
                        Image(systemName: actor.deviceIconName)
                            .font(.system(size: 10))
                        Text("Moved by \(actor.friendlyName)")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(AppTheme.subtleInk)
                } else {
                    Text("Moved by host admin")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.subtleInk)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.canvas)
        )
    }
}

// MARK: - Simple flow layout for chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: width.isFinite ? width : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
