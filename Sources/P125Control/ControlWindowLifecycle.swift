import AppKit
import SwiftUI

final class ControlWindowLifecycle: NSObject, NSApplicationDelegate {
    private var openWindows: Set<ObjectIdentifier> = []
    private(set) var startingInMenuBar = ProcessInfo.processInfo.arguments.contains("--start-in-menu-bar")

    func applicationWillFinishLaunching(_ notification: Notification) {
        if startingInMenuBar { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func prepareToOpenControls() {
        startingInMenuBar = false
    }

    func register(_ window: NSWindow) {
        if startingInMenuBar {
            // SwiftUI may create or restore a window even when launched at login.
            window.alphaValue = 0
            DispatchQueue.main.async {
                if self.startingInMenuBar {
                    window.close()
                } else {
                    window.alphaValue = 1
                    self.register(window)
                }
            }
            return
        }
        guard openWindows.insert(ObjectIdentifier(window)).inserted else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: window)
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

struct ControlWindowAttachment: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onAttach: onAttach)
    }

    func updateNSView(_ view: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private let onAttach: (NSWindow) -> Void

        init(onAttach: @escaping (NSWindow) -> Void) {
            self.onAttach = onAttach
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onAttach(window) }
        }
    }
}
