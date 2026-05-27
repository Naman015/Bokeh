import SwiftUI
import UIKit
import AVFoundation
import CoreSpotlight

// MARK: - Camera

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Rotation angle in degrees (0, 90, 180, 270).
    var rotationAngle: CGFloat = 90

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let connection = uiView.videoPreviewLayer.connection, connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

enum AppState: Equatable {
    case scanning
    case success
}

struct ContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var manager = CameraManager()
    @StateObject private var logManager = LogManager()
    @State private var gamification = GamificationManager()
    @State private var showHistorySheet = false
    @State private var showHelpSheet = false
    @AppStorage("hasSeenFocusLogTooltip") private var hasSeenFocusLogTooltip = false
    @State private var showFocusLogTooltip = false
    @State private var lastAddedLogId: UUID?
    @State private var appState: AppState = .scanning
    @State private var pendingCutout: UIImage?
    @State private var pendingLabel: String?
    @State private var pendingDuration: TimeInterval = 0
    @State private var saveToastMessage: String?
    @State private var spotlightLogId: UUID?
    @State private var isInFocusedState = false
    @State private var focusLogButtonScale: CGFloat = 0.8
    @State private var focusLogButtonOpacity: Double = 0
    @State private var showSplash = true
    @AppStorage("newFocusItemsCount") private var newFocusItemsCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            mainContent

            if showSplash {
                splashScreen
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            let delay: Double = hasSeenOnboarding ? 0.8 : 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }

    private var splashScreen: some View {
        ZStack {
            Color.theme.bokehSand
                .ignoresSafeArea()

            VStack(spacing: 16) {
                BokehLogoView(size: 96)
                Text("Bokeh")
                    .bokehFont(.title2, weight: .bold)
                    .foregroundStyle(Color.theme.bokehTitleColor)
                Text("One thing at a time.")
                    .bokehFont(.subheadline)
                    .foregroundStyle(Color.theme.bokehBodyColor)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView(hasSeenOnboarding: $hasSeenOnboarding, onGetStarted: {
                    manager.requestPermission()
                    SubjectLifter.prewarmVisionModel()
                    BokehHaptics.shared.prewarm()
                })
            } else if !manager.permissionGranted {
                cameraDeniedFullScreen
            } else {
                switch appState {
                case .scanning:
                    MagicFocusView(manager: manager, gamification: gamification, isFocused: $isInFocusedState) { image, label, duration in
                        if let image {
                            pendingCutout = image
                            pendingLabel = label
                            pendingDuration = duration
                        }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            appState = .success
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .onAppear { applyVideoOrientation() }
                    .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in applyVideoOrientation() }
                    .overlay(alignment: .top) {
                        if !isInFocusedState {
                            HStack {
                                Button(action: { showHelpSheet = true }) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .frame(width: 44, height: 44)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .accessibilityLabel("How to use Bokeh")
                                .accessibilityHint("Opens a guide on how to use Bokeh")

                                if gamification.currentStreak > 0 {
                                    HStack(spacing: 6) {
                                        Image(systemName: "flame.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.theme.bokehAmber)
                                        Text("\(gamification.currentStreak) day streak")
                                            .bokehFont(.caption, weight: .semibold)
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                }

                                Spacer()

                                Button(action: {
                                    newFocusItemsCount = 0
                                    showFocusLogTooltip = false
                                    showHistorySheet = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "book.closed.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Focus Log")
                                            .bokehFont(.subheadline, weight: .semibold)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .background(Color.theme.bokehTeal, in: Capsule())
                                    .bokehShadow(.floating)
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .overlay(alignment: .topTrailing) {
                                    if newFocusItemsCount > 0 {
                                        Text("\(min(newFocusItemsCount, 99))")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .padding(5)
                                            .background(Color.theme.bokehAmber, in: Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if showFocusLogTooltip {
                                        Text("Your cleared items live here")
                                            .bokehFont(.caption, weight: .semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                                            .offset(y: 44)
                                            .onTapGesture {
                                                withAnimation { showFocusLogTooltip = false }
                                                hasSeenFocusLogTooltip = true
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                    }
                                }
                                .scaleEffect(focusLogButtonScale)
                                .opacity(focusLogButtonOpacity)
                                .accessibilityLabel("Focus Log")
                                .accessibilityHint(newFocusItemsCount > 0 ? "\(newFocusItemsCount) new items" : "View your cleared items journal")
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 60)
                            .onAppear {
                                if reduceMotion {
                                    focusLogButtonScale = 1
                                    focusLogButtonOpacity = 1
                                } else {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3)) {
                                        focusLogButtonScale = 1.0
                                        focusLogButtonOpacity = 1.0
                                    }
                                }
                                if !hasSeenFocusLogTooltip {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        withAnimation(.easeOut(duration: 0.3)) { showFocusLogTooltip = true }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                                        withAnimation(.easeOut(duration: 0.3)) { showFocusLogTooltip = false }
                                        hasSeenFocusLogTooltip = true
                                    }
                                }
                            }
                        }
                    }

                case .success:
                    if let cutout = pendingCutout {
                        SuccessView(
                            cutout: cutout,
                            label: pendingLabel,
                            duration: pendingDuration,
                            gamification: gamification,
                            onSaveToLocation: { finalLabel, location in
                                let log = logManager.add(cutoutImage: cutout, label: finalLabel, location: location, duration: pendingDuration)
                                lastAddedLogId = log.id
                                newFocusItemsCount += 1
                                pendingCutout = nil
                                pendingLabel = nil
                                pendingDuration = 0
                                isInFocusedState = false
                                withAnimation(.easeInOut(duration: 0.35)) { appState = .scanning }
                                showSaveToast(location != nil ? "Saved to Focus Log – \(location!)" : "Saved to Focus Log")
                            },
                            onCancel: {
                                pendingCutout = nil
                                pendingLabel = nil
                                pendingDuration = 0
                                isInFocusedState = false
                                withAnimation(.easeInOut(duration: 0.35)) { appState = .scanning }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        Color.black.ignoresSafeArea()
                            .onAppear { appState = .scanning }
                    }
                }
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            FocusLogView(logManager: logManager, lastAddedId: lastAddedLogId, openLogId: spotlightLogId, onClearOpenLogId: { spotlightLogId = nil })
                .onDisappear {
                    lastAddedLogId = nil
                    newFocusItemsCount = 0
                }
        }
        .sheet(isPresented: $showHelpSheet) {
            HelpGuideView()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let id = UUID(uuidString: idString) {
                spotlightLogId = id
                showHistorySheet = true
                hasSeenOnboarding = true
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.permissionGranted)
        .animation(.easeInOut(duration: 0.3), value: hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.35), value: appState)
        .overlay(alignment: .top) {
            if let message = saveToastMessage {
                VStack {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .padding(.top, 40)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }


    /// Full-screen view when user has completed onboarding but camera access was denied.
    private var cameraDeniedFullScreen: some View {
        ZStack {
            Color(red: 0.97, green: 0.95, blue: 0.93)
                .ignoresSafeArea()
            cameraDeniedOverlay
        }
    }

    private var cameraDeniedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.theme.bokehTeal.opacity(0.8))
            Text("Camera access was denied.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.theme.bokehTitleColor)
                .multilineTextAlignment(.center)
            Text("You can enable it in Settings → Bokeh → Camera.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color.theme.bokehBodyColor)
                .multilineTextAlignment(.center)
            Button("Retry") {
                manager.requestPermission()
            }
            .buttonStyle(ScaleButtonStyle())
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.theme.bokehTeal, in: Capsule())
            .padding(.top, 8)
            .accessibilityLabel("Retry")
            .accessibilityHint("Opens settings to grant camera access")
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        .padding(.horizontal, 32)
    }

    private func applyVideoOrientation() {
        let angle: CGFloat
        switch UIDevice.current.orientation {
        case .portrait: angle = 90
        case .portraitUpsideDown: angle = 270
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        default: angle = 90
        }
        manager.setVideoRotationAngle(angle)
    }

    private func showSaveToast(_ message: String) {
        saveToastMessage = message
        let current = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if saveToastMessage == current {
                withAnimation(.easeOut(duration: 0.25)) {
                    saveToastMessage = nil
                }
            }
        }
    }
}
