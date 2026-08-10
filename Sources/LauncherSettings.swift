import SwiftUI
import AppKit
import Foundation

extension LauncherModel {
    // MARK: Folder / settings choosers

    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose VPX Tables Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let rootURL { panel.directoryURL = rootURL }

        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            UserDefaults.standard.set(url.path, forKey: "TableRoot")
            scan()
        }
    }

    func chooseVPXApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose VPinballX_BGFX.app"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            vpxAppPath = url.path
        }
    }

    func chooseROMFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose PinMAME ROM Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: romFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            romFolderPath = url.path
        }
    }

    func chooseVPXTool() {
        let panel = NSOpenPanel()
        panel.title = "Choose vpxtool"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !vpxtoolPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: vpxtoolPath).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            vpxtoolPath = url.path
        }
    }

}
