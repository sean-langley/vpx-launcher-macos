import SwiftUI
import AppKit
import Foundation

@main
struct VPXLauncherApp: App {
    var body: some Scene {
        WindowGroup("VPX Launcher") {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
