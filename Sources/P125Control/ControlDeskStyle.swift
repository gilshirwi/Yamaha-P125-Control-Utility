import SwiftUI

enum DeskStyle {
    static let background = Color(red: 0.075, green: 0.085, blue: 0.10)
    static let panel = Color(red: 0.115, green: 0.127, blue: 0.145)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 0.49, green: 0.86, blue: 0.76)
    static let muteAccent = Color.orange
    static let text = Color(red: 0.92, green: 0.93, blue: 0.91)
}

struct ControlDeskWordmark: View {
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("P").foregroundColor(DeskStyle.accent) + Text("125"))
                .font(.system(size: size, weight: .light, design: .rounded))
            Text("CONTROL DESK")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.6)
                .foregroundStyle(.secondary)
        }
    }
}

struct ControlDeskConnectionBadge: View {
    @ObservedObject var piano: PianoModel

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(piano.verified ? DeskStyle.accent : .orange)
                .frame(width: 6, height: 6)
            Text(status).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(0.04), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var status: String {
        if piano.loading { return "Reading settings…" }
        if piano.connecting { return "Connecting…" }
        return piano.verified ? "Piano connected" : "Piano offline"
    }
}

extension View {
    func panel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return background(DeskStyle.panel, in: shape)
            .overlay(shape.stroke(DeskStyle.line, lineWidth: 1))
    }
}
