import SwiftUI

struct ExhibitionsFeatureView: View {
    let store: ExhibitionsFeatureModel
    let onSelectExhibition: (Int64) -> Void
    let onCreateExhibition: () -> Void

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            phaseFilterPills
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            content
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            if !store.hasLoadedOnce {
                await store.load()
            }
        }
        .refreshable {
            await store.load()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Exhibitions")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Plan, run, and look back at museum exhibitions.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedInk)
            }
            Spacer()
            Button(action: onCreateExhibition) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var phaseFilterPills: some View {
        HStack(spacing: 8) {
            phasePill(title: "All", phase: nil)
            phasePill(title: "Active", phase: .active)
            phasePill(title: "Planned", phase: .planned)
            phasePill(title: "Ended", phase: .ended)
        }
    }

    private func phasePill(title: String, phase: ExhibitionPhase?) -> some View {
        let isSelected = store.phaseFilter == phase
        return Button {
            store.setPhaseFilter(phase)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : AppTheme.mutedInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? AppTheme.primary : AppTheme.paper)
                )
                .overlay(
                    Capsule().stroke(AppTheme.cardBorder, lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.errorMessage, store.exhibitions.isEmpty {
            errorState(message: message)
        } else if store.isLoading && store.exhibitions.isEmpty {
            ProgressView()
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
        } else if store.filteredExhibitions.isEmpty && store.hasLoadedOnce {
            emptyState
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.filteredExhibitions) { exhibition in
                    Button {
                        onSelectExhibition(exhibition.id)
                    } label: {
                        ExhibitionRow(exhibition: exhibition)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.mutedInk)
            Text(store.phaseFilter == nil
                ? "No exhibitions yet"
                : "Nothing in this phase")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Create an exhibition to group museum items by date and location.")
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

struct ExhibitionRow: View {
    let exhibition: ExhibitionResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exhibition.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text(exhibition.locationPath)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppTheme.mutedInk)
                }
                Spacer()
                phaseTag(for: exhibition.phase)
            }

            HStack(spacing: 14) {
                infoChip(
                    icon: "calendar",
                    text: "\(exhibition.startDate.formattedForDisplay()) → \(exhibition.endDate.formattedForDisplay())"
                )
                infoChip(
                    icon: "square.stack.3d.up.fill",
                    text: "\(exhibition.itemCount) item(s)"
                )
                Spacer()
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

    private func phaseTag(for phase: ExhibitionPhase) -> some View {
        switch phase {
        case .planned: return StatusTag(text: "Planned", kind: .planned)
        case .active: return StatusTag(text: "Active", kind: .approved)
        case .ended: return StatusTag(text: "Ended", kind: .expired)
        }
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.mutedInk)
    }
}
