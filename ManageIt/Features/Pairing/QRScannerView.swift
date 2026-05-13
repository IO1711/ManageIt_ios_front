import AVFoundation
import SwiftUI
import UIKit

enum PairingScannerState: Equatable {
    case idle
    case requestingPermission
    case cameraReady
    case permissionDenied
    case unavailable
}

struct QRScannerView: UIViewRepresentable {
    let isEnabled: Bool
    let onCodeScanned: (String) -> Void
    let onStateChanged: (PairingScannerState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onStateChanged: onStateChanged)
    }

    func makeUIView(context: Context) -> ScannerPreviewView {
        let previewView = ScannerPreviewView()
        previewView.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attachPreview(previewView)
        return previewView
    }

    func updateUIView(_ uiView: ScannerPreviewView, context: Context) {
        context.coordinator.attachPreview(uiView)
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleUIView(_ uiView: ScannerPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCodeScanned: (String) -> Void
        private let onStateChanged: (PairingScannerState) -> Void
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "manageit.qr.session")

        private weak var previewView: ScannerPreviewView?
        private var didConfigureSession = false
        private var lastScannedCode: String?
        private var isEnabled = false

        init(
            onCodeScanned: @escaping (String) -> Void,
            onStateChanged: @escaping (PairingScannerState) -> Void
        ) {
            self.onCodeScanned = onCodeScanned
            self.onStateChanged = onStateChanged
        }

        func attachPreview(_ previewView: ScannerPreviewView) {
            self.previewView = previewView
            previewView.previewLayer.session = session
        }

        func setEnabled(_ enabled: Bool) {
            isEnabled = enabled

            if enabled {
                prepareCamera()
            } else {
                lastScannedCode = nil
                stop()
            }
        }

        func stop() {
            sessionQueue.async { [session] in
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }

        private func prepareCamera() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureIfNeededAndStart()
            case .notDetermined:
                onStateChanged(.requestingPermission)
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else {
                        return
                    }

                    DispatchQueue.main.async {
                        if granted {
                            self.configureIfNeededAndStart()
                        } else {
                            self.onStateChanged(.permissionDenied)
                        }
                    }
                }
            case .restricted, .denied:
                onStateChanged(.permissionDenied)
            @unknown default:
                onStateChanged(.unavailable)
            }
        }

        private func configureIfNeededAndStart() {
            guard isEnabled else {
                return
            }

            guard AVCaptureDevice.default(for: .video) != nil else {
                onStateChanged(.unavailable)
                return
            }

            if !didConfigureSession {
                configureSession()
            }

            guard didConfigureSession else {
                onStateChanged(.unavailable)
                return
            }

            onStateChanged(.cameraReady)

            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
            }
        }

        private func configureSession() {
            guard let camera = AVCaptureDevice.default(for: .video) else {
                onStateChanged(.unavailable)
                return
            }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .high

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    onStateChanged(.unavailable)
                    return
                }
            } catch {
                onStateChanged(.unavailable)
                return
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            } else {
                onStateChanged(.unavailable)
                return
            }

            didConfigureSession = true
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard isEnabled else {
                return
            }

            guard
                let qrCode = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                qrCode.type == .qr,
                let value = qrCode.stringValue,
                value != lastScannedCode
            else {
                return
            }

            lastScannedCode = value
            onCodeScanned(value)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.lastScannedCode = nil
            }
        }
    }
}

final class ScannerPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
