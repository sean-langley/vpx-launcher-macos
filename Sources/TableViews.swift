import SwiftUI
import AppKit
import Foundation

// MARK: - Views

struct BadgeView: View {
    let text: String
    var warning = false
    var accent = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(warning ? Color.orange : (accent ? Color.accentColor : Color.secondary))
            .background((warning ? Color.orange : (accent ? Color.accentColor : Color.secondary)).opacity(0.12))
            .clipShape(Capsule())
    }
}

struct WheelImageView: View {
    let url: URL?
    var width: CGFloat = 108
    var height: CGFloat = 50

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "circle.grid.cross")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .frame(width: width, height: height)
    }
}

struct PlayfieldPreviewView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                // VPinMediaDB playfield media is stored in cabinet orientation.
                // Rotate it into the natural portrait orientation for the launcher.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 330, height: 230)
                    .rotationEffect(.degrees(90))
                    .frame(width: 230, height: 330)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait")
                            .font(.system(size: 32))
                        Text("No playfield preview")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 230, height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TableRow: View {
    @ObservedObject var entry: TableEntry

    var body: some View {
        HStack(spacing: 12) {
            WheelImageView(url: entry.wheelImageURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if let game = entry.vpsMetadata, !game.subtitle.isEmpty {
                    Text(game.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let info = entry.localInfo {
                    let subtitle = [info.manufacturer, info.year].filter { !$0.isEmpty }.joined(separator: " • ")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                HStack(spacing: 5) {
                    if entry.vpsMetadata != nil { BadgeView(text: "VPS", accent: true) }
                    if entry.hasPuP { BadgeView(text: "PuP") }
                    if entry.hasFlexDMD { BadgeView(text: "FlexDMD") }
                    if entry.hasUltraDMD { BadgeView(text: "UltraDMD") }
                    if entry.hasB2S { BadgeView(text: "B2S") }
                    if entry.hasCache { BadgeView(text: "Played") }
                    if case .checking = entry.verification {
                        ProgressView().controlSize(.mini)
                    } else if let label = entry.verification.label {
                        BadgeView(text: label, warning: entry.verification.isWarning)
                    }
                    if case .auditing = entry.romAudit {
                        ProgressView().controlSize(.mini)
                    } else if let label = entry.romAudit.label {
                        BadgeView(text: label, warning: entry.romAudit.isWarning)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.vertical, 4)
    }
}

struct DetailView: View {
    @ObservedObject var entry: TableEntry
    @ObservedObject var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 18) {
                    WheelImageView(url: entry.wheelImageURL, width: 190, height: 90)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.vpsMetadata?.name ?? entry.displayName)
                            .font(.title2.weight(.semibold))
                        if entry.vpsMetadata?.name != nil && entry.vpsMetadata?.name != entry.displayName {
                            Text(entry.displayName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }

                Divider()

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let game = entry.vpsMetadata {
                            GroupBox("Game Information") {
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                    GridRow { Text("Manufacturer").foregroundStyle(.secondary); Text(game.manufacturer.isEmpty ? "—" : game.manufacturer) }
                                    GridRow { Text("Year").foregroundStyle(.secondary); Text(game.year.isEmpty ? "—" : game.year) }
                                    GridRow { Text("Type").foregroundStyle(.secondary); Text(game.type.isEmpty ? "—" : game.type) }
                                    GridRow { Text("Players").foregroundStyle(.secondary); Text(game.players.isEmpty ? "—" : game.players) }
                                    GridRow { Text("Theme").foregroundStyle(.secondary); Text(game.theme.isEmpty ? "—" : game.theme.joined(separator: " • ")) }
                                    GridRow { Text("VPS ID").foregroundStyle(.secondary); Text(game.id).textSelection(.enabled) }
                                    if !game.ipdbID.isEmpty {
                                        GridRow { Text("IPDB ID").foregroundStyle(.secondary); Text(game.ipdbID).textSelection(.enabled) }
                                    }
                                    if !game.version.isEmpty {
                                        GridRow { Text("Latest VPX").foregroundStyle(.secondary); Text(game.version) }
                                    }
                                    if !game.authors.isEmpty {
                                        GridRow { Text("Authors").foregroundStyle(.secondary); Text(game.authors.joined(separator: ", ")) }
                                    }
                                    if !game.romVersions.isEmpty {
                                        GridRow { Text("VPS ROMs").foregroundStyle(.secondary); Text(game.romVersions.joined(separator: ", ")).lineLimit(3) }
                                    }
                                    GridRow {
                                        Text("Match").foregroundStyle(.secondary)
                                        Text("\(entry.vpsMatchSource) • \(Int(entry.vpsConfidence * 100))%")
                                    }
                                }
                                .font(.callout)
                                .padding(.top, 4)
                            }
                        } else if let info = entry.localInfo {
                            GroupBox("Table Information (.info)") {
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                    if !info.title.isEmpty { GridRow { Text("Title").foregroundStyle(.secondary); Text(info.title) } }
                                    if !info.manufacturer.isEmpty { GridRow { Text("Manufacturer").foregroundStyle(.secondary); Text(info.manufacturer) } }
                                    if !info.year.isEmpty { GridRow { Text("Year").foregroundStyle(.secondary); Text(info.year) } }
                                    if !info.authors.isEmpty { GridRow { Text("Authors").foregroundStyle(.secondary); Text(info.authors.joined(separator: ", ")) } }
                                    if !info.vpsID.isEmpty { GridRow { Text("VPS ID").foregroundStyle(.secondary); Text(info.vpsID) } }
                                }
                                .font(.callout)
                            }
                        }

                        if let info = entry.localInfo,
                           info.favorite || !info.rating.isEmpty || !info.lastRun.isEmpty || !info.startCount.isEmpty || !info.runTime.isEmpty || !info.tags.isEmpty {
                            GroupBox("Library Data (.info)") {
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                    if info.favorite { GridRow { Text("Favorite").foregroundStyle(.secondary); Text("Yes") } }
                                    if !info.rating.isEmpty { GridRow { Text("Rating").foregroundStyle(.secondary); Text(info.rating) } }
                                    if !info.lastRun.isEmpty { GridRow { Text("Last run").foregroundStyle(.secondary); Text(info.lastRun).textSelection(.enabled) } }
                                    if !info.startCount.isEmpty { GridRow { Text("Start count").foregroundStyle(.secondary); Text(info.startCount) } }
                                    if !info.runTime.isEmpty { GridRow { Text("Run time").foregroundStyle(.secondary); Text(formatDurationSeconds(info.runTime)) } }
                                    if !info.tags.isEmpty { GridRow { Text("Tags").foregroundStyle(.secondary); Text(info.tags.joined(separator: ", ")) } }
                                }
                                .font(.callout)
                            }
                        }

                        GroupBox("Local Setup") {
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                GridRow { Text("Table").foregroundStyle(.secondary); Text(entry.url.path).textSelection(.enabled) }
                                GridRow { Text("PuP Pack").foregroundStyle(.secondary); Text(entry.hasPuP ? "Detected" : "—") }
                                GridRow { Text("FlexDMD").foregroundStyle(.secondary); Text(entry.hasFlexDMD ? "Detected" : "—") }
                                GridRow { Text("UltraDMD").foregroundStyle(.secondary); Text(entry.hasUltraDMD ? "Detected" : "—") }
                                GridRow { Text("B2S").foregroundStyle(.secondary); Text(entry.hasB2S ? "Detected" : "—") }
                                GridRow { Text("AltSound / AltColor").foregroundStyle(.secondary); Text([entry.hasAltSound ? "AltSound" : nil, entry.hasAltColor ? "AltColor" : nil].compactMap { $0 }.joined(separator: " • ").isEmpty ? "—" : [entry.hasAltSound ? "AltSound" : nil, entry.hasAltColor ? "AltColor" : nil].compactMap { $0 }.joined(separator: " • ")) }
                                GridRow { Text("Color DMD").foregroundStyle(.secondary); Text([entry.hasSerum ? "Serum" : nil, entry.hasVNI ? "VNI" : nil].compactMap { $0 }.joined(separator: " • ").isEmpty ? "—" : [entry.hasSerum ? "Serum" : nil, entry.hasVNI ? "VNI" : nil].compactMap { $0 }.joined(separator: " • ")) }
                                GridRow { Text("Music").foregroundStyle(.secondary); Text(entry.hasMusic ? "Detected" : "—") }
                                GridRow { Text("Local PinMAME").foregroundStyle(.secondary); Text(entry.hasLocalPinMAME ? "Detected" : "—") }
                                GridRow { Text("Rules / manual").foregroundStyle(.secondary); Text(entry.hasRulesheet ? "Detected" : "—") }
                                GridRow { Text("Table INI").foregroundStyle(.secondary); Text(entry.hasINI ? "Yes" : "No") }
                                GridRow { Text("VPReg").foregroundStyle(.secondary); Text(entry.hasVPReg ? "Yes" : "No") }
                                GridRow { Text("Previously launched").foregroundStyle(.secondary); Text(entry.hasCache ? "Yes" : "No") }
                                GridRow {
                                    Text("VPX structure").foregroundStyle(.secondary)
                                    switch entry.verification {
                                    case .notChecked: Text(model.hasVPXTool ? "Not verified" : "vpxtool not configured")
                                    case .checking: HStack { ProgressView().controlSize(.small); Text("Verifying…") }
                                    case .valid: Text("Verified by vpxtool")
                                    case .warning(let message): Text(message).foregroundStyle(.orange).textSelection(.enabled).lineLimit(4)
                                    case .unavailable: Text("vpxtool not configured")
                                    }
                                }
                                GridRow {
                                    Text("ROM audit").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        switch entry.romAudit {
                                        case .notAudited: Text("Not audited")
                                        case .auditing: HStack { ProgressView().controlSize(.small); Text("Auditing…") }
                                        case .noROMReference: Text("No PinMAME ROM reference found")
                                        case .present(let name): Text("\(name).zip present")
                                        case .missing(let name): Text("\(name).zip missing").foregroundStyle(.orange)
                                        case .failed(let message): Text(message).foregroundStyle(.orange).textSelection(.enabled)
                                        }
                                        if !entry.romAuditSource.isEmpty {
                                            Text(entry.romAuditSource).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .font(.callout)
                        }

                        if model.hasVPXTool {
                            GroupBox("High Scores") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if entry.isLoadingScores {
                                        HStack { ProgressView().controlSize(.small); Text("Reading saved scores…") }
                                    } else if entry.highScores.isEmpty {
                                        Text("Read PinMAME, VPReg, GLF, or supported EM high scores with vpxtool.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button("Load High Scores") { model.loadHighScores(for: entry) }
                                    } else {
                                        ScrollView(.horizontal) {
                                            Text(entry.highScores)
                                                .font(.system(.caption, design: .monospaced))
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Button("Refresh Scores") { model.loadHighScores(for: entry) }
                                            .controlSize(.small)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PlayfieldPreviewView(url: entry.playfieldImageURL)
                }

                HStack(spacing: 10) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    }
                    Button("Choose Artwork…") { model.chooseArtwork(for: entry) }
                    Button("Reset Artwork") { model.clearArtworkOverride(for: entry) }
                    Button("Audit Table") { model.auditSelected(entry) }
                        .disabled(model.isAuditing)
                    Button {
                        model.makeTablePortable(entry)
                    } label: {
                        Label(model.isMakingTablePortable ? "Making Portable…" : "Make Table Portable", systemImage: "shippingbox.and.arrow.backward")
                    }
                    .disabled(model.isMakingTablePortable || model.isAuditing)

                    if model.onlineGameCount > 0 {
                        Button(entry.vpsMetadata == nil ? "Match with VPS…" : "Change VPS Match…") {
                            model.matchTarget = entry
                        }
                    }
                    if entry.vpsMatchSource == "Manual" {
                        Button("Clear Manual Match") { model.clearManualMatch(entry) }
                    }
                    if let game = entry.vpsMetadata,
                       !game.tableURL.isEmpty,
                       let url = URL(string: game.tableURL) {
                        Button("Open Table Page") { NSWorkspace.shared.open(url) }
                    }

                    Spacer()

                    Button {
                        model.launchSelected()
                    } label: {
                        Label(model.isLaunching ? "Running…" : "Launch Table", systemImage: "play.fill")
                            .foregroundStyle(.white)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isLaunching)
                }
            }
            .padding(24)
        }
        .onAppear { model.ensurePreviewMedia(for: entry) }
        .alert(item: $model.portableTableNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
