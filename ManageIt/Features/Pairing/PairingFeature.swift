import SwiftUI

struct PairingFeatureView: View {
    let store: PairingFeatureModel

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if store.phase.showsScanner {
                    scannerCard
                    manualEntryCard(manualPairingCode: $store.manualPairingCode)
                } else {
                    waitingCard
                }

                if let errorMessage = store.errorMessage {
                    errorCard(errorMessage)
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ManageIt")
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)

            Text("Pair this iPhone with the museum server by scanning the host QR code before opening the inventory workspace.")
                .font(.body)
                .foregroundStyle(AppTheme.mutedInk)
        }
    }

    private var scannerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("QR scan")
                Spacer()
                scannerStatusBadge
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.ink.opacity(0.92))
                    .frame(height: 280)

                QRScannerView(
                    isEnabled: store.phase == .ready,
                    onCodeScanned: { scannedValue in
                        Task {
                            await store.beginPairing(from: scannedValue)
                        }
                    },
                    onStateChanged: store.updateScannerState
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .frame(height: 280)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(AppTheme.scannerFrame, style: StrokeStyle(lineWidth: 1.5, dash: [10, 8]))
                    .frame(height: 280)

                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(AppTheme.paper)

                    Text(store.scannerHelperText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.paper.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                if store.phase == .submitting {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .overlay {
                            ProgressView("Checking pairing token…")
                                .progressViewStyle(.circular)
                                .tint(AppTheme.paper)
                                .foregroundStyle(AppTheme.paper)
                        }
                }
            }

            Text("The QR should come from the host-only admin screen that generated the mobile pairing request.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .museumPanel()
    }

    private func manualEntryCard(manualPairingCode: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Manual link")

            Text("Useful on Simulator or when camera access is unavailable. Paste the full `manageit://pair?...` link. A raw token still works if this iPhone already remembers the same server from an earlier pairing.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedInk)

            TextField("manageit://pair?server=http%3A%2F%2F192.168.1.50&token=...", text: manualPairingCode, axis: .vertical)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .lineLimit(2...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline, lineWidth: 1)
                )

            Button("Activate From Pairing Link") {
                Task {
                    await store.beginPairing(from: store.manualPairingCode)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.deepClay)
            .disabled(!store.canStartPairingManually)
        }
        .museumPanel()
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.deepClay)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.statusHeadline)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Text(store.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            if let status = store.lastStatus {
                VStack(alignment: .leading, spacing: 10) {
                    PairingProgressRow(
                        title: "QR accepted",
                        detail: status.scannedAt == nil ? "Waiting for first scan confirmation." : status.scannedAt!.formatted(date: .omitted, time: .shortened),
                        isActive: true
                    )

                    PairingProgressRow(
                        title: "Host naming",
                        detail: status.status == .completed
                            ? (status.friendlyName ?? "Completed")
                            : "Waiting for the host admin to finalize the device name.",
                        isActive: status.status == .scanned || status.status == .completed
                    )

                    PairingProgressRow(
                        title: "Session activation",
                        detail: store.phase == .finalizing ? "Issuing secure device credentials." : "Starts automatically after host confirmation.",
                        isActive: store.phase == .finalizing
                    )
                }
            }

            if let expiresAt = store.lastStatus?.expiresAt {
                Text("Token expires \(expiresAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .museumPanel()
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.deepClay)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.alertBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.alertBorder, lineWidth: 1)
        )
    }

    private var scannerStatusBadge: some View {
        Text(store.scannerStatusTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.badgeBackground)
            )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.subtleInk)
            .tracking(0.8)
    }
}

private struct PairingProgressRow: View {
    let title: String
    let detail: String
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? AppTheme.deepClay : AppTheme.outline)
                .font(.body.weight(.semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }
}

#Preview {
    PairingFeatureView(
        store: PairingFeatureModel(
            apiClient: ManageItAPIClient(),
            keychainStore: KeychainStore(),
            initialServerAddress: "192.168.1.24"
        )
    )
}
