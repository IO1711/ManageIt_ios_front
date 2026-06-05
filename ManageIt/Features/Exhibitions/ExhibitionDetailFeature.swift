import SwiftUI

struct ExhibitionDetailView: View {
    let store: ExhibitionDetailFeatureModel
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isLoading && store.exhibition == nil {
                    ProgressView()
                        .padding(.top, 80)
                } else if let exhibition = store.exhibition {
                    headerSection(exhibition: exhibition)
                    scheduleSection(exhibition: exhibition)
                    itemsSection(exhibition: exhibition)
                } else if let message = store.errorMessage {
                    errorCard(message: message)
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Exhibition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.exhibition != nil {
                    Button("Edit", action: onEdit)
                }
            }
        }
        .task {
            if store.exhibition == nil {
                await store.load()
            }
        }
        .refreshable {
            await store.load()
        }
    }

    private func headerSection(exhibition: ExhibitionDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exhibition.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                StatusTag(text: exhibition.phase.displayName, kind: phaseTagKind(exhibition.phase))
            }

            Label(exhibition.location.displayName, systemImage: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .museumPanel()
    }

    private func scheduleSection(exhibition: ExhibitionDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Schedule")

            detailRow(
                label: "Start date",
                value: exhibition.startDate.formattedForDisplay()
            )
            detailRow(
                label: "End date",
                value: exhibition.endDate.formattedForDisplay()
            )
            Text("The iPhone keeps a local end reminder scheduled for \(exhibition.endDate.formattedForDisplay()) at 10:00 AM.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.subtleInk)
        }
        .museumPanel()
    }

    private func itemsSection(exhibition: ExhibitionDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Linked items")

            ForEach(exhibition.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(item.mainInventoryNumber)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedInk)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.canvas)
                )
            }
        }
        .museumPanel()
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

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title: label)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

private func phaseTagKind(_ phase: ExhibitionPhase) -> StatusTag.Kind {
    switch phase {
    case .planned:
        return .planned
    case .active:
        return .approved
    case .ended:
        return .expired
    }
}
