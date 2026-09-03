import Foundation

/// A dotted version such as `0.2.3`, with an optional leading `v`.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let parsed = digits.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
        components = parsed.compactMap { $0 }
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    /// Missing trailing components count as zero, so 0.2.3 equals 0.2.3.0.
    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

struct UpdateChecker {
    enum Outcome: Equatable {
        case upToDate(AppVersion)
        case available(version: AppVersion, url: URL)
    }

    enum CheckError: LocalizedError {
        case unreadableRelease
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .unreadableRelease:
                return "Couldn’t read the latest release"
            case .httpStatus(let status):
                return "GitHub returned HTTP \(status)"
            }
        }
    }

    var repository = "Neel2107/Mend"
    var session: URLSession = .shared

    static var currentVersion: AppVersion {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return AppVersion(bundled ?? "") ?? AppVersion("0")!
    }

    func check(currentVersion: AppVersion = UpdateChecker.currentVersion) async throws -> Outcome {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CheckError.httpStatus(http.statusCode)
        }

        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = AppVersion(release.tagName) else {
            throw CheckError.unreadableRelease
        }

        if currentVersion < latest {
            return .available(version: latest, url: release.htmlURL)
        }
        return .upToDate(currentVersion)
    }
}

private struct Release: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
