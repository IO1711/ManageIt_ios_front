import Foundation
import Observation

@MainActor
@Observable
final class PairingFeatureModel {
    enum Phase: Equatable {
        case ready
        case submitting
        case waiting
        case finalizing

        var showsScanner: Bool {
            self == .ready || self == .submitting
        }
    }

    @ObservationIgnored
    var onActivationComplete: ((MobilePairingCompleteResponse, String) throws -> Void)?

    var serverAddress: String
    var manualPairingCode = ""
    var phase: Phase = .ready
    var errorMessage: String?
    var lastStatus: MobilePairingStatusResponse?
    var scannerState: PairingScannerState = .idle
    var statusHeadline = "Waiting for pairing"
    var statusDetail = "Scan the host QR code to begin."

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let keychainStore: KeychainStore

    @ObservationIgnored
    private var pollTask: Task<Void, Never>?

    @ObservationIgnored
    private var isCompletingPairing = false

    init(
        apiClient: ManageItAPIClient,
        keychainStore: KeychainStore,
        initialServerAddress: String
    ) {
        self.apiClient = apiClient
        self.keychainStore = keychainStore
        self.serverAddress = initialServerAddress
    }

    var canStartPairingManually: Bool {
        phase == .ready
            && !manualPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var scannerStatusTitle: String {
        switch scannerState {
        case .idle:
            return "Ready"
        case .requestingPermission:
            return "Permission"
        case .cameraReady:
            return "Camera On"
        case .permissionDenied:
            return "Manual Entry"
        case .unavailable:
            return "Unavailable"
        }
    }

    var scannerHelperText: String {
        switch scannerState {
        case .idle, .cameraReady:
            return "Align the pairing QR inside the frame."
        case .requestingPermission:
            return "Waiting for camera permission."
        case .permissionDenied:
            return "Camera access is off. Paste the pairing link below."
        case .unavailable:
            return "Camera input is unavailable here. Paste the pairing link below."
        }
    }

    func updateScannerState(_ newState: PairingScannerState) {
        scannerState = newState
    }

    func beginPairing(from rawValue: String) async {
        guard phase == .ready else {
            return
        }

        errorMessage = nil

        do {
            let pairingPayload = try parsePairingPayload(from: rawValue)
            let server = try resolvedServer(explicitAddress: pairingPayload.serverAddress)
            let installationId: UUID

            do {
                installationId = try keychainStore.loadOrCreateInstallationId()
            } catch {
                throw ManageItError.deviceIdentityUnavailable
            }

            let metadata = DeviceMetadata.current(installationId: installationId)

            phase = .submitting
            statusHeadline = "Checking pairing token"
            statusDetail = "Registering this iPhone with the museum server."

            let response = try await apiClient.scanPairing(
                serverURL: server.url,
                request: MobilePairingScanRequest(
                    pairingToken: pairingPayload.pairingToken,
                    installationId: metadata.installationId,
                    suggestedName: metadata.suggestedName,
                    platformName: metadata.platformName,
                    platformVersion: metadata.platformVersion,
                    modelName: metadata.modelName
                )
            )

            serverAddress = server.canonicalAddress
            manualPairingCode = ""

            let shouldComplete = try applyStatus(response)
            if shouldComplete {
                try await completePairing(pairingId: response.pairingId, server: server)
            } else {
                beginPolling(pairingId: response.pairingId, server: server)
            }
        } catch {
            handleFailure(error)
        }
    }

    func reset(keepServerAddress: Bool) {
        pollTask?.cancel()
        pollTask = nil
        phase = .ready
        errorMessage = nil
        lastStatus = nil
        statusHeadline = "Waiting for pairing"
        statusDetail = "Scan the host QR code to begin."
        manualPairingCode = ""

        if !keepServerAddress {
            serverAddress = ""
        }
    }

    @discardableResult
    private func applyStatus(_ status: MobilePairingStatusResponse) throws -> Bool {
        lastStatus = status

        if status.expired {
            throw ManageItError.pairingExpired
        }

        switch status.status {
        case .generated, .scanned:
            phase = .waiting
            statusHeadline = "Awaiting host confirmation"
            statusDetail = "Keep this screen open while the host admin finishes the device name."
            return false
        case .completed:
            phase = .finalizing
            statusHeadline = "Activating device"
            statusDetail = "Receiving secure credentials from the host."
            return true
        case .cancelled:
            throw ManageItError.pairingCancelled
        }
    }

    private func beginPolling(pairingId: UUID, server: ResolvedServer) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let response = try await apiClient.fetchPairingStatus(serverURL: server.url, pairingId: pairingId)
                    let shouldComplete = try applyStatus(response)

                    if shouldComplete {
                        pollTask = nil
                        try await completePairing(
                            pairingId: pairingId,
                            server: server,
                            cancelPollingTask: false
                        )
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    handleFailure(error)
                    return
                }
            }
        }
    }

    private func completePairing(
        pairingId: UUID,
        server: ResolvedServer,
        cancelPollingTask: Bool = true
    ) async throws {
        guard !isCompletingPairing else {
            return
        }

        isCompletingPairing = true
        if cancelPollingTask {
            pollTask?.cancel()
            pollTask = nil
        }

        defer {
            isCompletingPairing = false
        }

        let response = try await apiClient.completePairing(serverURL: server.url, pairingId: pairingId)
        try onActivationComplete?(response, server.canonicalAddress)
    }

    private func handleFailure(_ error: Error) {
        pollTask?.cancel()
        pollTask = nil
        phase = .ready
        lastStatus = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong during pairing."
        statusHeadline = "Waiting for pairing"
        statusDetail = "Scan the host QR code to begin."
    }

    private func parsePairingPayload(from rawValue: String) throws -> PairingPayload {
        let cleanedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedValue.isEmpty else {
            throw ManageItError.invalidPairingCode
        }

        if let token = UUID(uuidString: cleanedValue) {
            return PairingPayload(pairingToken: token, serverAddress: nil)
        }

        if
            let components = URLComponents(string: cleanedValue),
            let tokenValue = components.queryItems?.first(where: { $0.name == "token" })?.value,
            let token = UUID(uuidString: tokenValue)
        {
            let serverAddress = components.queryItems?.first(where: { $0.name == "server" })?.value
            return PairingPayload(pairingToken: token, serverAddress: serverAddress)
        }

        throw ManageItError.invalidPairingCode
    }

    private func resolvedServer(explicitAddress: String?) throws -> ResolvedServer {
        let chosenAddress = explicitAddress ?? serverAddress
        var rawAddress = chosenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawAddress.isEmpty else {
            throw ManageItError.invalidServerAddress
        }

        if !rawAddress.contains("://") {
            rawAddress = "http://\(rawAddress)"
        }

        guard var components = URLComponents(string: rawAddress), components.host != nil else {
            throw ManageItError.invalidServerAddress
        }

        var cleanedPath = components.path
        while cleanedPath.hasSuffix("/") && cleanedPath.count > 1 {
            cleanedPath.removeLast()
        }

        if cleanedPath == "/api" {
            cleanedPath = ""
        }

        components.path = cleanedPath

        guard let url = components.url else {
            throw ManageItError.invalidServerAddress
        }

        return ResolvedServer(url: url, canonicalAddress: url.absoluteString)
    }
}

private struct ResolvedServer {
    let url: URL
    let canonicalAddress: String
}

private struct PairingPayload {
    let pairingToken: UUID
    let serverAddress: String?
}
