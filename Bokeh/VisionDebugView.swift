#if DEBUG
import SwiftUI
import Vision
import UIKit

// MARK: - Vision Debug Info

struct VisionDebugInfo: Equatable {
    let inputImage: UIImage        // Raw image fed to Vision
    let maskImage: UIImage?        // Red semi-transparent mask overlay
    let boundingBox: CGRect        // Normalized Vision bounding box (bottom-left origin)
    let inputSize: CGSize          // Width × Height of input
    let instanceCount: Int         // Number of detected foreground instances
    let confidence: Float?         // Top classification confidence
    let orientationUsed: String    // EXIF orientation label string
    let classLabel: String?        // Top classification label
}

// MARK: - Vision Debug View

struct VisionDebugView: View {
    let info: VisionDebugInfo
    var onClose: () -> Void
    var onRetryWithOrientation: ((CGImagePropertyOrientation) -> Void)? = nil

    private static let teal = Color(red: 0.2, green: 0.65, blue: 0.65)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onClose) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                            Text("Close Debug")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("🔬 VISION DEBUG")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Three-layer visualization
                GeometryReader { geo in
                    let viewSize = geo.size

                    ZStack {
                        // Layer 1: Raw input image
                        Image(uiImage: info.inputImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: viewSize.width, maxHeight: viewSize.height)

                        // Layer 2: Red mask overlay
                        if let maskImg = info.maskImage {
                            Image(uiImage: maskImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: viewSize.width, maxHeight: viewSize.height)
                                .blendMode(.normal)
                        }

                        // Layer 3: Yellow bounding box
                        if info.boundingBox != .zero {
                            let imageSize = info.inputSize
                            let fittedRect = Self.fittedImageRect(
                                imageSize: imageSize,
                                viewSize: viewSize
                            )
                            let visionRect = VNImageRectForNormalizedRect(
                                info.boundingBox,
                                Int(imageSize.width),
                                Int(imageSize.height)
                            )
                            // Convert Vision coords (bottom-left origin) to SwiftUI (top-left origin)
                            let swiftUIRect = CGRect(
                                x: fittedRect.origin.x + (visionRect.origin.x / imageSize.width) * fittedRect.width,
                                y: fittedRect.origin.y + ((imageSize.height - visionRect.origin.y - visionRect.height) / imageSize.height) * fittedRect.height,
                                width: (visionRect.width / imageSize.width) * fittedRect.width,
                                height: (visionRect.height / imageSize.height) * fittedRect.height
                            )

                            Rectangle()
                                .stroke(Color.yellow, lineWidth: 2.5)
                                .frame(width: swiftUIRect.width, height: swiftUIRect.height)
                                .position(
                                    x: swiftUIRect.midX,
                                    y: swiftUIRect.midY
                                )

                            // Label tag at top-left of bounding box
                            if let label = info.classLabel {
                                Text(label)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
                                    .position(
                                        x: swiftUIRect.minX + 40,
                                        y: swiftUIRect.minY - 10
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Layer labels legend
                HStack(spacing: 16) {
                    legendDot(color: .white.opacity(0.7), label: "Input")
                    legendDot(color: .red.opacity(0.7), label: "Mask")
                    legendDot(color: .yellow, label: "BBox")
                }
                .padding(.vertical, 6)

                // Console log panel
                consolePanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                // Orientation test buttons
                if let onRetry = onRetryWithOrientation {
                    orientationButtons(onRetry: onRetry)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Console Panel

    private var consolePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "terminal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                Text("Console")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                Spacer()
            }

            Divider().background(Color.green.opacity(0.3))

            consoleLine("Input Image Size", value: "\(Int(info.inputSize.width)) × \(Int(info.inputSize.height))")
            consoleLine("Detected Instances", value: "\(info.instanceCount)")
            consoleLine("Confidence Score", value: info.confidence.map { String(format: "%.4f", $0) } ?? "N/A")
            consoleLine("Orientation Used", value: info.orientationUsed)
            consoleLine("Classification", value: info.classLabel ?? "None")

            if info.boundingBox != .zero {
                let bb = info.boundingBox
                consoleLine("Bounding Box", value: String(format: "(%.2f, %.2f, %.2f, %.2f)", bb.origin.x, bb.origin.y, bb.width, bb.height))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func consoleLine(_ key: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("▸")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.green.opacity(0.6))
            Text(key + ":")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.green.opacity(0.7))
            Text(value)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(.green)
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Orientation Test Buttons

    private func orientationButtons(onRetry: @escaping (CGImagePropertyOrientation) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test Orientations:")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orientationOptions, id: \.0) { name, orient in
                        Button(action: { onRetry(orient) }) {
                            Text(name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .overlay(Capsule().stroke(Color.orange, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var orientationOptions: [(String, CGImagePropertyOrientation)] {
        [
            (".up", .up),
            (".right", .right),
            (".down", .down),
            (".left", .left),
            (".upMirrored", .upMirrored),
            (".rightMirrored", .rightMirrored),
        ]
    }

    // MARK: - Geometry Helpers

    /// Calculates the rect of an aspect-fit image within the given view size.
    private static func fittedImageRect(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let fitW = imageSize.width * scale
        let fitH = imageSize.height * scale
        return CGRect(
            x: (viewSize.width - fitW) / 2,
            y: (viewSize.height - fitH) / 2,
            width: fitW,
            height: fitH
        )
    }
}
#endif
