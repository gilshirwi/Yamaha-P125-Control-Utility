import AppKit
import SwiftUI
import P125Core

struct CompactControls: View {
    @ObservedObject var piano: PianoModel
    let prepareToOpenControls: () -> Void
    @Environment(\.openWindow) private var openWindow
    private let mainVolume = ParameterKey(.volume, 0)

    var body: some View {
        let muted = piano.isMuted(mainVolume.index)
        let applying = piano.desired[mainVolume] != nil
        let available = piano.supported(mainVolume) && !applying
        let actionColor = muted ? DeskStyle.muteAccent : DeskStyle.accent
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ControlDeskWordmark(size: 27)
                Spacer()
                ControlDeskConnectionBadge(piano: piano)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Main").font(.system(size: 23, weight: .light))
                    Text("PRIMARY VOICE")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    piano.toggleMute(mainVolume.index)
                } label: {
                    Label(muted ? "Unmute Main" : "Mute Main",
                          systemImage: muted ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(actionColor)
                        .background(actionColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(actionColor.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .opacity(available ? 1 : 0.45)

                Text(applying ? "Applying to piano…" : "USB MIDI stays active when Main is muted.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .panel()

            OpenAtLoginToggle()
            Rectangle().fill(DeskStyle.line).frame(height: 1)

            HStack {
                Button("Open Full Controls", systemImage: "slider.vertical.3") {
                    prepareToOpenControls()
                    openWindow(value: ControlWindow.main)
                    NSApp.activate()
                }
                Spacer()
                Button("Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
                .accessibilityLabel("Quit P-125 Control")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 284)
        .foregroundStyle(DeskStyle.text)
        .background(DeskStyle.background)
        .tint(DeskStyle.accent)
        .preferredColorScheme(.dark)
    }
}
