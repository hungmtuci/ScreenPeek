import SwiftUI
import AppKit

/// Allows dragging an `NSWindow` with `.fullSizeContentView` from any SwiftUI header background region.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableHeaderNSView {
        DraggableHeaderNSView()
    }

    func updateNSView(_ nsView: DraggableHeaderNSView, context: Context) {}
}

final class DraggableHeaderNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Renders an Apple System Settings–style rounded-square colorful icon badge.
struct SystemSettingsIconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.92),
                            color
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.6)
                )
                .shadow(color: color.opacity(0.25), radius: 2, x: 0, y: 1)

            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Renders physical macOS keyboard keycaps (e.g. `⌃` `⌥` `M`).
struct MacKeycapGroup: View {
    let keys: [String]
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 2.5 : 3.5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(minWidth: compact ? 17 : 21, minHeight: compact ? 17 : 20)
                    .padding(.horizontal, compact ? 3 : 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.16), radius: 0.6, x: 0, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous)
                            .stroke(Color.primary.opacity(0.16), lineWidth: 0.7)
                    )
            }
        }
    }
}
