import UIKit

final class BokehHaptics {
    static let shared = BokehHaptics()
    private init() {}

    enum HapticPattern {
        case completion
        case save
        case milestone
        case combo
    }

    func prewarm() {
        // Pre-warm generators for lower latency on first fire
        completionGenerator.prepare()
    }

    func play(_ pattern: HapticPattern) {
        switch pattern {
        case .completion:
            playCompletion()
        case .save:
            playSave()
        case .milestone:
            playMilestone()
        case .combo:
            playCombo()
        }
    }

    // MARK: - Generators

    private let completionGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let saveGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Patterns

    private func playCompletion() {
        // Phase 1: soft thunk
        let soft = UIImpactFeedbackGenerator(style: .soft)
        soft.impactOccurred(intensity: 0.4)

        // Phase 2: rising click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.completionGenerator.impactOccurred(intensity: 0.6)
        }

        // Phase 3: decisive confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.notificationGenerator.notificationOccurred(.success)
        }
    }

    private func playSave() {
        saveGenerator.impactOccurred(intensity: 0.7)
    }

    private func playMilestone() {
        let light = UIImpactFeedbackGenerator(style: .light)
        light.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            light.impactOccurred(intensity: 0.3)
        }
    }

    private func playCombo() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            heavy.impactOccurred(intensity: 0.6)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            self.notificationGenerator.notificationOccurred(.success)
        }
    }
}
