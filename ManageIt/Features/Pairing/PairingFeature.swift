import SwiftUI

struct PairingFeatureView: View {
    let store: PairingFeatureModel
    var onActivateDemoMode: (() -> Void)? = nil

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if store.phase.showsScanner {
                    scannerCard
                    manualEntryCard(manualPairingCode: $store.manualPairingCode)
                    #if DEBUG
                    demoModeCard
                    #endif
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

    #if DEBUG
    private var demoModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(AppTheme.primary)
                sectionLabel("Preview without backend")
            }

            Text("Skip pairing and open the app with sample data so you can navigate inventory, item detail, create, planning, movement, history, and admin location screens. Visible only in debug builds.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)

            Button {
                onActivateDemoMode?()
            } label: {
                Label("Open demo mode", systemImage: "play.fill")
            }
            .buttonStyle(SoftButtonStyle())
        }
        .museumPanel()
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.primary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .semibold))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ManageIt")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Museum inventory")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .padding(.bottom, 4)

            Text("Pair this iPhone with the museum server")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            Text("Scan the host QR code or paste the pairing link to register this device.")
                .font(.system(size: 14))
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.ink)
                    .frame(height: 260)

                QRScannerView(
                    isEnabled: store.phase == .ready,
                    onCodeScanned: { scannedValue in
                        Task {
                            await store.beginPairing(from: scannedValue)
                        }
                    },
                    onStateChanged: store.updateScannerState
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(height: 260)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .frame(height: 260)
                    .padding(8)

                VStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.95))

                    Text(store.scannerHelperText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                if store.phase == .submitting {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .overlay {
                            ProgressView("Checking pairing token…")
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .foregroundStyle(Color.white)
                                .font(.system(size: 13, weight: .medium))
                        }
                }
            }

            Text("The QR should come from the host-only admin screen that generated the mobile pairing request.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .museumPanel()
    }

    private func manualEntryCard(manualPairingCode: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Manual link")

            Text("Use this on the Simulator or when camera access is unavailable. Paste the full `manageit://pair?...` link.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)

            TextField("manageit://pair?server=…&token=…", text: manualPairingCode, axis: .vertical)
                .font(.system(size: 13))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .lineLimit(2...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )

            Button {
                Task {
                    await store.beginPairing(from: store.manualPairingCode)
                }
            } label: {
                Text("Activate from pairing link")
            }
            .buttonStyle(PrimaryButtonStyle(fillWidth: true))
            .disabled(!store.canStartPairingManually)
            .opacity(store.canStartPairingManually ? 1 : 0.5)
        }
        .museumPanel()
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.statusHeadline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text(store.statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            if let status = store.lastStatus {
                VStack(alignment: .leading, spacing: 10) {
                    PairingProgressRow(
                        title: "QR accepted",
                        detail: status.scannedAt == nil
                            ? "Waiting for first scan confirmation."
                            : status.scannedAt!.formatted(date: .omitted, time: .shortened),
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
                        detail: store.phase == .finalizing
                            ? "Issuing secure device credentials."
                            : "Starts automatically after host confirmation.",
                        isActive: store.phase == .finalizing
                    )
                }
            }

            if let expiresAt = store.lastStatus?.expiresAt {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("Token expires \(expiresAt.formatted(date: .omitted, time: .shortened)).")
                        .font(.system(size: 12))
                }
                .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .museumPanel()
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.rejectedText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.rejectedBg)
        )
    }

    private var scannerStatusBadge: some View {
        StatusTag(text: store.scannerStatusTitle, kind: badgeKind(for: store.scannerState))
    }

    private func badgeKind(for state: PairingScannerState) -> StatusTag.Kind {
        switch state {
        case .cameraReady: return .approved
        case .idle, .requestingPermission: return .editor
        case .permissionDenied, .unavailable: return .expired
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AppTheme.mutedInk)
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
                .foregroundStyle(isActive ? AppTheme.primary : AppTheme.subtleInk)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)

                Text(detail)
                    .font(.system(size: 12))
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
