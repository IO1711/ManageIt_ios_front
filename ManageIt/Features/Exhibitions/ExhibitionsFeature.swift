import SwiftUI

struct ExhibitionsFeatureView: View {
    let store: ExhibitionsFeatureModel
    let onSelectExhibition: (Int64) -> Void
    let onCreateExhibition: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            content
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            if store.exhibitions.isEmpty {
                await store.load()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Exhibitions")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Track planned, active, and ended exhibitions.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            }
            Spacer()
            Button(action: onCreateExhibition) {
                Label("New exhibition", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.errorMessage, store.exhibitions.isEmpty {
            errorState(message: message)
        } else if store.isLoading && store.exhibitions.isEmpty {
            ProgressView()
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
        } else if store.exhibitions.isEmpty {
            emptyState
        } else {
            sectionsList
        }
    }

    private var sectionsList: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach([ExhibitionPhase.active, .planned, .ended], id: \.rawValue) { phase in
                    let rows = store.exhibitions(for: phase)
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(phase.displayName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.ink)

                            ForEach(rows) { exhibition in
                                Button {
                                    onSelectExhibition(exhibition.id)
                                } label: {
                                    ExhibitionSummaryRow(exhibition: exhibition)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .refreshable {
            await store.load()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.mutedInk)
            Text("No exhibitions yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Create the first exhibition to group items, choose a location, and schedule a local end reminder.")
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
            Text("Could not load exhibitions")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await store.load() }
            }
            .buttonStyle(SoftButtonStyle())
        }
        .padding(.horizontal, 30)
        .padding(.top, 50)
    }
}

private struct ExhibitionSummaryRow: View {
    let exhibition: ExhibitionSummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(exhibition.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(exhibition.locationPath)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()
                StatusTag(text: exhibition.phase.displayName, kind: phaseTagKind(exhibition.phase))
            }

            HStack(spacing: 12) {
                Label(
                    "\(exhibition.startDate.formattedForDisplay()) - \(exhibition.endDate.formattedForDisplay())",
                    systemImage: "calendar"
                )
                Label("\(exhibition.itemCount) items", systemImage: "shippingbox.fill")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.subtleInk)
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
