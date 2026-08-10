import SwiftUI
import AppKit
import Foundation

extension LauncherModel {
    // MARK: VPS database

    func vpsCacheFile() -> URL { appSupportURL.appendingPathComponent("vpsdb.json") }

    func shouldRefreshVPSCache() -> Bool {
        let file = vpsCacheFile()
        guard let attrs = try? fm.attributesOfItem(atPath: file.path),
              let date = attrs[.modificationDate] as? Date else { return true }
        return Date().timeIntervalSince(date) > 24 * 60 * 60
    }

    func loadCachedVPSDatabase() {
        let file = vpsCacheFile()
        guard fm.fileExists(atPath: file.path) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? Data(contentsOf: file), let index = self.parseVPSDatabase(data) else { return }
            DispatchQueue.main.async {
                self.installVPSIndex(index, status: nil)
            }
        }
    }

    func refreshOnlineData(force: Bool = true) {
        if !force, !shouldRefreshVPSCache() { return }
        guard !isRefreshingOnline else { return }
        isRefreshingOnline = true
        statusText = "Downloading VPS metadata…"

        var request = URLRequest(url: vpsDatabaseURL)
        request.timeoutInterval = 30
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    self.isRefreshingOnline = false
                    self.statusText = "VPS refresh failed: \(error.localizedDescription)"
                }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                DispatchQueue.main.async {
                    self.isRefreshingOnline = false
                    self.statusText = "VPS refresh failed"
                }
                return
            }

            guard let index = self.parseVPSDatabase(data) else {
                DispatchQueue.main.async {
                    self.isRefreshingOnline = false
                    self.statusText = "Could not parse VPS database"
                }
                return
            }

            try? data.write(to: self.vpsCacheFile(), options: .atomic)
            DispatchQueue.main.async {
                self.isRefreshingOnline = false
                self.installVPSIndex(index, status: "VPS metadata refreshed — \(index.games.count) games")
            }
        }.resume()
    }

    func parseVPSDatabase(_ data: Data) -> VPSDatabaseIndex? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let raw: [[String: Any]]
        if let array = json as? [[String: Any]] {
            raw = array
        } else if let dictionary = json as? [String: Any] {
            raw = (dictionary["tables"] as? [[String: Any]]) ?? (dictionary["data"] as? [[String: Any]]) ?? []
        } else {
            return nil
        }

        var games: [VPSMetadata] = []
        games.reserveCapacity(raw.count)
        for item in raw {
            // Match the community manager's behavior: only catalog entries with VPX releases.
            let tableFiles = item["tableFiles"] as? [[String: Any]] ?? []
            if !tableFiles.contains(where: { stringValue($0["tableFormat"]).uppercased() == "VPX" }) { continue }
            if let game = VPSMetadata.from(item) { games.append(game) }
        }

        var byID: [String: VPSMetadata] = [:]
        var exact: [String: [VPSMetadata]] = [:]
        var tokenIDs: [String: Set<String>] = [:]
        let stop = Set(["the", "a", "an", "of", "and", "pinball", "machine"])

        for game in games {
            byID[game.id] = game
            let normalized = normalizeTitle(game.name)
            exact[normalized, default: []].append(game)
            for token in normalized.split(separator: " ").map(String.init) where token.count > 1 && !stop.contains(token) {
                tokenIDs[token, default: []].insert(game.id)
            }
        }

        return VPSDatabaseIndex(games: games, byID: byID, exactNames: exact, tokenIDs: tokenIDs)
    }

    func installVPSIndex(_ index: VPSDatabaseIndex, status: String?) {
        vpsIndex = index
        onlineGameCount = index.games.count
        if let status { statusText = status }
        applyVPSMatches()
    }

    func matchQueries(for entry: TableEntry) -> [String] {
        var values: [String] = []
        if let title = entry.localInfo?.title, !title.isEmpty { values.append(title) }
        values.append(entry.displayName)
        values.append(entry.fileStem)

        for source in [entry.displayName, entry.fileStem] {
            if let range = source.range(of: " (") { values.append(String(source[..<range.lowerBound])) }
            if let range = source.range(of: " [") { values.append(String(source[..<range.lowerBound])) }
        }

        var seen = Set<String>()
        return values.map(normalizeTitle).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func bestMatch(for entry: TableEntry, in index: VPSDatabaseIndex) -> (VPSMetadata, Double, String)? {
        if let manualID = manualMatches[entry.url.path], let game = index.byID[manualID] {
            return (game, 1.0, "Manual")
        }
        if let infoID = entry.localInfo?.vpsID, !infoID.isEmpty, let game = index.byID[infoID] {
            return (game, 1.0, ".info")
        }

        let queries = matchQueries(for: entry)
        for query in queries {
            if let exact = index.exactNames[query], exact.count == 1, let game = exact.first {
                return (game, 1.0, "Auto")
            }
        }

        var candidateIDs = Set<String>()
        let stop = Set(["the", "a", "an", "of", "and", "pinball", "machine"])
        for query in queries {
            for token in query.split(separator: " ").map(String.init) where token.count > 1 && !stop.contains(token) {
                candidateIDs.formUnion(index.tokenIDs[token] ?? [])
            }
        }
        if candidateIDs.isEmpty { return nil }

        var scored: [(VPSMetadata, Double)] = []
        scored.reserveCapacity(candidateIDs.count)
        for id in candidateIDs {
            guard let game = index.byID[id] else { continue }
            let gameName = normalizeTitle(game.name)
            let score = queries.map { titleSimilarity($0, gameName) }.max() ?? 0
            if score >= 0.72 { scored.append((game, score)) }
        }
        scored.sort { $0.1 > $1.1 }
        guard let best = scored.first else { return nil }
        let second = scored.dropFirst().first?.1 ?? 0

        // Err toward no match rather than silently attaching the wrong game's media.
        if best.1 >= 0.94 || (best.1 >= 0.84 && best.1 - second >= 0.035) {
            return (best.0, best.1, "Auto")
        }
        return nil
    }

    func applyVPSMatches() {
        guard let index = vpsIndex, !tables.isEmpty else { return }
        var matched = 0
        for entry in tables {
            if let match = bestMatch(for: entry, in: index) {
                entry.vpsMetadata = match.0
                entry.vpsConfidence = match.1
                entry.vpsMatchSource = match.2
                matched += 1
                applyCachedArtwork(to: entry)
                fetchWheelIfNeeded(for: entry)
            } else {
                entry.vpsMetadata = nil
                entry.vpsConfidence = 0
                entry.vpsMatchSource = ""
                applyCachedArtwork(to: entry)
            }
        }
        if !isScanning, !isRefreshingOnline {
            statusText = "\(tables.count) tables • \(matched) matched to VPS"
        }
    }

    func searchVPS(_ query: String) -> [VPSMetadata] {
        guard let index = vpsIndex else { return [] }
        let q = normalizeTitle(query)
        if q.isEmpty { return Array(index.games.prefix(100)) }

        return index.games.compactMap { game -> (VPSMetadata, Double)? in
            let name = normalizeTitle(game.name)
            if name.contains(q) || q.contains(name) {
                return (game, max(0.9, titleSimilarity(q, name)))
            }
            let score = titleSimilarity(q, name)
            return score >= 0.55 ? (game, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(100)
        .map { $0.0 }
    }

    func setManualMatch(_ entry: TableEntry, game: VPSMetadata) {
        manualMatches[entry.url.path] = game.id
        UserDefaults.standard.set(manualMatches, forKey: "ManualVPSMatches")
        entry.vpsMetadata = game
        entry.vpsConfidence = 1.0
        entry.vpsMatchSource = "Manual"
        applyCachedArtwork(to: entry)
        fetchWheelIfNeeded(for: entry)
        ensurePreviewMedia(for: entry)
        matchTarget = nil
    }

    func clearManualMatch(_ entry: TableEntry) {
        manualMatches.removeValue(forKey: entry.url.path)
        UserDefaults.standard.set(manualMatches, forKey: "ManualVPSMatches")
        applyVPSMatches()
    }

}
