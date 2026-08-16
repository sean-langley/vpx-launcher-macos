import SwiftUI
import AppKit
import Foundation

struct MatchSheet: View {
    @ObservedObject var entry: TableEntry
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var selected: VPSMetadata?

    init(entry: TableEntry, model: LauncherModel) {
        self.entry = entry
        self.model = model
        _query = State(initialValue: entry.vpsMetadata?.name ?? entry.displayName)
    }

    var results: [VPSMetadata] { model.searchVPS(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Match \(entry.displayName) with VPS")
                .font(.title2.weight(.semibold))

            TextField("Search game name", text: $query)
                .textFieldStyle(.roundedBorder)

            List(results, selection: $selected) { game in
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name).font(.body.weight(.medium))
                    Text(game.subtitle.isEmpty ? game.id : "\(game.subtitle) • \(game.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(game)
            }

            HStack {
                Text("Manual matches are remembered for this exact .vpx path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    if let selected { model.setManualMatch(entry, game: selected) }
                } label: {
                    Text("Use Match")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 650, height: 520)
    }
}

struct SettingsView: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("VPX Launcher Settings")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("VPX application").font(.headline)
                HStack {
                    TextField("/Applications/VPinballX_BGFX.app", text: $model.vpxAppPath)
                    Button("Choose…") { model.chooseVPXApp() }
                }
                Text("Used to launch tables and as the fallback script extractor when vpxtool is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PinMAME ROM folder").font(.headline)
                HStack {
                    TextField("~/.pinmame/roms", text: $model.romFolderPath)
                    Button("Choose…") { model.chooseROMFolder() }
                }
                Text("ROM audit checks the requested ZIP. Split-set parent dependencies are still left to PinMAME itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("vpxtool (optional, recommended)").font(.headline)
                HStack {
                    TextField("/opt/homebrew/bin/vpxtool", text: $model.vpxtoolPath)
                    Button("Choose…") { model.chooseVPXTool() }
                    Button("Detect") { model.redetectVPXTool() }
                }
                HStack(spacing: 6) {
                    Image(systemName: model.hasVPXTool ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.hasVPXTool ? Color.green : Color.orange)
                    Text(model.hasVPXTool
                         ? "Used for reliable ROM-name extraction, VPX structure verification, and saved high scores."
                         : "Not found. The launcher will fall back to VPX -extractvbs for ROM detection.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle("Automatically refresh VPS metadata (once per day)", isOn: $model.autoRefreshOnline)
            Text("Metadata comes from the Virtual Pinball Spreadsheet database. Missing local wheel/playfield artwork is cached from VPinMediaDB when a table is matched.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Text(model.onlineGameCount == 0 ? "No VPS database loaded" : "\(model.onlineGameCount) VPS games loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh Now") { model.refreshOnlineData(force: true) }
                    .disabled(model.isRefreshingOnline)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700, height: 500)
    }
}
