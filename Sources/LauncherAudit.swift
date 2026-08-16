import SwiftUI
import AppKit
import Foundation

extension LauncherModel {
    // MARK: Table / ROM audit

    func makeTablePortable(_ entry: TableEntry) {
        guard !isMakingTablePortable else { return }

        let tool = vpxtoolURL()
        let binary = vpxBinaryURL()
        guard tool != nil || binary != nil else {
            statusText = "Could not determine the table ROM — check vpxtool or VPX in Settings"
            showSettings = true
            return
        }

        isMakingTablePortable = true
        statusText = "Making \(entry.displayName) portable…"

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.portableROMCopy(entry: entry, vpxtool: tool, vpxBinary: binary)
            DispatchQueue.main.async {
                self.isMakingTablePortable = false
                self.statusText = result.status
                self.portableTableNotice = PortableTableNotice(title: result.title, message: result.message)
                if result.succeeded {
                    entry.hasLocalPinMAME = true
                    entry.romAudit = .present(result.romName ?? "ROM")
                    entry.romAuditSource = result.source
                }
            }
        }
    }

    private func portableROMCopy(entry: TableEntry, vpxtool: URL?, vpxBinary: URL?) -> (succeeded: Bool, title: String, message: String, status: String, romName: String?, source: String) {
        let detection = detectRequiredROM(entry: entry, vpxtool: vpxtool, vpxBinary: vpxBinary)
        guard let romName = detection.romName else {
            let detail = detection.error ?? "No PinMAME ROM reference was found in this table."
            return (false, "Could Not Make Table Portable", detail, "Portable copy failed: \(detail)", nil, detection.source)
        }

        let configuredDirectory = URL(
            fileURLWithPath: NSString(string: romFolderPath).expandingTildeInPath,
            isDirectory: true
        )
        guard let source = matchingROM(named: romName, in: configuredDirectory) else {
            let expected = configuredDirectory.appendingPathComponent("\(romName).zip").path
            let detail = "The required ROM \(romName).zip was not found in the configured ROM folder.\n\nExpected: \(expected)"
            return (false, "ROM Not Found", detail, "Portable copy failed: \(romName).zip not found", romName, detection.source)
        }

        let destinationDirectory = entry.folderURL
            .appendingPathComponent("pinmame", isDirectory: true)
            .appendingPathComponent("roms", isDirectory: true)
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)

        do {
            if fm.fileExists(atPath: destination.path) {
                if fm.contentsEqual(atPath: source.path, andPath: destination.path) {
                    let message = "\(source.lastPathComponent) is already present and identical. No copy was needed.\n\nWarning: clone/parent ROM dependencies could not be determined reliably, so only the directly referenced ROM was checked."
                    return (true, "Table Is Already Portable", message, "Portable ROM already present: \(source.lastPathComponent)", romName, detection.source)
                }
                let detail = "A different file already exists at \(destination.path). It was left unchanged."
                return (false, "Local ROM Already Exists", detail, "Portable copy stopped: existing ROM differs", romName, detection.source)
            }

            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
            let message = "Copied \(source.lastPathComponent) to:\n\(destination.path)\n\nWarning: clone/parent ROM dependencies could not be determined reliably, so only the directly referenced ROM was copied."
            return (true, "Table Made Portable", message, "Copied \(source.lastPathComponent) beside \(entry.fileName)", romName, detection.source)
        } catch {
            let detail = "Could not copy \(source.lastPathComponent): \(error.localizedDescription)"
            return (false, "Copy Failed", detail, "Portable copy failed: \(error.localizedDescription)", romName, detection.source)
        }
    }

    private func detectRequiredROM(entry: TableEntry, vpxtool: URL?, vpxBinary: URL?) -> (romName: String?, source: String, error: String?) {
        if let vpxtool {
            let result = runProcess(vpxtool.path, ["romname", entry.url.path])
            if result.status == 0, let rom = parseROMNameFromToolOutput(result.stdout) {
                return (rom, "vpxtool • portable copy", nil)
            }
            if result.status == 0, result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (nil, "vpxtool", "No PinMAME ROM reference was found in this table.")
            }
        }

        guard let vpxBinary else {
            return (nil, "vpxtool", "vpxtool could not determine the ROM and VPX is unavailable for fallback extraction.")
        }

        do {
            let script = try obtainScript(for: entry, vpxBinary: vpxBinary)
            guard let rom = detectROMName(in: script) else {
                return (nil, "VBS fallback", "No PinMAME ROM reference was found in this table.")
            }
            return (rom, "VBS fallback • portable copy", nil)
        } catch {
            return (nil, "VBS fallback", error.localizedDescription)
        }
    }

    private func matchingROM(named romName: String, in directory: URL) -> URL? {
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let expected = "\(romName).zip"
        return files.first {
            $0.lastPathComponent.compare(expected, options: [.caseInsensitive, .literal]) == .orderedSame
        }
    }

    func deepAuditAll() {
        guard !tables.isEmpty else { return }
        let tool = vpxtoolURL()
        let binary = vpxBinaryURL()
        guard tool != nil || binary != nil else {
            statusText = "Neither vpxtool nor the VPX executable was found — check Settings"
            showSettings = true
            return
        }

        isAuditing = true
        statusText = tool == nil ? "Auditing ROM references…" : "Auditing tables with vpxtool…"
        let romSet = availableROMNames()
        let items = tables

        DispatchQueue.global(qos: .utility).async {
            for (index, entry) in items.enumerated() {
                DispatchQueue.main.async {
                    entry.romAudit = .auditing
                    entry.verification = tool == nil ? .unavailable : .checking
                    self.statusText = "Auditing \(index + 1)/\(items.count): \(entry.displayName)"
                }

                let romResult = self.auditROM(entry: entry, vpxtool: tool, vpxBinary: binary, availableROMs: romSet)
                let verification = self.verifyTable(entry: entry, vpxtool: tool)
                DispatchQueue.main.async {
                    entry.romAudit = romResult.state
                    entry.romAuditSource = romResult.source
                    entry.verification = verification
                }
            }

            DispatchQueue.main.async {
                self.isAuditing = false
                let missing = items.filter {
                    if case .missing = $0.romAudit { return true }
                    return false
                }.count
                let warnings = items.filter {
                    if case .warning = $0.verification { return true }
                    return false
                }.count

                var parts: [String] = ["Audit complete"]
                if missing > 0 { parts.append("\(missing) missing ROM set\(missing == 1 ? "" : "s")") }
                if warnings > 0 { parts.append("\(warnings) VPX verification warning\(warnings == 1 ? "" : "s")") }
                self.statusText = parts.joined(separator: " • ")
            }
        }
    }

    func auditSelected(_ entry: TableEntry) {
        guard !isAuditing else { return }
        let tool = vpxtoolURL()
        let binary = vpxBinaryURL()
        guard tool != nil || binary != nil else {
            statusText = "Neither vpxtool nor the VPX executable was found — check Settings"
            showSettings = true
            return
        }

        let romSet = availableROMNames()
        entry.romAudit = .auditing
        entry.verification = tool == nil ? .unavailable : .checking
        statusText = "Auditing \(entry.displayName)…"

        DispatchQueue.global(qos: .utility).async {
            let romResult = self.auditROM(entry: entry, vpxtool: tool, vpxBinary: binary, availableROMs: romSet)
            let verification = self.verifyTable(entry: entry, vpxtool: tool)
            DispatchQueue.main.async {
                entry.romAudit = romResult.state
                entry.romAuditSource = romResult.source
                entry.verification = verification
                self.statusText = "Audit complete: \(entry.displayName)"
            }
        }
    }

    func availableROMNames() -> Set<String> {
        let dir = URL(fileURLWithPath: NSString(string: romFolderPath).expandingTildeInPath, isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return Set(files.filter { $0.pathExtension.lowercased() == "zip" }.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
    }

    func auditROM(entry: TableEntry, vpxtool: URL?, vpxBinary: URL?, availableROMs: Set<String>) -> (state: ROMAuditState, source: String) {
        if let vpxtool {
            let result = runProcess(vpxtool.path, ["romname", entry.url.path])
            if result.status == 0 {
                if let rom = parseROMNameFromToolOutput(result.stdout) {
                    let state: ROMAuditState = availableROMs.contains(rom.lowercased()) ? .present(rom) : .missing(rom)
                    return (state, "vpxtool")
                }
                // A successful command with no ROM name means the table is probably ROM-less.
                if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (.noROMReference, "vpxtool")
                }
            }
            // vpxtool may not recognize every script style. Fall through to the legacy extractor.
        }

        guard let vpxBinary else {
            return (.failed("vpxtool could not determine the ROM and VPX is unavailable for fallback extraction"), "vpxtool")
        }

        do {
            let script = try obtainScript(for: entry, vpxBinary: vpxBinary)
            guard let rom = detectROMName(in: script) else { return (.noROMReference, "VBS fallback") }
            let state: ROMAuditState = availableROMs.contains(rom.lowercased()) ? .present(rom) : .missing(rom)
            return (state, "VBS fallback")
        } catch {
            return (.failed(error.localizedDescription), "VBS fallback")
        }
    }

    func parseROMNameFromToolOutput(_ output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("no rom") || lower.contains("not found") { continue }
            if line.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
                return line
            }
        }
        return nil
    }

    func verifyTable(entry: TableEntry, vpxtool: URL?) -> TableVerificationState {
        guard let vpxtool else { return .unavailable }
        let result = runProcess(vpxtool.path, ["verify", entry.url.path])
        if result.status == 0 { return .valid }

        let combined = [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = combined.isEmpty ? "vpxtool verify exited with status \(result.status)" : String(combined.prefix(1200))
        return .warning(message)
    }

    func loadHighScores(for entry: TableEntry) {
        guard let tool = vpxtoolURL() else {
            entry.highScores = "vpxtool is required to read high scores."
            return
        }
        guard !entry.isLoadingScores else { return }

        entry.isLoadingScores = true
        entry.highScores = ""
        DispatchQueue.global(qos: .utility).async {
            let result = runProcess(tool.path, ["scores", "show", entry.url.path])
            let text: String
            if result.status == 0 {
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                text = output.isEmpty ? "No stored high scores were reported." : output
            } else {
                let errorText = [result.stdout, result.stderr]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                text = errorText.isEmpty ? "Could not read high scores (vpxtool status \(result.status))." : errorText
            }
            DispatchQueue.main.async {
                entry.highScores = text
                entry.isLoadingScores = false
            }
        }
    }

    func obtainScript(for entry: TableEntry, vpxBinary: URL) throws -> String {
        let sidecar = entry.url.deletingPathExtension().appendingPathExtension("vbs")
        if fm.fileExists(atPath: sidecar.path) {
            return try String(contentsOf: sidecar, encoding: .utf8)
        }

        let tempDir = fm.temporaryDirectory.appendingPathComponent("VPXLauncher-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let tempTable = tempDir.appendingPathComponent(entry.url.lastPathComponent)
        try fm.copyItem(at: entry.url, to: tempTable)

        let result = runProcess(vpxBinary.path, ["-extractvbs", tempTable.path])
        guard result.status == 0 else {
            throw NSError(domain: "VPXLauncher", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: result.stderr.isEmpty ? "VPX -extractvbs failed" : result.stderr])
        }

        let extracted = tempTable.deletingPathExtension().appendingPathExtension("vbs")
        guard fm.fileExists(atPath: extracted.path) else {
            throw NSError(domain: "VPXLauncher", code: 2, userInfo: [NSLocalizedDescriptionKey: "VPX did not produce an extracted VBS script"])
        }
        return try String(contentsOf: extracted, encoding: .utf8)
    }

    func detectROMName(in script: String) -> String? {
        let patterns = [
            #"(?im)^\s*(?:const\s+)?cGameName\s*=\s*\"([^\"]+)\""#,
            #"(?im)^\s*(?:const\s+)?cRomName\s*=\s*\"([^\"]+)\""#,
            #"(?im)^\s*(?:const\s+)?RomName\s*=\s*\"([^\"]+)\""#,
            #"(?im)^\s*(?:Controller\.)?GameName\s*=\s*\"([^\"]+)\""#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(script.startIndex..<script.endIndex, in: script)
            if let match = regex.firstMatch(in: script, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: script) {
                let candidate = String(script[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }

    func vpxBinaryURL() -> URL? {
        let app = URL(fileURLWithPath: vpxAppPath, isDirectory: true)
        let macOSDir = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let preferred = macOSDir.appendingPathComponent("VPinballX_BGFX")
        if fm.isExecutableFile(atPath: preferred.path) { return preferred }
        if let candidates = try? fm.contentsOfDirectory(at: macOSDir, includingPropertiesForKeys: nil),
           let executable = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) {
            return executable
        }
        return nil
    }

}
