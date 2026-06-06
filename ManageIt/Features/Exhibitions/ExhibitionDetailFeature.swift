import SwiftUI
import UserNotifications

struct ExhibitionDetailView: View {
    let store: ExhibitionDetailFeatureModel
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isLoading && store.exhibition == nil {
                    ProgressView().padding(.top, 80)
                } else if let exhibition = store.exhibition {
                    headerSection(exhibition: exhibition)
                    metadataSection(exhibition: exhibition)
                    itemsSection(exhibition: exhibition)
                    actionSection(exhibition: exhibition)
                } else if let message = store.errorMessage {
                    errorCard(message: message)
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Exhibition")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.exhibition == nil {
                await store.load()
            }
        }
        .refreshable {
            await store.load()
        }
    }

    private func headerSection(exhibition: ExhibitionResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(exhibition.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                phaseTag(for: exhibition.phase)
            }
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12))
                Text(exhibition.locationPath)
                    .font(.system(size: 13))
            }
            .foregroundStyle(AppTheme.mutedInk)
        }
        .museumPanel()
    }

    private func metadataSection(exhibition: ExhibitionResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Dates")

            HStack(spacing: 14) {
                dateColumn(title: "Start", date: exhibition.startDate)
                Image(systemName: "arrow.right")
                    .foregroundStyle(AppTheme.subtleInk)
                dateColumn(title: "End", date: exhibition.endDate)
            }

            if let scheduled = store.scheduledReminderDate {
                reminderChip(text: "Local end reminder set for \(scheduled.formatted(date: .abbreviated, time: .shortened))")
            } else if exhibition.phase != .ended {
                Text(reminderHint(for: store.reminderCoordinator.permissionStatus))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .museumPanel()
    }

    private func reminderHint(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Notifications are disabled — enable them in iOS Settings to receive an end-of-exhibition reminder."
        case .notDetermined:
            return "Allow notifications to receive a local end-of-exhibition reminder."
        default:
            return "Local end reminder will be scheduled from the end date."
        }
    }

    private func reminderChip(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(AppTheme.plannedText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(AppTheme.plannedBg))
    }

    private func itemsSection(exhibition: ExhibitionResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Items")
                Spacer()
                Text("\(exhibition.itemCount) total")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
            }

            if let items = exhibition.items, !items.isEmpty {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        exhibitionItemRow(item: item, exhibition: exhibition)
                    }
                }
            } else {
                Text("No items linked.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .museumPanel()
    }

    private func exhibitionItemRow(item: ExhibitionItemSummary, exhibition: ExhibitionResponse) -> some View {
        let placementMatches = item.currentPlacement?.location?.id == exhibition.locationId
            && item.currentPlacement?.presenceType == .internal

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.stack.fill")
                .foregroundStyle(AppTheme.primary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(item.mainInventoryNumber)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedInk)
                if exhibition.phase == .active && !placementMatches {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Not at exhibition location")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(AppTheme.rejectedText)
                }
            }
            Spacer()
            if item.archived {
                StatusTag(text: "Archived", kind: .expired)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(AppTheme.canvas)
        )
    }

    private func actionSection(exhibition: ExhibitionResponse) -> some View {
        Button(action: onEdit) {
            Label("Edit exhibition", systemImage: "square.and.pencil")
        }
        .buttonStyle(PrimaryButtonStyle(fillWidth: true))
        .disabled(exhibition.phase == .ended)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Could not load exhibition", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.rejectedText)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
            Button("Retry") {
                Task { await store.load() }
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

    private func dateColumn(title: String, date: BusinessDate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.subtleInk)
                .tracking(0.6)
            Text(date.formattedForDisplay())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func phaseTag(for phase: ExhibitionPhase) -> some View {
        switch phase {
        case .planned: return StatusTag(text: "Planned", kind: .planned)
        case .active: return StatusTag(text: "Active", kind: .approved)
        case .ended: return StatusTag(text: "Ended", kind: .expired)
        }
    }
}
