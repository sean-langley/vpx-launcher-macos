import SwiftUI
import AppKit
import Foundation

// MARK: - Scanner / metadata / launcher

final class LauncherModel: ObservableObject {
    @Published var rootURL: URL?
    @Published var tables: [TableEntry] = []
    @Published var selection: TableEntry?
    @Published var isScanning = false
    @Published var isAuditing = false
    @Published var isLaunching = false
    @Published var isRefreshingOnline = false
    @Published var isMakingTablePortable = false
    @Published var portableTableNotice: PortableTableNotice?
    @Published var statusText = ""
    @Published var searchText = ""
    @Published var showSettings = false
    @Published var matchTarget: TableEntry?
    @Published var onlineGameCount = 0

    @Published var vpxAppPath: String {
        didSet { UserDefaults.standard.set(vpxAppPath, forKey: "VPXAppPath") }
    }
    @Published var romFolderPath: String {
        didSet { UserDefaults.standard.set(romFolderPath, forKey: "ROMFolderPath") }
    }
    @Published var vpxtoolPath: String {
        didSet { UserDefaults.standard.set(vpxtoolPath, forKey: "VPXToolPath") }
    }
    @Published var autoRefreshOnline: Bool {
        didSet { UserDefaults.standard.set(autoRefreshOnline, forKey: "AutoRefreshOnline") }
    }

    let fm = FileManager.default
    var vpsIndex: VPSDatabaseIndex?
    var manualMatches: [String: String]

    let vpsDatabaseURL = URL(string: "https://raw.githubusercontent.com/VirtualPinballSpreadsheet/vps-db/main/db/vpsdb.json")!
    let vpinMediaBase = "https://raw.githubusercontent.com/superhac/vpinmediadb/main"

    lazy var appSupportURL: URL = {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("VPX Launcher", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    lazy var cacheURL: URL = {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("VPX Launcher", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        try? fm.createDirectory(at: url.appendingPathComponent("Wheels", isDirectory: true), withIntermediateDirectories: true)
        try? fm.createDirectory(at: url.appendingPathComponent("Playfields", isDirectory: true), withIntermediateDirectories: true)
        return url
    }()

    init() {
        self.vpxAppPath = UserDefaults.standard.string(forKey: "VPXAppPath") ?? "/Applications/VPinballX_BGFX.app"
        self.romFolderPath = UserDefaults.standard.string(forKey: "ROMFolderPath") ?? NSString(string: "~/.pinmame/roms").expandingTildeInPath
        self.vpxtoolPath = UserDefaults.standard.string(forKey: "VPXToolPath") ?? ""
        if UserDefaults.standard.object(forKey: "AutoRefreshOnline") == nil {
            self.autoRefreshOnline = true
        } else {
            self.autoRefreshOnline = UserDefaults.standard.bool(forKey: "AutoRefreshOnline")
        }
        self.manualMatches = UserDefaults.standard.dictionary(forKey: "ManualVPSMatches") as? [String: String] ?? [:]

        if self.vpxtoolPath.isEmpty {
            self.vpxtoolPath = self.detectVPXToolPath() ?? ""
        }

        loadCachedVPSDatabase()

        if let stored = UserDefaults.standard.string(forKey: "TableRoot"), !stored.isEmpty {
            let url = URL(fileURLWithPath: stored, isDirectory: true)
            if fm.fileExists(atPath: url.path) {
                rootURL = url
                scan()
            }
        }

        if autoRefreshOnline, shouldRefreshVPSCache() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.refreshOnlineData(force: false)
            }
        }
    }

    var filteredTables: [TableEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tables }
        return tables.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) ||
            $0.fileName.localizedCaseInsensitiveContains(q) ||
            ($0.vpsMetadata?.name.localizedCaseInsensitiveContains(q) ?? false) ||
            ($0.vpsMetadata?.manufacturer.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var vpsGames: [VPSMetadata] { vpsIndex?.games ?? [] }

    var hasVPXTool: Bool { vpxtoolURL() != nil }

    func detectVPXToolPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/vpxtool",
            "/usr/local/bin/vpxtool",
            "\(home)/bin/vpxtool",
            "\(home)/.local/bin/vpxtool"
        ]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return found
        }

        // GUI applications inherit a sparse PATH on macOS, so ask a login shell too.
        let result = runProcess("/bin/zsh", ["-lc", "command -v vpxtool || true"])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty, fm.isExecutableFile(atPath: path) { return path }
        return nil
    }

    func vpxtoolURL() -> URL? {
        let expanded = NSString(string: vpxtoolPath).expandingTildeInPath
        guard !expanded.isEmpty, fm.isExecutableFile(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    func redetectVPXTool() {
        if let path = detectVPXToolPath() {
            vpxtoolPath = path
            let version = runProcess(path, ["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            statusText = version.isEmpty ? "vpxtool detected" : "Detected \(version)"
        } else {
            statusText = "vpxtool was not found"
        }
    }

}
