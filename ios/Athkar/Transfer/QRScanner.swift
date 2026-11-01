@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Why the camera cannot scan, worded as the PWA's `transferCameraErrorText`.
enum QRScannerProblem: Equatable {
    case denied, unavailable, failed

    var message: String {
        switch self {
        case .denied:
            "لم يُسمح باستخدام الكاميرا. يمكنك لصق الرمز أو اختيار ملف، أو السماح بالكاميرا من الإعدادات ثم المحاولة مرة أخرى."
        case .unavailable:
            "لا تتوفر كاميرا على هذا الجهاز. الصق الرمز أو اختر ملفًا."
        case .failed:
            "الكاميرا مشغولة بتطبيق آخر. أغلقه ثم حاول مرة أخرى، أو الصق الرمز."
        }
    }
}

/// The back camera reading QR codes (`AVCaptureMetadataOutput`), for «مسح رمز QR». Each text read goes to `onCode`;
/// returning `true` stops the camera. Frames are read on this device only: nothing is recorded, kept or sent.
struct QRScanner: UIViewRepresentable {
    let onCode: @MainActor (String) -> Bool
    let onProblem: @MainActor (QRScannerProblem) -> Void

    /// Whether this device has a camera to scan with.
    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.onProblem = onProblem
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onProblem: onProblem)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: @MainActor (String) -> Bool
        var onProblem: @MainActor (QRScannerProblem) -> Void
        /// The session runs on its own queue: `startRunning` blocks until the camera is on.
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "local.dev.athkar.qr-scanner")
        private var finished = false

        init(onCode: @escaping @MainActor (String) -> Bool, onProblem: @escaping @MainActor (QRScannerProblem) -> Void) {
            self.onCode = onCode
            self.onProblem = onProblem
        }

        func attach(to view: PreviewView) {
            view.previewLayer.session = session
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configure()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    Task { @MainActor in
                        if granted { self.configure() } else { self.report(.denied) }
                    }
                }
            default:
                report(.denied)
            }
        }

        func stop() {
            finished = true
            let session = session
            queue.async { if session.isRunning { session.stopRunning() } }
        }

        private func configure() {
            guard !finished else { return }
            guard let device = AVCaptureDevice.default(for: .video) else { return report(.unavailable) }
            guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                return report(.failed)
            }
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            session.addInput(input)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return report(.failed)
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()
            let session = session
            queue.async { session.startRunning() }
        }

        private func report(_ problem: QRScannerProblem) {
            guard !finished else { return }
            finished = true
            onProblem(problem)
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                                        from connection: AVCaptureConnection) {
            let texts = objects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            // The delegate queue is the main queue.
            MainActor.assumeIsolated {
                for text in texts where !finished {
                    if onCode(text) { stop() }
                }
            }
        }
    }
}
