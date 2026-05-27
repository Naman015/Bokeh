import SwiftUI
import UIKit

// MARK: - Paged Card Onboarding (Welcome + Story Arc)

private let noiseSymbols: [(name: String, x: CGFloat, y: CGFloat)] = [
    ("key.fill", -80, -60),
    ("doc.fill", 70, -50),
    ("trash.fill", -50, 40),
    ("cup.and.saucer.fill", 0, 0),
    ("folder.fill", 60, 30),
    ("paperclip", -70, 50),
    ("envelope.fill", 50, -70),
    ("book.closed.fill", -40, -40),
    ("pencil", 40, 60),
    ("paperplane.fill", -60, -20),
    ("tray.full.fill", 30, -60),
    ("archivebox.fill", -30, 70),
    ("tag.fill", 80, 10),
]

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    var onGetStarted: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var currentTab: Int = 0
    @State private var slide3CupLanded = false
    @State private var slide3PinOpacity: Double = 0

    // Pre-warmed haptic generator to avoid first-use latency
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .soft)

    private var isCompactHeight: Bool { verticalSizeClass == .compact }
    private var isPhone: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ZStack {
            Color.theme.bokehSand
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // MARK: - Fixed Header
                    headerSection

                    // MARK: - White Card (Stage)
                    cardSection

                    // MARK: - Smart Button (below card) — HIG: clear separation from card
                    smartButton
                        .padding(.top, isCompactHeight ? 16 : (horizontalSizeClass == .regular ? 44 : 28))

                    // MARK: - Privacy Note (always visible)
                    privacyNote
                        .padding(.top, isCompactHeight ? 12 : (horizontalSizeClass == .regular ? 24 : 16))
                        .padding(.bottom, isCompactHeight ? 16 : (horizontalSizeClass == .regular ? 40 : 24))
                }
            }
        }
        .onAppear {
            // Pre-warm haptic engine on appear for instant feedback later
            hapticGenerator.prepare()
        }
        .onChange(of: currentTab) { _, _ in
            hapticGenerator.impactOccurred()
            // Re-prepare for next use
            hapticGenerator.prepare()
        }
    }

    // MARK: - Header (HIG: semantic typography, tagline with contrast on sand)

    private var headerSection: some View {
        VStack(spacing: isCompactHeight ? 10 : 16) {
            BokehLogoView(size: isCompactHeight ? 64 : 96)

            Text("Welcome to Bokeh")
                .bokehFont(isCompactHeight ? .headline : .title2, weight: .bold)
                .foregroundStyle(Color.theme.bokehTitleColor)
                .multilineTextAlignment(.center)

            if !isCompactHeight {
                Text("A gentle way to tidy up.")
                    .bokehFont(.subheadline)
                    .foregroundStyle(Color.theme.bokehBodyColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, isCompactHeight ? 16 : (horizontalSizeClass == .regular ? 48 : 40))
        .padding(.bottom, isCompactHeight ? 12 : (horizontalSizeClass == .regular ? 32 : 24))
        .padding(.horizontal, AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass))
    }

    // MARK: - Card with TabView (iPad: full-width card with internal padding per HIG)

    private var cardSection: some View {
        let cardHeight: CGFloat = isCompactHeight ? 200 : (horizontalSizeClass == .regular ? 340 : 280)

        return VStack(spacing: 0) {
            TabView(selection: $currentTab) {
                tab1Problem
                    .tag(0)
                tab2Solution
                    .tag(1)
                tab3Promise
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .animation(.easeInOut(duration: 0.35), value: currentTab)
            .frame(height: cardHeight)

            // Custom page dots below the content, inside the card
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == currentTab ? Color.theme.bokehTeal : Color.theme.bokehBodyColor.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentTab ? 1.15 : 1)
                        .animation(.easeInOut(duration: 0.2), value: currentTab)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)
        .padding(.top, horizontalSizeClass == .regular ? 32 : 20)
        .padding(.bottom, horizontalSizeClass == .regular ? 24 : 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: AppLayoutConstants.cardCornerRadius(horizontalSizeClass: horizontalSizeClass)))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass))
        .padding(.bottom, horizontalSizeClass == .regular ? 16 : 12)
    }

    // Tab 1: The Problem (HIG: .body for body copy)
    private var tab1Problem: some View {
        VStack(spacing: isCompactHeight ? 10 : 14) {
            noiseCloudView(jitter: true, blur: false, heroIndex: nil)
                .frame(height: isCompactHeight ? 80 : (isPhone ? 100 : 130))

            Text("Feeling overwhelmed?\nBokeh helps you clear one thing at a time.")
                .bokehFont(isCompactHeight ? .subheadline : .body, weight: .medium)
                .foregroundStyle(Color.theme.bokehBodyColor)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, isPhone ? 12 : 20)
        }
        .padding(.top, isCompactHeight ? 8 : 12)
        .padding(.bottom, 6)
    }

    // Tab 2: The Solution
    private var tab2Solution: some View {
        VStack(spacing: isCompactHeight ? 12 : 16) {
            noiseCloudView(jitter: false, blur: true, heroIndex: 3)
                .frame(height: isCompactHeight ? 90 : (isPhone ? 110 : 140))

            Text("Tap something to clear it.\nWe isolate it so you can put it away.")
                .bokehFont(isCompactHeight ? .subheadline : .body, weight: .medium)
                .foregroundStyle(Color.theme.bokehBodyColor)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, isPhone ? 12 : 20)
        }
        .padding(.top, isCompactHeight ? 8 : 16)
        .padding(.bottom, 8)
    }

    // Tab 3: The Promise
    private var tab3Promise: some View {
        VStack(spacing: isCompactHeight ? 10 : 14) {
            slide3Visual
                .frame(height: isCompactHeight ? 80 : (isPhone ? 100 : 130))

            Text("Clear it, tag it, find it.\nYour Focus Log remembers where you put things.")
                .bokehFont(isCompactHeight ? .subheadline : .body, weight: .medium)
                .foregroundStyle(Color.theme.bokehBodyColor)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, isPhone ? 12 : 20)

            if !isCompactHeight {
                Label("100% on-device. Private by design.", systemImage: "lock.shield.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green.opacity(0.9))
                    .padding(.top, 6)
            }
        }
        .padding(.top, isCompactHeight ? 8 : 12)
        .padding(.bottom, 6)
    }

    private var slide3Visual: some View {
        let iconSize: CGFloat = isCompactHeight ? 32 : (isPhone ? 38 : 48)
        return HStack(spacing: isCompactHeight ? 14 : 20) {
            // Cup flies in from the left
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: iconSize * 0.9))
                .foregroundStyle(Color.theme.bokehTeal)
                .offset(x: slide3CupLanded ? 0 : -80, y: 0)
                .scaleEffect(slide3CupLanded ? 1 : 1.15)

            // Focus Log icon next to the cup (saved to Focus Log)
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.theme.bokehTeal.opacity(0.9))
                .opacity(slide3PinOpacity)
        }
        .onAppear {
            slide3CupLanded = false
            slide3PinOpacity = 0
            withAnimation(.easeOut(duration: 0.65)) {
                slide3CupLanded = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) {
                slide3PinOpacity = 1
            }
        }
    }

    // MARK: - Smart Buttons (HIG: semantic .headline, 44pt min, 16pt spacing)

    private var smartButton: some View {
        HStack(spacing: 16) {
            if currentTab > 0 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentTab -= 1
                    }
                }) {
                    Text("Back")
                        .bokehFont(.headline)
                        .foregroundStyle(Color.theme.bokehTeal)
                        .frame(minWidth: 80, minHeight: AppLayoutConstants.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Back")
                .accessibilityHint("Go to previous step")
            }

            Button(action: {
                if currentTab < 2 {
                    // Instant UI update first
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentTab += 1
                    }
                } else {
                    // 1. Instant UI update — mark onboarding complete immediately
                    hasSeenOnboarding = true
                    // 2. Defer camera permission request to next run loop
                    //    so the transition animation isn't blocked
                    Task {
                        onGetStarted()
                    }
                }
            }) {
                Text(currentTab < 2 ? "Next" : "Start Camera")
                    .bokehFont(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppLayoutConstants.minTouchTarget)
                    .padding(.vertical, 16)
                    .background(Color.theme.bokehTeal, in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
.accessibilityLabel(currentTab < 2 ? "Next" : "Start Camera")
.accessibilityHint(currentTab < 2 ? "Go to next step" : "Request camera access and finish onboarding")
        }
        .padding(.horizontal, AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass))
    }

    // MARK: - Privacy Note (HIG: .caption2 or .caption, readable contrast)

    private var privacyNote: some View {
        Text("Your camera helps you focus. No images are ever recorded, saved, or sent anywhere.")
            .bokehFont(isCompactHeight ? .caption2 : .caption)
            .foregroundStyle(Color.theme.bokehBodyColor)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, horizontalSizeClass == .regular ? 48 : 24)
    }

    // MARK: - Shared noise cloud

    private func noiseCloudView(jitter: Bool, blur: Bool, heroIndex: Int?) -> some View {
        let scale: CGFloat = isCompactHeight ? 0.6 : (isPhone ? 0.75 : 1.0)
        return TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(noiseSymbols.enumerated()), id: \.offset) { index, item in
                    let isHero = heroIndex == index
                    let jitterX = jitter ? sin(t * 25 + Double(index * 2)) * 3 : 0
                    let jitterY = jitter ? cos(t * 20 + Double(index)) * 2.5 : 0
                    Image(systemName: item.name)
                        .font(.system(size: isHero ? 32 : 22))
                        .foregroundStyle(isHero ? Color.theme.bokehTeal : Color.theme.bokehBodyColor.opacity(0.7))
                        .scaleEffect(isHero ? 1.2 : 1.0)
                        .blur(radius: (blur && !isHero) ? 10 : 0)
                        .offset(x: (item.x + jitterX) * scale, y: (item.y + jitterY) * scale)
                }
            }
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
