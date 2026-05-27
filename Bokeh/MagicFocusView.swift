import SwiftUI
import Combine
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

// MARK: - Subject Lifter

/// Wraps CVPixelBuffer for capture in @Sendable closures (buffer used only on processing queue after handoff).
private struct SendablePixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// Shared CIContext for image rendering. CIContext is thread-safe for concurrent use; nonisolated(unsafe) satisfies Swift's Sendable check.
private nonisolated(unsafe) let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

@MainActor
final class SubjectLifter: ObservableObject {

    enum Result: Equatable {
        case idle
        case processing
        case focused(cutout: UIImage, label: String?)
        #if DEBUG
        case debug(VisionDebugInfo)
        #endif
        case error(String)
    }

    @Published var result: Result = .idle
    @Published var debugMode: Bool = false

    private let processingQueue = DispatchQueue(label: "com.bokeh.subjectLifter", qos: .userInitiated)

    // MARK: - Vision Model Pre-warming

    /// Pre-warm the Vision model in background to avoid first-use latency.
    /// Call this early (e.g., when camera view appears) to load the ML model ahead of time.
    nonisolated static func prewarmVisionModel() {
        DispatchQueue.global(qos: .utility).async {
            // Creating and performing a dummy request loads the ML model into memory
            let request = VNGenerateForegroundInstanceMaskRequest()
            let dummyImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            guard let cgImage = CIContext().createCGImage(dummyImage, from: dummyImage.extent) else { return }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    /// Last captured frame for re-running with different orientations
    private var lastPixelBuffer: CVPixelBuffer?

    func lift(from frame: CameraManager.CapturedFrame) {
        result = .processing
        let orientation = frame.orientation
        let isDebug = debugMode
        lastPixelBuffer = frame.pixelBuffer
        let wrapped = SendablePixelBuffer(buffer: frame.pixelBuffer)
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.performLift(pixelBuffer: wrapped.buffer, orientation: orientation, emitDebug: isDebug)
        }
    }

    #if DEBUG
    /// Re-run vision with a different orientation (long-press to enable debug).
    func retryWithOrientation(_ orientation: CGImagePropertyOrientation) {
        guard let buffer = lastPixelBuffer else { return }
        result = .processing
        let wrapped = SendablePixelBuffer(buffer: buffer)
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.performLift(pixelBuffer: wrapped.buffer, orientation: orientation, emitDebug: true)
        }
    }

    /// Run Vision on a test image (debug).
    func liftTestImage() {
        result = .processing
        let isDebug = debugMode
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.performTestImageLift(emitDebug: isDebug)
        }
    }
    #endif

    func reset() {
        result = .idle
    }

    // MARK: - Pipeline

    private nonisolated func performLift(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        emitDebug: Bool
    ) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
            Task { @MainActor in self.result = .error("Could not decode frame.") }
            return
        }

        runVision(cgImage: cg, ciImage: ciImage, orientation: orientation, emitDebug: emitDebug)
    }

    #if DEBUG
    private nonisolated func performTestImageLift(emitDebug: Bool) {
        // Generate a test image: a filled circle on a white background (simulates "object on table")
        let size = CGSize(width: 400, height: 400)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            Task { @MainActor in self.result = .error("Could not create test image.") }
            return
        }
        // White background
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // Dark blue circle (the "object")
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        ctx.fillEllipse(in: CGRect(x: 100, y: 100, width: 200, height: 200))
        // Red triangle accent
        ctx.setFillColor(UIColor.systemRed.cgColor)
        ctx.move(to: CGPoint(x: 200, y: 50))
        ctx.addLine(to: CGPoint(x: 150, y: 140))
        ctx.addLine(to: CGPoint(x: 250, y: 140))
        ctx.closePath()
        ctx.fillPath()

        guard let uiImg = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImg = uiImg.cgImage else {
            Task { @MainActor in self.result = .error("Could not render test image.") }
            return
        }

        let ciImage = CIImage(cgImage: cgImg)
        runVision(cgImage: cgImg, ciImage: ciImage, orientation: .up, emitDebug: emitDebug)
    }
    #endif

    private nonisolated func runVision(
        cgImage cg: CGImage,
        ciImage: CIImage,
        orientation: CGImagePropertyOrientation,
        emitDebug: Bool
    ) {
        let isPortraitLayout = cg.height > cg.width
        let effectiveOrientation: CGImagePropertyOrientation = isPortraitLayout ? .up : orientation
        #if DEBUG
        let orientationLabel = Self.orientationName(effectiveOrientation)
        let inputSize = CGSize(width: cg.width, height: cg.height)
        let inputUIImage = UIImage(cgImage: cg)
        #endif

        // 1) Mask only first (we'll classify the foreground later for better labels)
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: effectiveOrientation, options: [:])
        do {
            try handler.perform([maskRequest])
        } catch {
            Task { @MainActor in self.result = .error("Vision failed: \(error.localizedDescription)") }
            return
        }

        guard let obs = maskRequest.results?.first as? VNInstanceMaskObservation else {
            #if DEBUG
            if emitDebug {
                let info = VisionDebugInfo(
                    inputImage: inputUIImage,
                    maskImage: nil,
                    boundingBox: .zero,
                    inputSize: inputSize,
                    instanceCount: 0,
                    confidence: nil,
                    orientationUsed: orientationLabel,
                    classLabel: nil
                )
                Task { @MainActor in self.result = .debug(info) }
                return
            }
            #endif
            Task { @MainActor in self.result = .error("Couldn't find a clear subject.") }
            return
        }

        do {
            let instances = obs.allInstances
            let maskBuffer = try obs.generateScaledMaskForImage(forInstances: instances, from: handler)

            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                .clampedToExtent()
                .cropped(to: ciImage.extent)

            // Foreground-only image for better classification (object, not scene)
            let clearBG = CIImage(color: .clear).cropped(to: ciImage.extent)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = ciImage
            blend.backgroundImage = clearBG
            blend.maskImage = maskCI

            guard let outCI = blend.outputImage,
                  let outCG = sharedCIContext.createCGImage(outCI, from: ciImage.extent) else {
                Task { @MainActor in self.result = .error("Could not render cutout.") }
                return
            }

            // Classify the foreground (cutout) so we get "book" not "structure"
            #if DEBUG
            let (label, confidence) = Self.classifyForegroundImage(outCG)
            #else
            let (label, _) = Self.classifyForegroundImage(outCG)
            #endif

            #if DEBUG
            let redMaskImage: UIImage? = {
                let redTint = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.45))
                    .cropped(to: ciImage.extent)
                let masked = CIFilter.blendWithMask()
                masked.inputImage = redTint
                masked.backgroundImage = CIImage(color: .clear).cropped(to: ciImage.extent)
                masked.maskImage = maskCI
                guard let out = masked.outputImage,
                      let outCG = sharedCIContext.createCGImage(out, from: ciImage.extent) else { return nil }
                let corrected = Self.rotatePixels(outCG, orientation: effectiveOrientation)
                return UIImage(cgImage: corrected, scale: 1.0, orientation: .up)
            }()

            let boundingBox: CGRect = {
                let maskCIFull = CIImage(cvPixelBuffer: maskBuffer)
                let maskExtent = maskCIFull.extent
                let imgExtent = ciImage.extent
                guard imgExtent.width > 0, imgExtent.height > 0 else { return .zero }
                return CGRect(
                    x: maskExtent.origin.x / imgExtent.width,
                    y: maskExtent.origin.y / imgExtent.height,
                    width: maskExtent.width / imgExtent.width,
                    height: maskExtent.height / imgExtent.height
                )
            }()

            if emitDebug {
                let correctedInput = Self.rotatePixels(cg, orientation: effectiveOrientation)
                let rotatedInputUI = UIImage(cgImage: correctedInput, scale: 1.0, orientation: .up)
                let info = VisionDebugInfo(
                    inputImage: rotatedInputUI,
                    maskImage: redMaskImage,
                    boundingBox: boundingBox,
                    inputSize: inputSize,
                    instanceCount: instances.count,
                    confidence: confidence,
                    orientationUsed: orientationLabel,
                    classLabel: label
                )
                Task { @MainActor in self.result = .debug(info) }
                return
            }
            #endif
            let correctedCG = Self.rotatePixels(outCG, orientation: effectiveOrientation)
            let cutout = UIImage(cgImage: correctedCG, scale: 1.0, orientation: .up)
            Task { @MainActor in
                self.result = .focused(cutout: cutout, label: label)
            }
        } catch {
            Task { @MainActor in self.result = .error("Couldn't generate cutout.") }
        }
    }

    /// Classify foreground image and return first specific label (skip generic ones like "structure").
    private nonisolated static func classifyForegroundImage(_ cgImage: CGImage) -> (label: String?, confidence: Float?) {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return (nil, nil)
        }
        // Skip generic scene/abstract identifiers; prefer concrete object labels
        let genericIdentifiers: Set<String> = [
            "structure", "artifact", "object", "thing", "entity", "building",
            "nature", "outdoor", "indoor", "container", "furniture", "equipment",
            "material", "pattern", "shape", "symbol", "text", "architecture"
        ]
        let results = request.results ?? []
        for obs in results {
            let id = obs.identifier.lowercased()
                .replacingOccurrences(of: " ", with: "_")
            if genericIdentifiers.contains(id) { continue }
            if id.count < 3 { continue }
            return (obs.identifier, obs.confidence)
        }
        return (results.first?.identifier, results.first?.confidence)
    }

    // MARK: - Helpers

    private nonisolated static func orientationName(_ o: CGImagePropertyOrientation) -> String {
        switch o {
        case .up: return ".up (1)"
        case .upMirrored: return ".upMirrored (2)"
        case .down: return ".down (3)"
        case .downMirrored: return ".downMirrored (4)"
        case .leftMirrored: return ".leftMirrored (5)"
        case .rightMirrored: return ".rightMirrored (6)"
        case .right: return ".right (7)"  // Note: 6 is rightMirrored, 7 is usually not standard but we keep the label
        case .left: return ".left (8)"
        @unknown default: return "unknown (\(o.rawValue))"
        }
    }

    /// Physically rotates/flips CGImage pixels to match the given orientation.
    /// This ensures the output image is correctly oriented at the pixel level
    /// (important because PNG ignores UIImage orientation metadata).
    nonisolated static func rotatePixels(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return image }

        let w = image.width
        let h = image.height

        // Determine output size (swap for 90°/270° rotations)
        let swapsWH: Bool = {
            switch orientation {
            case .left, .right, .leftMirrored, .rightMirrored: return true
            default: return false
            }
        }()
        let outW = swapsWH ? h : w
        let outH = swapsWH ? w : h

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: outW,
                  height: outH,
                  bitsPerComponent: image.bitsPerComponent,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }

        // Apply the transform corresponding to the orientation
        switch orientation {
        case .up:
            break
        case .down:
            ctx.translateBy(x: CGFloat(outW), y: CGFloat(outH))
            ctx.rotate(by: .pi)
        case .left:
            ctx.translateBy(x: CGFloat(outW), y: 0)
            ctx.rotate(by: .pi / 2)
        case .right:
            ctx.translateBy(x: 0, y: CGFloat(outH))
            ctx.rotate(by: -.pi / 2)
        case .upMirrored:
            ctx.translateBy(x: CGFloat(outW), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case .downMirrored:
            ctx.translateBy(x: 0, y: CGFloat(outH))
            ctx.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            ctx.translateBy(x: CGFloat(outW), y: CGFloat(outH))
            ctx.rotate(by: .pi / 2)
            ctx.scaleBy(x: -1, y: 1)
        case .rightMirrored:
            ctx.rotate(by: -.pi / 2)
            ctx.scaleBy(x: -1, y: 1)
        @unknown default:
            break
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

// MARK: - Magic Focus View (tap → lift subject cutout)

struct MagicFocusView: View {
    @ObservedObject var manager: CameraManager
    var gamification: GamificationManager
    /// Binding to communicate focused state to parent (hides top nav bar)
    @Binding var isFocused: Bool
    /// Called when the user taps "Mark as Done" after focusing and timing.
    var onDone: (UIImage?, String?, TimeInterval) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var lifter = SubjectLifter()
    @State private var timeElapsed: Int = 0
    @State private var showDebugIndicator = false
    @State private var videoRotationAngle: CGFloat = 90
    @State private var floatOffset: CGFloat = 0
    @State private var editedLabel: String = ""
    @FocusState private var isLabelFieldFocused: Bool
    @State private var instructionPulse: CGFloat = 1.0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let teal = Color.theme.bokehTeal

    var body: some View {
        ZStack {
            CameraPreview(session: manager.session, rotationAngle: videoRotationAngle)
                .ignoresSafeArea()

            switch lifter.result {
            case .idle:
                VStack {
                    Spacer()

                    #if DEBUG
                    // Debug mode: show test image button
                    if lifter.debugMode {
                        Button(action: { lifter.liftTestImage() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.badge.checkmark")
                                Text("Load Test Image")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .frame(minHeight: AppLayoutConstants.minTouchTarget)
                        .padding(.bottom, 12)
                    }
                    #endif

                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.tap")
                            Text("Tap something to clear it.")
                                .bokehFont(.subheadline, weight: .medium)
                        }
                        Text("We'll isolate it so you can put it away.")
                            .bokehFont(.subheadline, weight: .regular)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .scaleEffect(instructionPulse)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(1.5)) {
                            instructionPulse = 1.02
                        }
                    }
                    .padding(.bottom, 24)
                }

            case .processing:
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text(lifter.debugMode ? "Running Vision diagnostics…" : "Isolating…")
                        .bokehFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .padding(AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppLayoutConstants.cardCornerRadius(horizontalSizeClass: horizontalSizeClass)))

            case .focused(let cutout, let label):
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            Text(String(format: "%02d:%02d", timeElapsed / 60, timeElapsed % 60))
                                .font(.system(size: 54, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(.top, 32)
                                .accessibilityLabel("Timer: \(timeElapsed / 60) minutes \(timeElapsed % 60) seconds")

                            Text("Put it away or clear it,\nthen mark as done.")
                                .bokehFont(.body, weight: .semibold)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 24)

                            Image(uiImage: cutout)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geo.size.width * 0.65, maxHeight: geo.size.height * 0.35)
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                                .offset(y: floatOffset)
                                .onAppear {
                                    guard !reduceMotion else { return }
                                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                                        floatOffset = -6
                                    }
                                }
                                .accessibilityLabel(label.map { "\($0), object to clear" } ?? "Object to clear")

                            TextField("What is this?", text: $editedLabel)
                                .bokehFont(.body, weight: .medium)
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .focused($isLabelFieldFocused)
                                .onSubmit { isLabelFieldFocused = false }
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.theme.bokehTeal.opacity(isLabelFieldFocused ? 0.7 : 0.4), lineWidth: isLabelFieldFocused ? 2 : 1.5)
                                )
                                .padding(.horizontal, horizontalSizeClass == .regular ? 48 : 32)
                                .accessibilityLabel("Item name")
                                .accessibilityHint("Name what you are clearing")

                            VStack(spacing: 14) {
                                Button(action: {
                                    let duration = TimeInterval(timeElapsed)
                                    let finalLabel = editedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    onDone(cutout, finalLabel.isEmpty ? label : finalLabel, duration)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Mark as Done")
                                            .bokehFont(.headline, weight: .bold)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: AppLayoutConstants.minTouchTarget)
                                    .background(Self.teal, in: Capsule())
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .padding(.horizontal, horizontalSizeClass == .regular ? 48 : 32)
                                .accessibilityLabel("Mark as Done")
                                .accessibilityHint("Marks this item as cleared and opens the save screen")

                                Button(action: { lifter.reset() }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Retake")
                                    }
                                    .bokehFont(.subheadline, weight: .semibold)
                                    .foregroundStyle(.primary)
                                    .frame(minHeight: AppLayoutConstants.minTouchTarget)
                                    .padding(.horizontal, 24)
                                    .background(.ultraThinMaterial, in: Capsule())
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .accessibilityLabel("Retake")
                                .accessibilityHint("Go back and pick something else")
                            }
                            .padding(.bottom, 40)
                        }
                        .frame(minHeight: geo.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }

            #if DEBUG
            case .debug(let info):
                VisionDebugView(
                    info: info,
                    onClose: { lifter.reset() },
                    onRetryWithOrientation: { orientation in
                        lifter.retryWithOrientation(orientation)
                    }
                )
                .transition(.opacity)
            #endif

            case .error(let msg):
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    Text(msg)
                        .bokehFont(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button(action: { lifter.reset() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry").bokehFont(.body, weight: .semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(minHeight: AppLayoutConstants.minTouchTarget)
                        .padding(.horizontal, 24)
                        .background(Self.teal, in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppLayoutConstants.cardCornerRadius(horizontalSizeClass: horizontalSizeClass)))
            }

            #if DEBUG
            // Debug mode indicator
            if lifter.debugMode && lifter.result != .processing {
                VStack {
                    HStack {
                        Spacer()
                        Text("🔬 DEBUG")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                    Spacer()
                }
            }
            #endif
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelForState)
        .accessibilityHint(lifter.result == .idle ? "Double tap to select something to clear" : "")
        .accessibilityAddTraits(lifter.result == .idle ? .isButton : [])
        .accessibilityAction {
            captureAndLift()
        }
        .onTapGesture {
            captureAndLift()
        }
        #if DEBUG
        .onLongPressGesture(minimumDuration: 0.8) {
            guard case .idle = lifter.result else { return }
            lifter.debugMode.toggle()
            showDebugIndicator = true
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showDebugIndicator = false
            }
        }
        #endif
        .onChange(of: lifter.result) { _, newValue in
            switch newValue {
            case .focused(_, let label):
                timeElapsed = 0
                floatOffset = 0
                isFocused = true
                editedLabel = ""
                let objectName = label ?? "Object"
                UIAccessibility.post(notification: .announcement, argument: "\(objectName) isolated. Timer started.")
            case .idle, .processing, .error:
                isFocused = false
            #if DEBUG
            case .debug:
                isFocused = false
            #endif
            }
        }
        .onReceive(timer) { _ in
            if case .focused = lifter.result {
                timeElapsed += 1
            }
        }
        .onAppear {
            SubjectLifter.prewarmVisionModel()
            updateVideoOrientation()
            if case .focused = lifter.result {
                lifter.reset()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateVideoOrientation()
        }
    }

    private var accessibilityLabelForState: String {
        switch lifter.result {
        case .idle:
            return "Camera view. Tap something to clear it."
        case .processing:
            return "Isolating what you tapped."
        case .focused(_, let label):
            return "Object isolated: \(label ?? "unknown"). Timer running."
        #if DEBUG
        case .debug:
            return "Debug view"
        #endif
        case .error(let msg):
            return "Error: \(msg)"
        }
    }

    private func captureAndLift() {
        guard case .idle = lifter.result else { return }
        manager.setCaptureFrameCallback { frame in
            guard let frame else {
                lifter.result = .error("Could not capture frame.")
                return
            }
            lifter.lift(from: frame)
        }
    }

    private func updateVideoOrientation() {
        let angle: CGFloat
        switch UIDevice.current.orientation {
        case .portrait: angle = 90
        case .portraitUpsideDown: angle = 270
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        default:
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                return
            }
            switch scene.interfaceOrientation {
            case .portrait: angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeLeft: angle = 0
            case .landscapeRight: angle = 180
            default: return
            }
        }
        if angle != videoRotationAngle {
            videoRotationAngle = angle
        }
        manager.setVideoRotationAngle(angle)
    }
}

