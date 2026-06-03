@preconcurrency import AVFoundation
import Combine
import ImageIO
import UIKit

extension Notification.Name {
    nonisolated(unsafe) static let cameraAccessResult = Notification.Name("Bokeh.cameraAccessResult")
}

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Used so Sendable closures can reach the manager on main without capturing `self`.
    private nonisolated(unsafe) static weak var current: CameraManager?

    @Published var permissionGranted = false
    /// True when the user has explicitly denied camera access (or restricted).
    @Published var permissionDenied = false

    let session = AVCaptureSession()

    private let videoQueue = DispatchQueue(label: "videoQueue")
    nonisolated(unsafe) private var videoOutput: AVCaptureVideoDataOutput?

    private var _session: AVCaptureSession { session }
    private var _videoQueue: DispatchQueue { videoQueue }

    // MARK: - One-shot Frame Capture

    struct CapturedFrame {
        let pixelBuffer: CVPixelBuffer
        let orientation: CGImagePropertyOrientation
    }

    /// Always access under `captureLock` — written on main, read on videoQueue.
    nonisolated(unsafe) private var _onCaptureFrame: ((CapturedFrame?) -> Void)?

    private nonisolated(unsafe) static let captureLock = NSLock()
    private nonisolated(unsafe) static var pendingPixelBuffer: CVPixelBuffer?
    private nonisolated(unsafe) static var pendingCaptureCallback: ((CapturedFrame?) -> Void)?

    func setCaptureFrameCallback(_ callback: ((CapturedFrame?) -> Void)?) {
        Self.captureLock.lock()
        _onCaptureFrame = callback
        Self.captureLock.unlock()
    }

    // MARK: - Init

    override init() {
        super.init()
        Self.current = self
        checkPermission()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraAccessResult(_:)),
            name: .cameraAccessResult,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        Self.current = nil
    }

    func requestPermission() {
        checkPermission()
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            permissionDenied = false
            setupSession()
        case .notDetermined:
            permissionDenied = false
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .cameraAccessResult,
                        object: nil,
                        userInfo: ["granted": granted]
                    )
                }
            }
        case .denied:
            permissionGranted = false
            permissionDenied = true
        case .restricted:
            permissionGranted = false
            permissionDenied = true
        @unknown default:
            permissionGranted = false
            permissionDenied = false
        }
    }

    @objc private func handleCameraAccessResult(_ notification: Notification) {
        guard let granted = notification.userInfo?["granted"] as? Bool else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                Self.current?.applyCameraAccessResult(granted: granted)
            }
            return
        }
        applyCameraAccessResult(granted: granted)
    }

    private func applyCameraAccessResult(granted: Bool) {
        permissionGranted = granted
        permissionDenied = !granted
        if granted {
            setupSession()
        }
    }

    // MARK: - Session Setup

    private var sessionConfigured = false

    private func setupSession() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = _session
        let videoQueue = _videoQueue
        videoQueue.async {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)
            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            Self.current?.videoOutput = output

            // Set delegate here on the video queue — this is the correct thread
            output.setSampleBufferDelegate(Self.current, queue: videoQueue)

            session.commitConfiguration()
            session.startRunning()
        }
    }

    func setVideoRotationAngle(_ angle: CGFloat) {
        guard let output = videoOutput,
              let connection = output.connection(with: .video) else { return }
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        Self.captureLock.lock()
        let capture = self._onCaptureFrame
        if capture != nil {
            self._onCaptureFrame = nil
        }
        Self.captureLock.unlock()

        guard let capture else { return }

        let copied = Self.copyPixelBufferStatic(pixelBuffer)
        Self.captureLock.lock()
        Self.pendingPixelBuffer = copied
        Self.pendingCaptureCallback = capture
        Self.captureLock.unlock()
        DispatchQueue.main.async {
            Task { @MainActor in
                Self.deliverPendingCapturedFrame()
            }
        }
    }

    @MainActor
    private static func deliverPendingCapturedFrame() {
        Self.captureLock.lock()
        let buffer = Self.pendingPixelBuffer
        let callback = Self.pendingCaptureCallback
        Self.pendingPixelBuffer = nil
        Self.pendingCaptureCallback = nil
        Self.captureLock.unlock()
        guard let callback, let buffer else { return }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let orientation = Self.cgImageOrientationFromInterface(bufferWidth: w, bufferHeight: h)
        let frame = CapturedFrame(pixelBuffer: buffer, orientation: orientation)
        callback(frame)
    }

    @MainActor
    private static func cgImageOrientationFromInterface(bufferWidth w: Int, bufferHeight h: Int) -> CGImagePropertyOrientation {
        let io: UIInterfaceOrientation? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .interfaceOrientation
        let isPortraitLayout = h > w
        if isPortraitLayout { return .up }
        switch io {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .unknown, nil: return .right
        @unknown default: return .right
        }
    }

    private nonisolated static func copyPixelBufferStatic(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)

        var dest: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs, &dest)
        guard status == kCVReturnSuccess, let out = dest else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(out, [])
        defer {
            CVPixelBufferUnlockBaseAddress(out, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let srcAddr = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dstAddr = CVPixelBufferGetBaseAddressOfPlane(out, plane) else { continue }
                let bpr = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let h = CVPixelBufferGetHeightOfPlane(source, plane)
                memcpy(dstAddr, srcAddr, bpr * h)
            }
        } else {
            guard let srcBase = CVPixelBufferGetBaseAddress(source),
                  let dstBase = CVPixelBufferGetBaseAddress(out) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(source)
            memcpy(dstBase, srcBase, bytesPerRow * height)
        }
        return out
    }
}
