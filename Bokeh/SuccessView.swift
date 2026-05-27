import SwiftUI
import UIKit

// MARK: - Success View

struct SuccessView: View {
    let cutout: UIImage
    let label: String?
    let duration: TimeInterval
    var gamification: GamificationManager
    var onSaveToLocation: (String, String?) -> Void
    var onCancel: () -> Void

    private static let recentLocationsKey = "bokeh.recentLocations"
    private static let removedLocationTagsKey = "bokeh.removedLocationTags"

    @State private var editableLabel: String = ""
    @State private var recentLocations: [String] = []
    @State private var removedLocationTags: Set<String> = []
    @State private var showCustomLocationSheet = false
    @State private var customLocationText = ""
    @State private var showLocationSection = false
    @State private var selectedLocation: String? = nil
    @State private var medallionScale: CGFloat = 0
    @State private var ringProgress: CGFloat = 0
    @State private var glowScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.95
    @State private var locationSectionOpacity: Double = 0
    @State private var locationSectionOffset: CGFloat = 40
    @State private var savingToFocusLog = false
    @State private var focusLogIconScale: CGFloat = 1
    @State private var clearReward: ClearReward?
    @State private var showConfetti = false
    @State private var confettiStart = Date()
    @State private var xpOpacity: Double = 0
    @State private var cardRotation: Double = 2
    @State private var cardOffset: CGFloat = 20
    @FocusState private var isLabelFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            gradientBackground

            if showConfetti {
                ConfettiView(startTime: confettiStart, duration: 2.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .bokehFont(.body, weight: .semibold)
                            .foregroundStyle(.primary)
                            .frame(width: AppLayoutConstants.minTouchTarget, height: AppLayoutConstants.minTouchTarget)
                            .contentShape(Rectangle())
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Discards and returns to camera")
                    Spacer()
                }
                .padding(.horizontal, AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass))
                .padding(.top, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        GeometryReader { geo in
                            let medallionSize = min(120, geo.size.width * 0.35)
                            ZStack {
                                Circle()
                                    .fill(Color.theme.bokehTeal.opacity(glowOpacity))
                                    .frame(width: medallionSize * 1.15, height: medallionSize * 1.15)
                                    .scaleEffect(glowScale)

                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: medallionSize, height: medallionSize)
                                Image(uiImage: cutout)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: medallionSize, height: medallionSize)
                                    .clipShape(Circle())

                                Circle()
                                    .trim(from: 0, to: ringProgress)
                                    .stroke(
                                        Color.theme.bokehTeal,
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                    )
                                    .frame(width: medallionSize, height: medallionSize)
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(medallionScale)
                            .opacity(medallionScale)
                            .accessibilityLabel("Cleared item: \(label ?? "item")")
                        }
                        .frame(height: 140)

                    Text("You cleared it!")
                        .bokehFont(.title2, weight: .bold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .scaleEffect(titleScale)
                        .opacity(titleOpacity)

                    // Timer pill
                    HStack(spacing: 6) {
                        Image(systemName: "stopwatch")
                            .bokehFont(.caption, weight: .semibold)
                        Text(clearedInText)
                            .bokehFont(.subheadline, weight: .semibold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .opacity(titleOpacity)

                    if let reward = clearReward {
                        if let comboMsg = reward.comboMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption.weight(.bold))
                                Text(comboMsg)
                                    .bokehFont(.subheadline, weight: .bold)
                            }
                            .foregroundStyle(Color.theme.bokehTeal)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.theme.bokehTealSubtle, in: Capsule())
                            .opacity(xpOpacity)
                        }

                        if reward.dailyCount > 1 {
                            Text("\(ordinal(reward.dailyCount)) item today")
                                .bokehFont(.caption, weight: .semibold)
                                .foregroundStyle(Color.theme.bokehTitleColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.theme.bokehAmberSoft, in: Capsule())
                                .opacity(xpOpacity)
                        }

                        if let milestone = reward.milestoneLabel {
                            Text(milestone)
                                .bokehFont(.headline, weight: .bold)
                                .foregroundStyle(Color.theme.bokehTeal)
                                .opacity(xpOpacity)
                                .accessibilityLabel("Milestone: \(milestone)")
                        }
                    }

                    // Editable name — caption + prominent text field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you clear?")
                            .bokehFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.primary)
                        HStack(spacing: 10) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.theme.bokehTeal)
                            TextField("e.g. Keys, mug, book", text: $editableLabel)
                                .bokehFont(.body)
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .focused($isLabelFocused)
                                .onSubmit { isLabelFocused = false }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.theme.bokehTeal.opacity(isLabelFocused ? 0.7 : 0.4), lineWidth: isLabelFocused ? 2 : 1.5)
                                )
                        }
                    }
                    .padding(.horizontal, 8)
                    .opacity(titleOpacity)
                    .onTapGesture { isLabelFocused = true }
                    .accessibilityHint("Tap to edit the name")

                    if showLocationSection {
                        VStack(alignment: .leading, spacing: 14) {
                            Divider()
                                .background(.secondary.opacity(0.5))
                                .padding(.vertical, 4)

                            Text("Save to Focus Log")
                                .bokehFont(.subheadline, weight: .bold)
                                .foregroundStyle(.primary)
                            Text("Where did you put it? (optional)")
                                .bokehFont(.caption)
                                .foregroundStyle(Color.theme.bokehCaption)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    Button(action: { showCustomLocationSheet = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus")
                                                .bokehFont(.caption, weight: .bold)
                                            Text("Custom")
                                                .bokehFont(.subheadline, weight: .semibold)
                                        }
                                        .foregroundStyle(Color.theme.bokehTeal)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .frame(minHeight: AppLayoutConstants.minTouchTarget)
                                        .overlay(Capsule().strokeBorder(Color.theme.bokehTeal, lineWidth: 1.5))
                                    }
                                    .buttonStyle(ScaleButtonStyle(minScale: 0.97))
                                    .accessibilityLabel("Custom location")
                                    .accessibilityHint("Enter a custom location")
                                    ForEach(displayLocations, id: \.self) { option in
                                        Button(action: {
                                            if selectedLocation == option {
                                                selectedLocation = nil
                                            } else {
                                                selectedLocation = option
                                            }
                                        }) {
                                            Text(option)
                                                .bokehFont(.subheadline, weight: .semibold)
                                                .foregroundStyle(selectedLocation == option ? .white : Color.theme.bokehTeal)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .frame(minHeight: AppLayoutConstants.minTouchTarget)
                                                .background(selectedLocation == option ? Color.theme.bokehTeal : Color.clear, in: Capsule())
                                                .overlay(Capsule().strokeBorder(Color.theme.bokehTeal, lineWidth: selectedLocation == option ? 0 : 1.5))
                                        }
                                        .buttonStyle(ScaleButtonStyle(minScale: 0.97))
                                        .contextMenu {
                                            Button(role: .destructive, action: { removeLocationTag(option) }) {
                                                Label("Remove from suggestions", systemImage: "trash")
                                            }
                                        }
                                        .accessibilityLabel(option)
                                        .accessibilityHint(selectedLocation == option ? "Tap to unselect. Hold for more options." : "Tap to select. Hold for more options.")
                                        .accessibilityAddTraits(selectedLocation == option ? .isSelected : [])
                                    }
                                    Button(action: { selectedLocation = nil }) {
                                        Text("No location")
                                            .bokehFont(.subheadline, weight: .semibold)
                                            .foregroundStyle(selectedLocation == nil ? .white : Color.theme.bokehBodyColor)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .frame(minHeight: AppLayoutConstants.minTouchTarget)
                                            .background(selectedLocation == nil ? Color.theme.bokehTeal.opacity(0.6) : Color.clear, in: Capsule())
                                    }
                                    .buttonStyle(ScaleButtonStyle(minScale: 0.97))
                                    .accessibilityLabel("No location")
                                    .accessibilityHint("Unselect and save without a location")
                                }
                            }

                            Button(action: {
                                guard !savingToFocusLog else { return }
                                savingToFocusLog = true
                                BokehHaptics.shared.play(.save)
                                if reduceMotion {
                                    saveAndDismiss(location: selectedLocation)
                                    return
                                }
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
                                    focusLogIconScale = 1.35
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                                        focusLogIconScale = 1.0
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                                    saveAndDismiss(location: selectedLocation)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "book.closed.fill")
                                        .bokehFont(.headline)
                                        .scaleEffect(focusLogIconScale)
                                    Text(savingToFocusLog ? "Saved!" : "Save to Focus Log")
                                        .bokehFont(.headline)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                                .background(Color.theme.bokehTeal, in: Capsule())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(savingToFocusLog)
                            .padding(.top, 6)
.accessibilityLabel(savingToFocusLog ? "Saved to Focus Log" : "Save to Focus Log")
.accessibilityHint("Saves this item to your Focus Log and returns to the camera")
                        }
                        .opacity(locationSectionOpacity)
                        .offset(y: locationSectionOffset)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .bokehShadow(.lifted)
                .rotation3DEffect(.degrees(cardRotation), axis: (x: 1, y: 0, z: 0))
                .offset(y: cardOffset)
                .padding(.horizontal, 20)

                Spacer(minLength: verticalSizeClass == .compact ? 16 : 32)
                }
                .containerRelativeFrame(.horizontal) { length, _ in
                    horizontalSizeClass == .regular ? min(length * 0.8, 720) : length * 0.92
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if editableLabel.isEmpty {
                editableLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            let reward = gamification.recordClear(duration: duration)
            clearReward = reward
            triggerFeedback()
            if let stored = UserDefaults.standard.stringArray(forKey: Self.recentLocationsKey) {
                recentLocations = stored
            }
            if let stored = UserDefaults.standard.stringArray(forKey: Self.removedLocationTagsKey) {
                removedLocationTags = Set(stored)
            }
            if !reduceMotion {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                    cardRotation = 0
                    cardOffset = 0
                }
                // 0.1s: Medallion springs in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                    medallionScale = 1.0
                }
                // 0.1-0.6s: Ring draws on
                withAnimation(.easeInOut(duration: 0.5).delay(0.1)) {
                    ringProgress = 1.0
                }
                // 0.5s: Title fades in with scale
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        titleOpacity = 1.0
                        titleScale = 1.0
                    }
                    // Glow pulse at ring completion
                    withAnimation(.easeOut(duration: 0.5)) {
                        glowOpacity = 0.3
                        glowScale = 1.12
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            glowOpacity = 0
                            glowScale = 1.0
                        }
                    }
                }
                // 0.7s: XP pill fades in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        xpOpacity = 1.0
                    }
                    if reward.isMilestone || reward.comboCount >= 3 {
                        confettiStart = Date()
                        showConfetti = true
                        BokehHaptics.shared.play(reward.comboCount >= 4 ? .combo : .milestone)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            showConfetti = false
                        }
                    }
                }
                // 1.0s: Location section slides in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showLocationSection = true
                        locationSectionOpacity = 1.0
                        locationSectionOffset = 0
                    }
                }
            } else {
                cardRotation = 0
                cardOffset = 0
                medallionScale = 1.0
                ringProgress = 1.0
                titleOpacity = 1.0
                titleScale = 1.0
                xpOpacity = 1.0
                showLocationSection = true
                locationSectionOpacity = 1.0
                locationSectionOffset = 0
                if reward.isMilestone || reward.comboCount >= 3 {
                    confettiStart = Date()
                    showConfetti = true
                    BokehHaptics.shared.play(reward.comboCount >= 4 ? .combo : .milestone)
                }
            }
        }
        .sheet(isPresented: $showCustomLocationSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("e.g. Closet", text: $customLocationText)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    } header: { Text("Location name") }
                }
                .navigationTitle("Add location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomLocationSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let trimmed = customLocationText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                selectedLocation = trimmed
                                updateRecents(with: trimmed)
                                customLocationText = ""
                                showCustomLocationSheet = false
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(customLocationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [Color.theme.bokehTeal.opacity(0.5), Color.theme.bokehSand],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var displayLocations: [String] {
        var seen = Set<String>()
        let merged = recentLocations + AppLayoutConstants.defaultLocationTags
        return merged.filter { !removedLocationTags.contains($0) && seen.insert($0).inserted }
    }

    private var clearedInText: String {
        if duration < 60 {
            let s = Int(round(duration))
            return s <= 1 ? "Cleared in 1s" : "Cleared in \(s)s"
        }
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        if s == 0 {
            return "Cleared in \(m)m"
        }
        return "Cleared in \(m)m \(s)s"
    }

    private func saveAndDismiss(location: String?) {
        let finalLabel = editableLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = finalLabel.isEmpty ? (label ?? "Cleared Item") : finalLabel
        if let loc = location, !loc.isEmpty {
            updateRecents(with: loc)
        }
        onSaveToLocation(name, location)
    }

    private func updateRecents(with location: String) {
        removedLocationTags.remove(location)
        var updated = [location] + recentLocations.filter { $0.caseInsensitiveCompare(location) != .orderedSame }
        if updated.count > 10 { updated = Array(updated.prefix(10)) }
        recentLocations = updated
        UserDefaults.standard.set(updated, forKey: Self.recentLocationsKey)
        UserDefaults.standard.set(Array(removedLocationTags), forKey: Self.removedLocationTagsKey)
    }

    private func removeLocationTag(_ tag: String) {
        if let idx = recentLocations.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            recentLocations.remove(at: idx)
            UserDefaults.standard.set(recentLocations, forKey: Self.recentLocationsKey)
        }
        removedLocationTags.insert(tag)
        UserDefaults.standard.set(Array(removedLocationTags), forKey: Self.removedLocationTagsKey)
        if selectedLocation?.caseInsensitiveCompare(tag) == .orderedSame {
            selectedLocation = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func triggerFeedback() {
        BokehHaptics.shared.play(.completion)
    }


    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Confetti (reserved for future milestone celebrations)

private struct ConfettiView: View {
    let startTime: Date
    let duration: TimeInterval
    private let particleCount = 36
    private static let teal = Color(red: 0.2, green: 0.65, blue: 0.65)
    private static let tealLight = Color(red: 0.4, green: 0.75, blue: 0.75)
    private static let sand = Color(red: 0.92, green: 0.88, blue: 0.82)
    private static let white = Color.white
    private static let palette: [Color] = [teal, tealLight, sand, white]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let phase = min(1, elapsed / duration)
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    ForEach(0..<particleCount, id: \.self) { i in
                        particleView(index: i, size: size, phase: phase)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .drawingGroup(opaque: false)
        }
    }

    /// Particles spawn from top center and fall with slight spread and rotation.
    private func particleView(index: Int, size: CGSize, phase: Double) -> some View {
        let delay = Double(index % 8) * 0.03
        let progress = phase <= delay ? 0 : min(1, (phase - delay) / (1.0 - delay))
        let easeOut = 1.0 - pow(1.0 - progress, 1.5)
        let horizontalSpread = CGFloat((index % 7) - 3) * 0.08
        let startX = size.width * (0.5 + horizontalSpread)
        let endX = startX + sin(Double(index) * 0.7) * size.width * 0.25
        let x = startX + (endX - startX) * easeOut
        let y = -20 + easeOut * (size.height + 60)
        let rotation = Double(index) * 0.9 + easeOut * .pi * 2
        let opacity = progress < 0.15 ? progress / 0.15 : max(0, 1.0 - (progress - 0.7) / 0.3)
        let color = Self.palette[index % Self.palette.count]
        let w = CGFloat(6 + (index % 5))
        let h = CGFloat(4 + (index % 3))
        return RoundedRectangle(cornerRadius: min(w, h) / 2)
            .fill(color)
            .frame(width: w, height: h)
            .rotationEffect(.radians(rotation))
            .position(x: x, y: y)
            .opacity(opacity)
    }
}
