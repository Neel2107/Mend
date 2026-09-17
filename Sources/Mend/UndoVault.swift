import Foundation

/// A persistent record of a single Mend rewrite operation.
public struct RewriteRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let bundleID: String?
    public let appName: String?
    public let actionName: String
    public let originalText: String
    public let replacedText: String
    public let provider: String
    public let latencyMs: Double
    public let method: String

    public init(
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
public final class UndoVault: @unchecked Sendable {
    public static let shared = UndoVault()

    private let queue = DispatchQueue(label: "com.mend.UndoVault", qos: .utility)
    private let storageURL: URL?
    private let maxRecords: Int
    private var cachedRecords: [RewriteRecord] = []
    private var isLoaded = false

    public init(storageURL: URL? = nil, maxRecords: Int = 500) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.maxRecords = maxRecords
    }

    public static func defaultStorageURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Mend", isDirectory: true)
        return dir.appendingPathComponent("history.json")
    }

    public func record(_ entry: RewriteRecord) {
        queue.sync {
            loadIfNeeded()
            cachedRecords.insert(entry, at: 0)
            if cachedRecords.count > maxRecords {
                cachedRecords = Array(cachedRecords.prefix(maxRecords))
            }
            save()
        }
    }

    public func lastRecord() -> RewriteRecord? {
        queue.sync {
            loadIfNeeded()
            return cachedRecords.first
        }
    }

    public func allRecords() -> [RewriteRecord] {
        queue.sync {
            loadIfNeeded()
            return cachedRecords
        }
    }

    public func clear() {
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
