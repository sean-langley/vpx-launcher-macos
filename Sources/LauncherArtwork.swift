import SwiftUI
import AppKit
import Foundation

extension LauncherModel {
    // MARK: Artwork and media

    func artworkOverrideDirectory() -> URL {
        let dir = appSupportURL.appendingPathComponent("ArtworkOverrides", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func customArtworkURL(for entry: TableEntry) -> URL? {
        let key = stableKey(entry.url.path)
        guard let files = try? fm.contentsOfDirectory(at: artworkOverrideDirectory(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return files.first { $0.deletingPathExtension().lastPathComponent == key && imageExtensions().contains($0.pathExtension.lowercased()) }
    }

    func cachedWheelURL(vpsID: String) -> URL {
        cacheURL.appendingPathComponent("Wheels/\(vpsID).png")
    }

    func cachedPlayfieldURL(vpsID: String) -> URL {
        cacheURL.appendingPathComponent("Playfields/\(vpsID).png")
    }

    func applyCachedArtwork(to entry: TableEntry) {
        if let custom = customArtworkURL(for: entry) {
            entry.wheelImageURL = custom
        } else if let local = entry.localWheelURL {
            entry.wheelImageURL = local
        } else if let id = entry.vpsMetadata?.id {
            let cached = cachedWheelURL(vpsID: id)
            entry.wheelImageURL = fm.fileExists(atPath: cached.path) ? cached : nil
        } else {
            entry.wheelImageURL = nil
        }

        if let local = entry.localPlayfieldURL {
            entry.playfieldImageURL = local
        } else if let id = entry.vpsMetadata?.id {
            let cached = cachedPlayfieldURL(vpsID: id)
            entry.playfieldImageURL = fm.fileExists(atPath: cached.path) ? cached : nil
        } else {
            entry.playfieldImageURL = nil
        }
    }

    func chooseArtwork(for entry: TableEntry) {
        let panel = NSOpenPanel()
        panel.title = "Choose Wheel Artwork"
        panel.prompt = "Use Artwork"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = Array(imageExtensions())
        panel.directoryURL = entry.folderURL
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let key = stableKey(entry.url.path)
        let dir = artworkOverrideDirectory()
        if let old = customArtworkURL(for: entry) { try? fm.removeItem(at: old) }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = dir.appendingPathComponent("\(key).\(ext)")
        do {
            try fm.copyItem(at: source, to: destination)
            entry.wheelImageURL = destination
        } catch {
            statusText = "Could not save artwork: \(error.localizedDescription)"
        }
    }

    func clearArtworkOverride(for entry: TableEntry) {
        if let old = customArtworkURL(for: entry) { try? fm.removeItem(at: old) }
        applyCachedArtwork(to: entry)
    }

    func fetchWheelIfNeeded(for entry: TableEntry) {
        guard customArtworkURL(for: entry) == nil,
              entry.localWheelURL == nil,
              let id = entry.vpsMetadata?.id else { return }

        let destination = cachedWheelURL(vpsID: id)
        if fm.fileExists(atPath: destination.path) {
            entry.wheelImageURL = destination
            return
        }
        guard let remote = URL(string: "\(vpinMediaBase)/\(id)/wheel.png") else { return }
        downloadImage(remote, to: destination) { ok in
            if ok {
                DispatchQueue.main.async { entry.wheelImageURL = destination }
            }
        }
    }

    func ensurePreviewMedia(for entry: TableEntry) {
        guard entry.localPlayfieldURL == nil, let id = entry.vpsMetadata?.id else { return }
        let destination = cachedPlayfieldURL(vpsID: id)
        if fm.fileExists(atPath: destination.path) {
            entry.playfieldImageURL = destination
            return
        }
        guard let remote = URL(string: "\(vpinMediaBase)/\(id)/1k/table.png") else { return }
        downloadImage(remote, to: destination) { ok in
            if ok {
                DispatchQueue.main.async { entry.playfieldImageURL = destination }
            }
        }
    }

    func downloadImage(_ remote: URL, to destination: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  !data.isEmpty,
                  NSImage(data: data) != nil else {
                completion(false)
                return
            }
            do {
                try data.write(to: destination, options: .atomic)
                completion(true)
            } catch {
                completion(false)
            }
        }.resume()
    }

}
