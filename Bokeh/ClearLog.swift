import Foundation
import UIKit
import Combine

// MARK: - Cleared Item (Focus Log Entry)

/// Metadata for a single cleared item.
/// We persist only the lifted subject cutout image (PNG) under Documents/BokehHistory/.
struct ClearLog: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let filename: String        // e.g. "AB12...CD.png"
    var label: String           // e.g. "Coffee Cup"
    var duration: TimeInterval  // How long it took to clear
    var location: String?       // e.g. "Kitchen", "Drawer"
    var originalImage: Data?    // Optional in-memory sticker; not persisted in manifest

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        filename: String,
        label: String,
        duration: TimeInterval = 0,
        location: String? = nil,
        originalImage: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filename = filename
        self.label = label
        self.duration = duration
        self.location = location
        self.originalImage = originalImage
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, filename, label, duration, location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        filename = try c.decode(String.self, forKey: .filename)
        label = try c.decode(String.self, forKey: .label)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        location = try c.decodeIfPresent(String.self, forKey: .location)
        originalImage = nil
    }
}

// MARK: - Log Manager (File-System Backed)

/// Persists cutout images as PNG files and metadata as a JSON manifest under Documents/BokehHistory/.
@MainActor
final class LogManager: ObservableObject {

    @Published private(set) var logs: [ClearLog] = []
    @Published private(set) var isLoading = true

    private let fm = FileManager.default
    private var pendingAdds: [ClearLog] = []

    /// Root folder: Application Support/BokehHistory/ (persists across app restarts)
    private var historyDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("BokehHistory", isDirectory: true)
    }

    /// Legacy path for migration from older versions
    private var legacyHistoryDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("BokehHistory", isDirectory: true)
    }

    private var manifestURL: URL {
        historyDir.appendingPathComponent("manifest.json")
    }

    init() {
        Task { await performLoad() }
    }

    private func performLoad() async {
        let dir = historyDir
        let legacyDir = legacyHistoryDir
        let manifest = manifestURL

        let loaded = await Task.detached(priority: .userInitiated) { () -> [ClearLog] in
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

            let legacyManifest = legacyDir.appendingPathComponent("manifest.json")
            if fm.fileExists(atPath: legacyManifest.path), !fm.fileExists(atPath: manifest.path) {
                if let data = try? Data(contentsOf: legacyManifest),
                   let entries = try? JSONDecoder().decode([ClearLog].self, from: data) {
                    for entry in entries {
                        let src = legacyDir.appendingPathComponent(entry.filename)
                        let dst = dir.appendingPathComponent(entry.filename)
                        if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
                    }
                    try? data.write(to: manifest, options: .atomic)
                    try? fm.removeItem(at: legacyDir)
                }
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: manifest),
                  let decoded = try? decoder.decode([ClearLog].self, from: data) else {
                return []
            }
            return decoded
        }.value

        let existingIds = Set(pendingAdds.map(\.id))
        logs = pendingAdds + loaded.filter { !existingIds.contains($0.id) }
        pendingAdds = []
        isLoading = false
    }

    // MARK: - Public API

    /// Save the lifted subject cutout image to disk and record the entry. Returns the new log.
    @discardableResult
    func add(cutoutImage: UIImage, label: String, location: String?, duration: TimeInterval) -> ClearLog {
        ensureDirectory()
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let url = historyDir.appendingPathComponent(filename)

        if let data = cutoutImage.pngData() {
            try? data.write(to: url, options: .atomic)
        }

        let entry = ClearLog(id: id, filename: filename, label: label, duration: duration, location: location)
        if isLoading {
            pendingAdds.insert(entry, at: 0)
        }
        logs.insert(entry, at: 0)
        saveManifest()

        SpotlightManager.indexItem(entry, image: cutoutImage)
        return entry
    }

    func loadImage(for log: ClearLog) -> UIImage? {
        let url = historyDir.appendingPathComponent(log.filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func remove(_ log: ClearLog) {
        SpotlightManager.removeItem(log)
        let url = historyDir.appendingPathComponent(log.filename)
        try? fm.removeItem(at: url)
        logs.removeAll { $0.id == log.id }
        saveManifest()
    }

    func clearAll() {
        SpotlightManager.removeAll()
        try? fm.removeItem(at: historyDir)
        logs = []
        ensureDirectory()
        saveManifest()
    }

    /// Update label and/or location for an existing entry and re-index Spotlight.
    func update(id: UUID, label: String? = nil, location: String? = nil) {
        guard let idx = logs.firstIndex(where: { $0.id == id }) else { return }
        let existing = logs[idx]
        let updated = ClearLog(
            id: existing.id,
            timestamp: existing.timestamp,
            filename: existing.filename,
            label: label ?? existing.label,
            duration: existing.duration,
            location: location ?? existing.location,
            originalImage: existing.originalImage
        )
        logs[idx] = updated
        saveManifest()
        SpotlightManager.indexItem(updated, image: loadImage(for: updated))
    }

    // MARK: - Private

    private func ensureDirectory() {
        try? fm.createDirectory(at: historyDir, withIntermediateDirectories: true, attributes: nil)
    }

    private func saveManifest() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        guard let data = try? enc.encode(logs) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}

