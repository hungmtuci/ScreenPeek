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
        let height = containerSize.height
        let width = height * aspectRatio
        let x = (containerSize.width - width) * 0.5
        return CGRect(x: x, y: 0, width: width, height: height)
    } else {
        let width = containerSize.width
        let height = width / aspectRatio
        let y = (containerSize.height - height) * 0.5
        return CGRect(x: 0, y: y, width: width, height: height)
    }
}

struct VideoSurfaceRepresentable: NSViewRepresentable {
    let aspectRatio: CGFloat
    let interactionMode: InteractionMode
    let isLoupeActive: Bool
    let loupeNormalizedPoint: CGPoint?
    let loupeZoomFactor: CGFloat
    let loupeDiameter: CGFloat
    let loupeBorderColor: NSColor

    func makeNSView(context: Context) -> InteractiveVideoNSView {
        let view = InteractiveVideoNSView()
        view.aspectRatio = aspectRatio
        view.interactionMode = interactionMode
        view.onHoverChanged = { pt in
            Task { @MainActor in
                CursorAndInputController.shared.hoverNormalizedPoint = pt
            }
        }

        ScreenCaptureManager.shared.onFrameHandler = { [weak view] surfaceObj in
            view?.updateFrame(surfaceObj)
        }

        view.updateLoupe(
            isActive: isLoupeActive,
            normalizedPoint: loupeNormalizedPoint,
            zoomFactor: loupeZoomFactor,
            diameter: loupeDiameter,
            borderColor: loupeBorderColor
        )
        return view
    }

    func updateNSView(_ nsView: InteractiveVideoNSView, context: Context) {
        nsView.aspectRatio = aspectRatio
        nsView.interactionMode = interactionMode
        nsView.updateLoupe(
            isActive: isLoupeActive,
            normalizedPoint: loupeNormalizedPoint,
            zoomFactor: loupeZoomFactor,
            diameter: loupeDiameter,
            borderColor: loupeBorderColor
        )
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
    private let loupeShadowLayer = CALayer()
    private let loupeMaskLayer = CALayer()
    private let loupeImageLayer = CALayer()
    private let loupeCrosshairH = CALayer()
    private let loupeCrosshairV = CALayer()

    private var trackingArea: NSTrackingArea?
    private var mouseDownPointInView: NSPoint?
    private var mouseDownNormalized: CGPoint?
    private var isDraggingRemote: Bool = false

    private var lastLoupeActive: Bool = false
    private var lastLoupeNorm: CGPoint? = nil
    private var lastLoupeZoom: CGFloat = 2.8
    private var lastLoupeDiameter: CGFloat = 155.0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1.0).cgColor

        let noAnim: [String: CAAction] = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "hidden": NSNull(),
            "borderColor": NSNull()
        ]

        videoLayer.contentsGravity = .resizeAspect
        videoLayer.magnificationFilter = .trilinear
        videoLayer.minificationFilter = .trilinear
        videoLayer.actions = noAnim
        layer?.addSublayer(videoLayer)

        // Zero-Copy Magnifier Loupe Layer Hierarchy
        loupeShadowLayer.shadowColor = NSColor.black.cgColor
        loupeShadowLayer.shadowOpacity = 0.65
        loupeShadowLayer.shadowRadius = 10
        loupeShadowLayer.shadowOffset = CGSize(width: 0, height: 4)
        loupeShadowLayer.isHidden = true
        loupeShadowLayer.actions = noAnim

        loupeMaskLayer.masksToBounds = true
        loupeMaskLayer.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        loupeMaskLayer.borderWidth = 2.5
        loupeMaskLayer.borderColor = NSColor.systemYellow.cgColor
        loupeMaskLayer.actions = noAnim

        loupeImageLayer.contentsGravity = .resize
        loupeImageLayer.magnificationFilter = .trilinear
        loupeImageLayer.minificationFilter = .trilinear
        loupeImageLayer.actions = noAnim
        loupeMaskLayer.addSublayer(loupeImageLayer)

        // Subtle center reticle inside the Loupe
        loupeCrosshairH.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        loupeCrosshairH.shadowColor = NSColor.black.cgColor
        loupeCrosshairH.shadowOpacity = 0.9
        loupeCrosshairH.shadowRadius = 1
        loupeCrosshairH.actions = noAnim

        loupeCrosshairV.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        loupeCrosshairV.shadowColor = NSColor.black.cgColor
        loupeCrosshairV.shadowOpacity = 0.9
        loupeCrosshairV.shadowRadius = 1
        loupeCrosshairV.actions = noAnim

        loupeMaskLayer.addSublayer(loupeCrosshairH)
        loupeMaskLayer.addSublayer(loupeCrosshairV)
        loupeShadowLayer.addSublayer(loupeMaskLayer)
        layer?.addSublayer(loupeShadowLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        layoutLoupeLayers()
        CATransaction.commit()

        ScreenCaptureManager.shared.notifyPreviewWindowResized(bounds.size)
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
        return true
    }

    func updateFrame(_ surfaceObj: AnyObject?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.contents = surfaceObj
        loupeImageLayer.contents = surfaceObj
        CATransaction.commit()
    }

    func updateLoupe(
        isActive: Bool,
        normalizedPoint: CGPoint?,
        zoomFactor: CGFloat,
        diameter: CGFloat,
        borderColor: NSColor
    ) {
        lastLoupeActive = isActive
        lastLoupeNorm = normalizedPoint
        lastLoupeZoom = zoomFactor
        lastLoupeDiameter = diameter

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        loupeMaskLayer.borderColor = borderColor.cgColor
        layoutLoupeLayers()
        CATransaction.commit()
    }

    private func layoutLoupeLayers() {
        guard lastLoupeActive,
              let norm = lastLoupeNorm,
              loupeImageLayer.contents != nil,
              bounds.width > 40,
              bounds.height > 40 else {
            loupeShadowLayer.isHidden = true
            return
        }

        let fitted = aspectFittedRect(aspectRatio: aspectRatio, in: bounds.size)
        guard fitted.width > 10, fitted.height > 10 else {
            loupeShadowLayer.isHidden = true
            return
        }

        let diameter = min(lastLoupeDiameter, min(bounds.width, bounds.height) * 0.62)
        let radius = diameter * 0.5
        let zoom = max(lastLoupeZoom, 1.5)

        let cursorX = fitted.minX + norm.x * fitted.width
        let cursorY = fitted.minY + norm.y * fitted.height

        // Position Loupe above cursor by default; flip below if near top edge
        let margin: CGFloat = 8
        let verticalGap: CGFloat = 24
        let loupeCenterY: CGFloat
        if cursorY - radius - verticalGap >= margin {
            loupeCenterY = cursorY - radius - verticalGap
        } else {
            loupeCenterY = min(cursorY + radius + verticalGap, bounds.height - radius - margin)
        }
        let loupeCenterX = min(max(cursorX, radius + margin), bounds.width - radius - margin)

        loupeShadowLayer.isHidden = false
        loupeShadowLayer.frame = CGRect(
            x: loupeCenterX - radius,
            y: loupeCenterY - radius,
            width: diameter,
            height: diameter
        )
        loupeMaskLayer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        loupeMaskLayer.cornerRadius = radius

        let zoomedW = fitted.width * zoom
        let zoomedH = fitted.height * zoom
        loupeImageLayer.frame = CGRect(
            x: radius - norm.x * zoomedW,
            y: radius - norm.y * zoomedH,
            width: zoomedW,
            height: zoomedH
        )

        let crossLen: CGFloat = 14
        loupeCrosshairH.frame = CGRect(x: radius - crossLen * 0.5, y: radius - 0.75, width: crossLen, height: 1.5)
        loupeCrosshairV.frame = CGRect(x: radius - 0.75, y: radius - crossLen * 0.5, width: 1.5, height: crossLen)
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
        // When toolbar is auto-hidden in Live View mode, allow dragging window by background on single click drag!
        guard let norm = normalizedPoint(for: event) else {
            super.mouseDown(with: event)
            return
        }

        switch interactionMode {
        case .liveView:
            if event.clickCount >= 2 {
                CursorAndInputController.shared.teleportCursor(toNormalized: norm)
            } else {
                window?.performDrag(with: event)
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
