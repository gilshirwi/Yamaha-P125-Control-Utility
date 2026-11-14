import AppKit
import ServiceManagement
import SwiftUI

struct OpenAtLoginToggle: View {
    private static let service = SMAppService.loginItem(identifier: "local.p125.control.LoginLauncher")
    @State private var status = SMAppService.Status.notRegistered
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open at Login", isOn: Binding(
                get: { status == .enabled },
                set: setEnabled
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 11, weight: .medium))

            if status == .requiresApproval {
                Text("Allow P-125 Control in Login Items to start it automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption2)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func setEnabled(_ enabled: Bool) {
        let service = Self.service
        errorMessage = nil
        defer { refresh() }

        if enabled && service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        guard (service.status == .enabled) != enabled else { return }

        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        status = Self.service.status
    }
}
