import Foundation

/// A segment of difference between original and modified text.
enum DiffChunk: Equatable {
    case equal(String)
    case insert(String)
    case delete(String)

    var text: String {
        switch self {
        case .equal(let s), .insert(let s), .delete(let s):
            return s
        }
    }
}

/// The outcome of computing differences between two text revisions.
struct DiffResult: Equatable {
    let chunks: [DiffChunk]
    let additionsCount: Int
    let deletionsCount: Int

    init(chunks: [DiffChunk], additionsCount: Int, deletionsCount: Int) {
        self.chunks = chunks
        self.additionsCount = additionsCount
        self.deletionsCount = deletionsCount
    }

    var hasChanges: Bool {
        additionsCount > 0 || deletionsCount > 0
    }

    var summary: String {
        if !hasChanges {
            return "No changes"
        }
        var parts: [String] = []
        if additionsCount > 0 {
            parts.append("+\(additionsCount)")
        }
        if deletionsCount > 0 {
            parts.append("-\(deletionsCount)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Computes token-level differences using Longest Common Subsequence (LCS).
enum DiffEngine {
    private enum TokenCategory {
        case whitespace
        case word
        case punctuation
    }

    /// Splits text into tokens (words, punctuation, and whitespace runs).
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var currentCategory: TokenCategory?

        for scalar in text.unicodeScalars {
            let category: TokenCategory
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                category = .whitespace
            } else if CharacterSet.alphanumerics.contains(scalar) {
                category = .word
            } else {
                category = .punctuation
            }

            if let prev = currentCategory {
                if prev == category && category != .punctuation {
                    current.unicodeScalars.append(scalar)
                } else {
                    tokens.append(current)
                    current = String(scalar)
                    currentCategory = category
                }
            } else {
                current.unicodeScalars.append(scalar)
                currentCategory = category
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Compares two texts and produces word/token-level diff chunks and counts.
    static func diff(original: String, modified: String) -> DiffResult {
        if original == modified {
            return DiffResult(
                chunks: original.isEmpty ? [] : [.equal(original)],
                additionsCount: 0,
                deletionsCount: 0
            )
        }

        let a = tokenize(original)
        let b = tokenize(modified)

        let n = a.count
        let m = b.count

        // Standard LCS dynamic programming table
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        // Backtrack to build diff
        var rawChunks: [DiffChunk] = []
        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                rawChunks.append(.equal(a[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                rawChunks.append(.insert(b[j - 1]))
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                rawChunks.append(.delete(a[i - 1]))
                i -= 1
            }
        }
        rawChunks.reverse()

        // Merge adjacent chunks of the same type
        var merged: [DiffChunk] = []
        var additions = 0
        var deletions = 0

        for chunk in rawChunks {
            let isWhitespaceOnly = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            switch chunk {
            case .equal(let text):
                if case .equal(let lastText)? = merged.last {
                    merged[merged.count - 1] = .equal(lastText + text)
                } else {
                    merged.append(chunk)
                }
            case .insert(let text):
                if !isWhitespaceOnly { additions += 1 }
                if case .insert(let lastText)? = merged.last {
                    merged[merged.count - 1] = .insert(lastText + text)
                } else {
                    merged.append(chunk)
                }
            case .delete(let text):
                if !isWhitespaceOnly { deletions += 1 }
                if case .delete(let lastText)? = merged.last {
                    merged[merged.count - 1] = .delete(lastText + text)
                } else {
                    merged.append(chunk)
                }
            }
        }

        return DiffResult(chunks: merged, additionsCount: additions, deletionsCount: deletions)
    }
}
