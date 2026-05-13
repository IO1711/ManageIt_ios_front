//
//  ContentView.swift
//  ManageIt
//
//  Created by Bilolbek Rayimov on 12/05/26.
//

import SwiftUI

struct ContentView: View {
    let appModel: AppModel

    var body: some View {
        Group {
            if let pairedDevice = appModel.pairedDevice {
                DeviceReadyView(
                    pairedDevice: pairedDevice,
                    hasActiveSession: appModel.activeSession != nil,
                    clearLocalPairing: appModel.clearLocalPairing
                )
            } else {
                PairingFeatureView(store: appModel.pairingModel)
            }
        }
        .background(AppTheme.canvas.ignoresSafeArea())
    }
}

private struct DeviceReadyView: View {
    let pairedDevice: StoredDeviceContext
    let hasActiveSession: Bool
    let clearLocalPairing: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ManageIt")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.ink)

                    Text("This iPhone is paired with the museum host and ready for the next feature slice.")
                        .font(.body)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Label(hasActiveSession ? "Session issued during pairing" : "Pairing saved on this device", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    deviceRow("Friendly name", pairedDevice.friendlyName)
                    deviceRow("Role", pairedDevice.role.displayName)
                    deviceRow("Device type", pairedDevice.deviceType.displayName)
                    deviceRow("Server", pairedDevice.serverAddress)
                    deviceRow("Refresh token expires", pairedDevice.refreshTokenExpiresAt.formatted(date: .abbreviated, time: .shortened))

                    Text("Inventory screens come next after you validate this pairing flow.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    Button("Clear local pairing", role: .destructive, action: clearLocalPairing)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.deepClay)
                }
                .museumPanel()
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func deviceRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.subtleInk)

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

#Preview {
    ContentView(appModel: AppModel())
}
