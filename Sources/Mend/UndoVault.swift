import Foundation

/// A persistent record of a single Mend rewrite operation.
struct RewriteRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let bundleID: String?
    let appName: String?
    let actionName: String
    let originalText: String
    let replacedText: String
    let provider: String
    let latencyMs: Double
    let method: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        bundleID: String? = nil,
        appName: String? = nil,
        actionName: String,
        originalText: String,
        replacedText: String,
        provider: String,
        latencyMs: Double,
        method: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bundleID = bundleID
        self.appName = appName
        self.actionName = actionName
        self.originalText = originalText
        self.replacedText = replacedText
        self.provider = provider
        self.latencyMs = latencyMs
        self.method = method
    }
}

/// A thread-safe, persistent history vault for rewrites, enabling instant undo/rollback.
final class UndoVault: @unchecked Sendable {
    static let shared = UndoVault()

    private let queue = DispatchQueue(label: "com.mend.UndoVault", qos: .utility)
    private let storageURL: URL?
    private let maxRecords: Int
    private var cachedRecords: [RewriteRecord] = []
    private var isLoaded = false

    init(storageURL: URL? = nil, maxRecords: Int = 500) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.maxRecords = maxRecords
    }

    static func defaultStorageURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Mend", isDirectory: true)
        return dir.appendingPathComponent("history.json")
    }

    func record(_ entry: RewriteRecord) {
        queue.sync {
            loadIfNeeded()
            cachedRecords.insert(entry, at: 0)
            if cachedRecords.count > maxRecords {
                cachedRecords = Array(cachedRecords.prefix(maxRecords))
            }
            save()
        }
    }

    func lastRecord() -> RewriteRecord? {
        queue.sync {
            loadIfNeeded()
            return cachedRecords.first
        }
    }

    func allRecords() -> [RewriteRecord] {
        queue.sync {
            loadIfNeeded()
            return cachedRecords
        }
    }

    func clear() {
        queue.sync {
            cachedRecords.removeAll()
            save()
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            cachedRecords = try JSONDecoder().decode([RewriteRecord].self, from: data)
        } catch {
            cachedRecords = []
        }
    }

    private func save() {
        guard let storageURL else { return }
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cachedRecords)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Failure to save history should never crash the host app.
        }
    }
}
