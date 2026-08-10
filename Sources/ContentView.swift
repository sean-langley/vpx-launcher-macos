import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        NavigationSplitView {
            Group {
                if model.rootURL == nil {
                    VStack(spacing: 14) {
                        Image(systemName: "pin.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Choose your VPX tables folder")
                            .font(.headline)
                        Button("Choose Folder…") { model.chooseRootFolder() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.filteredTables, selection: $model.selection) { entry in
                        TableRow(entry: entry)
                            .tag(entry)
                            .contextMenu {
                                Button("Launch") {
                                    model.selection = entry
                                    model.launchSelected()
                                }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                                }
                                Button("Audit Table") { model.auditSelected(entry) }
                                if model.hasVPXTool {
                                    Button("Load High Scores") { model.loadHighScores(for: entry) }
                                }
                                Divider()
                                Button("Choose Artwork…") { model.chooseArtwork(for: entry) }
                                if model.onlineGameCount > 0 {
                                    Button("Match with VPS…") { model.matchTarget = entry }
                                }
                            }
                    }
                    .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search tables")
                }
            }
            .navigationSplitViewColumnWidth(min: 410, ideal: 500, max: 620)
        } detail: {
            if let entry = model.selection {
                DetailView(entry: entry, model: model)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "pin.circle")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("No Table Selected")
                        .font(.headline)
                    Text("Choose a table from the sidebar.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1050, minHeight: 680)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.chooseRootFolder()
                } label: {
                    Label("Choose Tables Folder", systemImage: "folder")
                }

                Button {
                    model.scan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.rootURL == nil || model.isScanning)

                Button {
                    model.refreshOnlineData(force: true)
                } label: {
                    Label("Refresh VPS", systemImage: "icloud.and.arrow.down")
                }
                .disabled(model.isRefreshingOnline)

                Button {
                    model.deepAuditAll()
                } label: {
                    Label("Audit Tables", systemImage: "checkmark.shield")
                }
                .disabled(model.rootURL == nil || model.isAuditing || model.isScanning)

                Button {
                    model.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if model.isScanning || model.isAuditing || model.isRefreshingOnline {
                    ProgressView().controlSize(.small)
                }
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let root = model.rootURL {
                    Text(root.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        .sheet(item: $model.matchTarget) { entry in
            MatchSheet(entry: entry, model: model)
        }
    }
}
