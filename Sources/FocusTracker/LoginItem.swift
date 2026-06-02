import Foundation
import ServiceManagement

/// Launch-at-login via the modern SMAppService API (macOS 13+).
/// Registers the running `.app` bundle; only works from the packaged app.
enum LoginItem {
    static var isEnabled: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else {
            FileHandle.standardError.write(Data("scattrd: launch-at-login needs the .app bundle\n".utf8))
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            FileHandle.standardError.write(Data("scattrd: login item \(enabled ? "register" : "unregister") failed: \(error)\n".utf8))
        }
    }
}
