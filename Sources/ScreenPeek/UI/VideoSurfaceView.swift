import SwiftUI
import AppKit
import QuartzCore

/// Calculates the exact aspect-fitted rectangle of the display image inside a container of size `containerSize`.
func aspectFittedRect(aspectRatio: CGFloat, in containerSize: CGSize) -> CGRect {
    guard containerSize.width > 0, containerSize.height > 0, aspectRatio > 0 else {
        return CGRect(origin: .zero, size: containerSize)
    }
    let containerAspect = containerSize.width / containerSize.height
    if containerAspect > aspectRatio {
        // Pillarboxed (bars on left/right)
        let height = containerSize.height
        let width = height * aspectRatio
        let x = (containerSize.width - width) * 0.5
        return CGRect(x: x, y: 0, width: width, height: height)
    } else {
        // Letterboxed (bars on top/bottom)
        let width = containerSize.width
        let height = width / aspectRatio
        let y = (containerSize.height - height) * 0.5
        return CGRect(x: 0, y: y, width: width, height: height)
    }
}

struct VideoSurfaceRepresentable: NSViewRepresentable {
    let aspectRatio: CGFloat
    let interactionMode: InteractionMode

    func makeNSView(context: Context) -> InteractiveVideoNSView {
        let view = InteractiveVideoNSView()
        view.aspectRatio = aspectRatio
        view.interactionMode = interactionMode
        view.onHoverChanged = { pt in
            Task { @MainActor in
                CursorAndInputController.shared.hoverNormalizedPoint = pt
            }
        }

        // Hook up zero-copy IOSurface frame receiver
        ScreenCaptureManager.shared.onFrameHandler = { [weak view] surfaceObj in
            view?.updateFrame(surfaceObj)
        }

        return view
    }

    func updateNSView(_ nsView: InteractiveVideoNSView, context: Context) {
        nsView.aspectRatio = aspectRatio
        nsView.interactionMode = interactionMode
    }
}

final class InteractiveVideoNSView: NSView {
    var aspectRatio: CGFloat = 16.0 / 9.0 {
        didSet {
            if abs(oldValue - aspectRatio) > 0.001 {
                needsLayout = true
            }
        }
    }
    var interactionMode: InteractionMode = .liveView
    var onHoverChanged: ((CGPoint?) -> Void)?

    private let videoLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var mouseDownPointInView: NSPoint?
    private var mouseDownNormalized: CGPoint?
    private var isDraggingRemote: Bool = false

    override var isFlipped: Bool { true } // Top-left origin (0,0) for intuitive screen mapping!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1.0).cgColor

        videoLayer.contentsGravity = .resizeAspect
        videoLayer.magnificationFilter = .trilinear
        videoLayer.minificationFilter = .trilinear
        videoLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
        layer?.addSublayer(videoLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true // Respond immediately on first click without needing an extra click to activate window
    }

    func updateFrame(_ surfaceObj: AnyObject?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.contents = surfaceObj
        CATransaction.commit()
    }

    private func normalizedPoint(for event: NSEvent) -> CGPoint? {
        let localPt = convert(event.locationInWindow, from: nil)
        let fitted = aspectFittedRect(aspectRatio: aspectRatio, in: bounds.size)
        guard fitted.width > 1, fitted.height > 1 else { return nil }
        guard fitted.contains(localPt) else { return nil }

        let nx = (localPt.x - fitted.minX) / fitted.width
        let ny = (localPt.y - fitted.minY) / fitted.height
        return CGPoint(
            x: min(max(nx, 0.0), 1.0),
            y: min(max(ny, 0.0), 1.0)
        )
    }

    // MARK: - Mouse Events
    override func mouseMoved(with event: NSEvent) {
        let norm = normalizedPoint(for: event)
        onHoverChanged?(norm)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let norm = normalizedPoint(for: event) else {
            super.mouseDown(with: event)
            return
        }

        switch interactionMode {
        case .liveView:
            // In Live View mode: Double-clicking anywhere in the preview teleports the physical cursor to that spot on the external display!
            if event.clickCount >= 2 {
                CursorAndInputController.shared.teleportCursor(toNormalized: norm)
            }
        case .interactive:
            mouseDownPointInView = convert(event.locationInWindow, from: nil)
            mouseDownNormalized = norm
            isDraggingRemote = false
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard interactionMode == .interactive else {
            super.mouseDragged(with: event)
            return
        }
        guard let norm = normalizedPoint(for: event) else { return }
        onHoverChanged?(norm)

        let currentPt = convert(event.locationInWindow, from: nil)
        if !isDraggingRemote, let startPt = mouseDownPointInView {
            let dist = hypot(currentPt.x - startPt.x, currentPt.y - startPt.y)
            if dist >= 4.0 {
                isDraggingRemote = true
                CursorAndInputController.shared.beginRemoteDrag(atNormalized: mouseDownNormalized ?? norm)
            }
        }

        if isDraggingRemote {
            CursorAndInputController.shared.updateRemoteDrag(atNormalized: norm)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard interactionMode == .interactive else {
            super.mouseUp(with: event)
            return
        }

        let norm = normalizedPoint(for: event) ?? mouseDownNormalized
        defer {
            mouseDownPointInView = nil
            mouseDownNormalized = nil
            isDraggingRemote = false
        }

        guard let targetNorm = norm else { return }

        if isDraggingRemote {
            CursorAndInputController.shared.endRemoteDrag(atNormalized: targetNorm)
        } else {
            // Option-click in Interactive Mode teleports cursor and leaves it on external screen
            if event.modifierFlags.contains(.option) {
                CursorAndInputController.shared.teleportCursor(toNormalized: targetNorm)
            } else {
                CursorAndInputController.shared.performRemoteClick(
                    atNormalized: targetNorm,
                    clickCount: max(event.clickCount, 1),
                    isRightClick: false
                )
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let norm = normalizedPoint(for: event) else {
            super.rightMouseDown(with: event)
            return
        }

        switch interactionMode {
        case .liveView:
            // In Live View mode, right-click also offers quick teleport
            CursorAndInputController.shared.teleportCursor(toNormalized: norm)
        case .interactive:
            CursorAndInputController.shared.performRemoteClick(
                atNormalized: norm,
                clickCount: 1,
                isRightClick: true
            )
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard interactionMode == .interactive,
              let norm = normalizedPoint(for: event) else {
            super.scrollWheel(with: event)
            return
        }

        CursorAndInputController.shared.performRemoteScroll(
            atNormalized: norm,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY
        )
    }
}
