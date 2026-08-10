import SwiftUI
import AppKit
import Foundation

extension LauncherModel {
    // MARK: Launch

    func launchSelected() {
        guard let table = selection else { return }
        guard fm.fileExists(atPath: vpxAppPath) else {
            statusText = "VPX app not found — check Settings"
            showSettings = true
            return
        }

        isLaunching = true
        statusText = "Launching \(table.displayName)…"

        let script = #"""
set -u
orig="$( ( /usr/bin/defaults read com.apple.dock autohide 2>/dev/null ) || echo __unset__ )"
orig_delay="$( ( /usr/bin/defaults read com.apple.dock autohide-delay 2>/dev/null ) || echo __unset__ )"
orig_time="$( ( /usr/bin/defaults read com.apple.dock autohide-time-modifier 2>/dev/null ) || echo __unset__ )"
restore_default() {
    local key="$1" value="$2" type="$3"
    if [[ "$value" == "__unset__" ]]; then
        /usr/bin/defaults delete com.apple.dock "$key" >/dev/null 2>&1 || true
    else
        /usr/bin/defaults write com.apple.dock "$key" "$type" "$value" >/dev/null 2>&1 || true
    fi
}
restore_dock() {
    if [[ "$orig" == "__unset__" ]]; then
        /usr/bin/defaults delete com.apple.dock autohide >/dev/null 2>&1 || true
    elif [[ "$orig" == "1" ]]; then
        /usr/bin/defaults write com.apple.dock autohide -bool true >/dev/null
    else
        /usr/bin/defaults write com.apple.dock autohide -bool false >/dev/null
    fi
    restore_default autohide-delay "$orig_delay" -float
    restore_default autohide-time-modifier "$orig_time" -float
    /usr/bin/killall Dock >/dev/null 2>&1 || true
}
trap restore_dock EXIT HUP INT TERM
/usr/bin/defaults write com.apple.dock autohide -bool true >/dev/null
# Hide immediately, then make the hot-edge delay enormous while VPX owns the display.
/usr/bin/defaults write com.apple.dock autohide-time-modifier -float 0 >/dev/null
/usr/bin/defaults write com.apple.dock autohide-delay -float 1000 >/dev/null
/usr/bin/killall Dock >/dev/null 2>&1 || true
/usr/bin/open -n -W -a "$VPX_APP" "$TABLE_PATH"
"""#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VPX_APP": vpxAppPath,
            "TABLE_PATH": table.url.path
        ]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.isLaunching = false
                self.statusText = proc.terminationStatus == 0 ? "VPX closed" : "VPX exited with status \(proc.terminationStatus)"
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        do {
            try process.run()
        } catch {
            isLaunching = false
            statusText = "Could not launch VPX: \(error.localizedDescription)"
        }
    }
}
