import SwiftUI
import AppKit

enum ControlWindow: String, Codable {
    case main
}

@main
struct P125ControlApp: App {
    @NSApplicationDelegateAdaptor(ControlWindowLifecycle.self) private var controlWindows
    @StateObject private var piano = PianoModel()

    var body: some Scene {
        WindowGroup("P-125 Control", for: ControlWindow.self) { _ in
            ControlDesk(piano:piano).preferredColorScheme(.dark)
                .frame(minWidth:1000,minHeight:740)
                .background(ControlWindowAttachment(onAttach: controlWindows.register))
                .onAppear {
                    if !controlWindows.startingInMenuBar { NSApp.activate() }
                }
        } defaultValue: {
            .main
        }
        .defaultSize(width:1140,height:830).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after:.newItem) {
                Button("Refresh Piano Settings") { piano.refresh() }.keyboardShortcut("r")
                Button("Save Setup…") { piano.showSave = true }.keyboardShortcut("s").disabled(!piano.canSave)
            }
        }

        MenuBarExtra {
            CompactControls(piano: piano, prepareToOpenControls: controlWindows.prepareToOpenControls)
        } label: {
            Label {
                Text(menuBarTitle)
            } icon: {
                menuBarIcon
            }
            .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarTitle: LocalizedStringKey {
        guard piano.verified else { return "P-125 Control, piano offline" }
        return piano.isMuted(0) ? "P-125 Control, Main muted" : "P-125 Control, piano connected"
    }

    private var menuBarIcon: Image {
        if piano.verified {
            let icon = piano.isMuted(0) ? Self.mutedMenuBarIcon : Self.connectedMenuBarIcon
            if let icon { return Image(nsImage: icon).renderingMode(.original) }
        }
        return Image(systemName: "pianokeys")
    }

    private static let connectedMenuBarIcon = makeMenuBarIcon(background: DeskStyle.accent)
    private static let mutedMenuBarIcon = makeMenuBarIcon(background: DeskStyle.muteAccent)

    private static func makeMenuBarIcon(background: Color) -> NSImage? {
        let badge = Image(systemName: "pianokeys")
            .font(.system(size: 15))
            .foregroundStyle(DeskStyle.background)
            .frame(width: 28, height: 20)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .environment(\.colorScheme, .dark)

        // Render the badge as one image so the menu bar preserves its colors.
        let renderer = ImageRenderer(content: badge)
        renderer.scale = 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }
}
