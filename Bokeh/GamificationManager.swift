import SwiftUI
import Observation

struct ClearReward {
    let xpEarned: Int
    let isMilestone: Bool
    let milestoneLabel: String?
    let newStreak: Int
    let dailyCount: Int
    let comboCount: Int
    let comboMessage: String?
}

@Observable
@MainActor
final class GamificationManager {
    var totalXP: Int {
        didSet { UserDefaults.standard.set(totalXP, forKey: "bokeh.totalXP") }
    }
    var totalClears: Int {
        didSet { UserDefaults.standard.set(totalClears, forKey: "bokeh.totalClears") }
    }
    var currentStreak: Int {
        didSet { UserDefaults.standard.set(currentStreak, forKey: "bokeh.currentStreak") }
    }
    var longestStreak: Int {
        didSet { UserDefaults.standard.set(longestStreak, forKey: "bokeh.longestStreak") }
    }
    var lastActiveDate: String {
        didSet { UserDefaults.standard.set(lastActiveDate, forKey: "bokeh.lastActiveDate") }
    }
    var dailyClearCount: Int {
        didSet { UserDefaults.standard.set(dailyClearCount, forKey: "bokeh.dailyClearCount") }
    }
    var lastClearDateString: String {
        didSet { UserDefaults.standard.set(lastClearDateString, forKey: "bokeh.lastClearDate") }
    }
    var lastClearTimestamp: Date? {
        didSet {
            if let date = lastClearTimestamp {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "bokeh.lastClearTimestamp")
            }
        }
    }
    var sessionCombo: Int = 0

    private static let comboWindow: TimeInterval = 300
    private static let milestones: [Int: String] = [
        5: "First Five!",
        10: "Double Digits!",
        25: "Quarter Century!",
        50: "Half Century!",
        100: "Century Club!"
    ]

    init() {
        let defaults = UserDefaults.standard
        self.totalXP = defaults.integer(forKey: "bokeh.totalXP")
        self.totalClears = defaults.integer(forKey: "bokeh.totalClears")
        self.currentStreak = defaults.integer(forKey: "bokeh.currentStreak")
        self.longestStreak = defaults.integer(forKey: "bokeh.longestStreak")
        self.lastActiveDate = defaults.string(forKey: "bokeh.lastActiveDate") ?? ""
        self.dailyClearCount = defaults.integer(forKey: "bokeh.dailyClearCount")
        self.lastClearDateString = defaults.string(forKey: "bokeh.lastClearDate") ?? ""
        let ts = defaults.double(forKey: "bokeh.lastClearTimestamp")
        self.lastClearTimestamp = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func recordClear(duration: TimeInterval) -> ClearReward {
        let today = formatDate(Date())

        if lastClearDateString == today {
            dailyClearCount += 1
        } else {
            dailyClearCount = 1
            lastClearDateString = today
        }

        updateStreak(today: today)

        if let last = lastClearTimestamp, Date().timeIntervalSince(last) < Self.comboWindow {
            sessionCombo += 1
        } else {
            sessionCombo = 1
        }
        lastClearTimestamp = Date()

        var xp = 10
        if duration > 0 && duration < 30 {
            xp += 5
        }
        if currentStreak >= 2 {
            xp += 5
        }

        totalXP += xp
        totalClears += 1

        let milestone = Self.milestones[totalClears] ?? (totalClears > 100 && totalClears % 50 == 0 ? "\(totalClears) Cleared!" : nil)

        let comboMessage: String? = switch sessionCombo {
        case 2: "Keep going!"
        case 3: "On a roll!"
        case 4: "Unstoppable!"
        case 5...: "Legendary focus!"
        default: nil
        }

        return ClearReward(
            xpEarned: xp,
            isMilestone: milestone != nil,
            milestoneLabel: milestone,
            newStreak: currentStreak,
            dailyCount: dailyClearCount,
            comboCount: sessionCombo,
            comboMessage: comboMessage
        )
    }

    private func updateStreak(today: String) {
        if lastActiveDate.isEmpty {
            currentStreak = 1
        } else if lastActiveDate == today {
            // Same day, no change
        } else if isYesterday(lastActiveDate, relativeTo: today) {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        lastActiveDate = today
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }
    }

    private func isYesterday(_ dateString: String, relativeTo today: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString),
              let todayDate = formatter.date(from: today) else { return false }
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayDate)
        return calendar.isDate(date, inSameDayAs: yesterday ?? todayDate)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
