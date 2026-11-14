import AppKit

@main
struct LoginLauncher {
    @MainActor
    static func main() async {
        // The launcher lives in Contents/Library/LoginItems of the main app.
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let identifier = "local.p125.control"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--start-in-menu-bar"]
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false

        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            NSLog("Could not start P-125 Control at login: %@", error.localizedDescription)
        }
    }
}
