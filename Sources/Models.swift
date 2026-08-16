import SwiftUI
import AppKit
import Foundation

// MARK: - Models

enum ROMAuditState: Equatable {
    case notAudited
    case auditing
    case noROMReference
    case present(String)
    case missing(String)
    case failed(String)

    var label: String? {
        switch self {
        case .notAudited: return nil
        case .auditing: return "Auditing…"
        case .noROMReference: return "No ROM ref"
        case .present(let name): return "ROM: \(name)"
        case .missing(let name): return "ROM missing: \(name)"
        case .failed: return "Audit failed"
        }
    }

    var isWarning: Bool {
        switch self {
        case .missing, .failed: return true
        default: return false
        }
    }
}

enum TableVerificationState: Equatable {
    case notChecked
    case checking
    case valid
    case warning(String)
    case unavailable

    var label: String? {
        switch self {
        case .notChecked: return nil
        case .checking: return "Verifying…"
        case .valid: return "VPX ✓"
        case .warning: return "VPX warning"
        case .unavailable: return nil
        }
    }

    var isWarning: Bool {
        if case .warning = self { return true }
        return false
    }
}

struct PortableTableNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct LocalTableInfo: Hashable {
    var title = ""
    var description = ""
    var authors: [String] = []
    var manufacturer = ""
    var year = ""
    var vpsID = ""
    var ipdbID = ""

    // Optional fields from VPX 10.8.1's standardized .info User section.
    var rating = ""
    var favorite = false
    var lastRun = ""
    var startCount = ""
    var runTime = ""
    var tags: [String] = []
}

struct VPSMetadata: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let year: String
    let theme: [String]
    let type: String
    let players: String
    let ipdbID: String
    let version: String
    let authors: [String]
    let tableURL: String
    let romVersions: [String]

    var subtitle: String {
        [manufacturer, year].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    static func from(_ dictionary: [String: Any]) -> VPSMetadata? {
        let id = stringValue(dictionary["id"])
        let name = stringValue(dictionary["name"])
        guard !id.isEmpty, !name.isEmpty else { return nil }

        let manufacturer = stringValue(dictionary["manufacturer"])
        let year = stringValue(dictionary["year"])
        let type = stringValue(dictionary["type"])
        let players = stringValue(dictionary["players"])

        var themes: [String] = []
        if let array = dictionary["theme"] as? [Any] {
            themes = array.map { stringValue($0) }.filter { !$0.isEmpty }
        } else {
            let value = stringValue(dictionary["theme"])
            if !value.isEmpty { themes = [value] }
        }

        var ipdbID = stringValue(dictionary["ipdbNr"])
        if ipdbID.isEmpty { ipdbID = stringValue(dictionary["ipdb_id"]) }
        if ipdbID.isEmpty {
            let url = stringValue(dictionary["ipdbUrl"])
            if let regex = try? NSRegularExpression(pattern: #"id=(\d+)"#),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..<url.endIndex, in: url)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: url) {
                ipdbID = String(url[r])
            }
        }

        let tableFiles = dictionary["tableFiles"] as? [[String: Any]] ?? []
        let vpxFiles = tableFiles.filter { stringValue($0["tableFormat"]).uppercased() == "VPX" }
        let latest = vpxFiles.sorted {
            stringValue($0["version"]).localizedStandardCompare(stringValue($1["version"])) == .orderedDescending
        }.first

        let version = stringValue(latest?["version"])
        let authors = (latest?["authors"] as? [Any] ?? []).map { stringValue($0) }.filter { !$0.isEmpty }

        var tableURL = ""
        if let urls = latest?["urls"] as? [[String: Any]] {
            if let url = urls.first(where: { ($0["broken"] as? Bool) != true }) {
                tableURL = stringValue(url["url"])
            }
        }

        let romFiles = dictionary["romFiles"] as? [[String: Any]] ?? []
        let romVersions = romFiles.map { stringValue($0["version"]) }.filter { !$0.isEmpty }

        return VPSMetadata(
            id: id,
            name: name,
            manufacturer: manufacturer,
            year: year,
            theme: themes,
            type: type,
            players: players,
            ipdbID: ipdbID,
            version: version,
            authors: authors,
            tableURL: tableURL,
            romVersions: romVersions
        )
    }
}

struct VPSDatabaseIndex {
    let games: [VPSMetadata]
    let byID: [String: VPSMetadata]
    let exactNames: [String: [VPSMetadata]]
    let tokenIDs: [String: Set<String>]
}

final class TableEntry: ObservableObject, Identifiable, Hashable {
    static func == (lhs: TableEntry, rhs: TableEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id = UUID()
    let url: URL
    let folderURL: URL
    let displayName: String
    let fileName: String
    let fileStem: String
    let hasPuP: Bool
    let hasFlexDMD: Bool
    let hasUltraDMD: Bool
    let hasB2S: Bool
    let hasAltSound: Bool
    let hasAltColor: Bool
    let hasSerum: Bool
    let hasVNI: Bool
    let hasMusic: Bool
    @Published var hasLocalPinMAME: Bool
    let hasRulesheet: Bool
    let hasVPReg: Bool
    let hasINI: Bool
    let hasCache: Bool
    let localInfo: LocalTableInfo?
    let localWheelURL: URL?
    let localPlayfieldURL: URL?

    @Published var romAudit: ROMAuditState = .notAudited
    @Published var romAuditSource: String = ""
    @Published var verification: TableVerificationState = .notChecked
    @Published var highScores: String = ""
    @Published var isLoadingScores = false
    @Published var vpsMetadata: VPSMetadata?
    @Published var vpsConfidence: Double = 0
    @Published var vpsMatchSource: String = ""
    @Published var wheelImageURL: URL?
    @Published var playfieldImageURL: URL?

    init(url: URL,
         folderURL: URL,
         displayName: String,
         fileName: String,
         fileStem: String,
         hasPuP: Bool,
         hasFlexDMD: Bool,
         hasUltraDMD: Bool,
         hasB2S: Bool,
         hasAltSound: Bool,
         hasAltColor: Bool,
         hasSerum: Bool,
         hasVNI: Bool,
         hasMusic: Bool,
         hasLocalPinMAME: Bool,
         hasRulesheet: Bool,
         hasVPReg: Bool,
         hasINI: Bool,
         hasCache: Bool,
         localInfo: LocalTableInfo?,
         localWheelURL: URL?,
         localPlayfieldURL: URL?) {
        self.url = url
        self.folderURL = folderURL
        self.displayName = displayName
        self.fileName = fileName
        self.fileStem = fileStem
        self.hasPuP = hasPuP
        self.hasFlexDMD = hasFlexDMD
        self.hasUltraDMD = hasUltraDMD
        self.hasB2S = hasB2S
        self.hasAltSound = hasAltSound
        self.hasAltColor = hasAltColor
        self.hasSerum = hasSerum
        self.hasVNI = hasVNI
        self.hasMusic = hasMusic
        self.hasLocalPinMAME = hasLocalPinMAME
        self.hasRulesheet = hasRulesheet
        self.hasVPReg = hasVPReg
        self.hasINI = hasINI
        self.hasCache = hasCache
        self.localInfo = localInfo
        self.localWheelURL = localWheelURL
        self.localPlayfieldURL = localPlayfieldURL
        self.wheelImageURL = localWheelURL
        self.playfieldImageURL = localPlayfieldURL
    }
}
