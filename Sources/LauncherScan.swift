import SwiftUI
import AppKit
import Foundation

extension LauncherModel {
    // MARK: Local table scan

    func scan() {
        guard let rootURL else { return }
        isScanning = true
        statusText = "Scanning…"
        let previousSelectionPath = selection?.url.path

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.scanTables(root: rootURL)
            DispatchQueue.main.async {
                self.tables = result
                self.selection = result.first(where: { $0.url.path == previousSelectionPath }) ?? result.first
                self.isScanning = false
                self.statusText = "\(result.count) table\(result.count == 1 ? "" : "s")"
                self.applyVPSMatches()
            }
        }
    }

    func scanTables(root: URL) -> [TableEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles],
                                             errorHandler: { _, _ in true }) else { return [] }

        var vpxURLs: [URL] = []
        for case let url as URL in enumerator {
            let comps = url.pathComponents.map { $0.lowercased() }
            if comps.contains("cache") {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() == "vpx" {
                vpxURLs.append(url)
            }
        }

        let grouped = Dictionary(grouping: vpxURLs, by: { $0.deletingLastPathComponent().path })
        var entries: [TableEntry] = []

        for url in vpxURLs {
            let folder = url.deletingLastPathComponent()
            var folderName = folder.lastPathComponent
            if folderName.lowercased().hasSuffix(".vpx") {
                folderName = String(folderName.dropLast(4))
            }
            let stem = url.deletingPathExtension().lastPathComponent
            let countInFolder = grouped[folder.path]?.count ?? 1
            let display = countInFolder > 1 ? "\(folderName) — \(stem)" : folderName

            let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let lowerNames = children.map { $0.lastPathComponent.lowercased() }

            let hasPuP = lowerNames.contains("pupvideos")
            let hasFlex = lowerNames.contains(where: { $0.hasSuffix(".flexdmd") })
            let hasUltra = lowerNames.contains(where: { $0.hasSuffix(".ultradmd") })
            let hasB2S = children.contains(where: { $0.pathExtension.lowercased() == "directb2s" }) || lowerNames.contains("b2s")
            let hasAltSound = lowerNames.contains("altsound")
            let hasAltColor = lowerNames.contains("altcolor")
            let hasSerum = lowerNames.contains("serum")
            let hasVNI = lowerNames.contains("vni")
            let hasMusic = lowerNames.contains("music")
            let hasLocalPinMAME = lowerNames.contains("pinmame")
            let hasRulesheet = children.contains(where: {
                let name = $0.lastPathComponent.lowercased()
                return $0.pathExtension.lowercased() == "pdf" && (name.contains("rule") || name.contains("manual"))
            }) || findLocalMedia(in: folder, typePrefix: "(GameHelp)") != nil || findLocalMedia(in: folder, typePrefix: "(GameInfo)") != nil
            let hasVPReg = fm.fileExists(atPath: folder.appendingPathComponent("user/VPReg.ini").path) || fm.fileExists(atPath: folder.appendingPathComponent("user/VPReg.stg").path)
            let hasINI = fm.fileExists(atPath: folder.appendingPathComponent(stem + ".ini").path)
            let cachePath = folder.appendingPathComponent("cache/\(stem)").path
            let hasCache = fm.fileExists(atPath: cachePath)
            let info = readInfoFile(in: folder, stem: stem, folderName: folderName)
            let localWheel = findLocalMedia(in: folder, typePrefix: "(Wheel)") ?? findLegacyWheelImage(in: folder)
            let localPlayfield = findLocalMedia(in: folder, typePrefix: "(Playfield)")

            let entry = TableEntry(
                url: url,
                folderURL: folder,
                displayName: display,
                fileName: url.lastPathComponent,
                fileStem: stem,
                hasPuP: hasPuP,
                hasFlexDMD: hasFlex,
                hasUltraDMD: hasUltra,
                hasB2S: hasB2S,
                hasAltSound: hasAltSound,
                hasAltColor: hasAltColor,
                hasSerum: hasSerum,
                hasVNI: hasVNI,
                hasMusic: hasMusic,
                hasLocalPinMAME: hasLocalPinMAME,
                hasRulesheet: hasRulesheet,
                hasVPReg: hasVPReg,
                hasINI: hasINI,
                hasCache: hasCache,
                localInfo: info,
                localWheelURL: localWheel,
                localPlayfieldURL: localPlayfield
            )
            applyCachedArtwork(to: entry)
            entries.append(entry)
        }

        return entries.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func imageExtensions() -> Set<String> {
        Set(["png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif", "apng", "webp"])
    }

    func findLocalMedia(in folder: URL, typePrefix: String) -> URL? {
        let dir = folder.appendingPathComponent("medias", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        let prefix = typePrefix.lowercased()
        let exts = imageExtensions()
        return files.first {
            $0.lastPathComponent.lowercased().hasPrefix(prefix) && exts.contains($0.pathExtension.lowercased())
        }
    }

    func findLegacyWheelImage(in folder: URL) -> URL? {
        let candidateDirs = ["Wheel", "wheel", "Animated wheel", "Animated Wheel"]
        let exts = imageExtensions()
        for dirname in candidateDirs {
            let dir = folder.appendingPathComponent(dirname, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            if let image = files.first(where: { exts.contains($0.pathExtension.lowercased()) }) {
                return image
            }
        }
        return nil
    }

    func readInfoFile(in folder: URL, stem: String, folderName: String) -> LocalTableInfo? {
        var candidates = [
            folder.appendingPathComponent(stem + ".info"),
            folder.appendingPathComponent(folderName + ".info")
        ]
        if let other = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).first(where: { $0.pathExtension.lowercased() == "info" }) {
            candidates.append(other)
        }

        for url in candidates where fm.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = root["Info"] as? [String: Any] else { continue }

            var result = LocalTableInfo()
            result.title = stringValue(info["Title"])
            result.description = stringValue(info["Description"])
            result.authors = (info["Authors"] as? [Any] ?? []).map { stringValue($0) }.filter { !$0.isEmpty }
            result.manufacturer = stringValue(info["Manufacturer"])
            result.year = stringValue(info["Year"])
            result.vpsID = stringValue(info["VPSId"])
            result.ipdbID = stringValue(info["IPDBId"])

            if let user = root["User"] as? [String: Any] {
                result.rating = stringValue(user["Rating"])
                let favorite = stringValue(user["Favorite"]).lowercased()
                result.favorite = favorite == "1" || favorite == "true" || favorite == "yes"
                result.lastRun = stringValue(user["LastRun"])
                result.startCount = stringValue(user["StartCount"])
                result.runTime = stringValue(user["RunTime"])
                result.tags = (user["Tags"] as? [Any] ?? []).map { stringValue($0) }.filter { !$0.isEmpty }
            }
            return result
        }
        return nil
    }

}
