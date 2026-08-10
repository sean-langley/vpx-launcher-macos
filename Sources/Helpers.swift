import SwiftUI
import AppKit
import Foundation

// MARK: - Small process helper

@discardableResult
func runProcess(_ executable: String, _ arguments: [String] = [], environment: [String: String]? = nil) -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }

    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (-1, "", error.localizedDescription)
    }

    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, stdout, stderr)
}

func stringValue(_ value: Any?) -> String {
    switch value {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

func stableKey(_ text: String) -> String {
    var hash: UInt64 = 1469598103934665603
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }
    return String(format: "%016llx", hash)
}

func formatDurationSeconds(_ raw: String) -> String {
    guard let seconds = Int(raw), seconds >= 0 else { return raw }
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(seconds)s"
}

func normalizeTitle(_ raw: String) -> String {
    var s = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()

    // Strip the most common release metadata while preserving actual title words.
    let patterns = [
        #"\.(vpx|vpt)$"#,
        #"\([^)]*\)"#,
        #"\[[^]]*\]"#,
        #"\bv(?:ersion)?\s*\d+(?:\.\d+)*\b"#,
        #"\b(vpx|vpw|mod|original|remaster(?:ed)?|desktop|vr|fss|fs|4k|release|edition)\b"#
    ]
    for pattern in patterns {
        s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }

    s = s.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs)
    let b = Array(rhs)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var previous = Array(0...b.count)
    var current = Array(repeating: 0, count: b.count + 1)

    for i in 1...a.count {
        current[0] = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            current[j] = min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + cost
            )
        }
        swap(&previous, &current)
    }
    return previous[b.count]
}

func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
    if lhs == rhs { return 1.0 }
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

    let maxLen = max(lhs.count, rhs.count)
    let edit = 1.0 - (Double(levenshteinDistance(lhs, rhs)) / Double(maxLen))

    let stop = Set(["the", "a", "an", "of", "and", "pinball"])
    let leftTokens = Set(lhs.split(separator: " ").map(String.init).filter { !stop.contains($0) })
    let rightTokens = Set(rhs.split(separator: " ").map(String.init).filter { !stop.contains($0) })
    let union = leftTokens.union(rightTokens)
    let jaccard = union.isEmpty ? 0 : Double(leftTokens.intersection(rightTokens).count) / Double(union.count)

    var score = (edit * 0.58) + (jaccard * 0.42)
    if lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs) {
        let ratio = Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        if ratio > 0.70 { score = max(score, 0.93 * ratio + 0.06) }
    }
    return min(1.0, score)
}
