import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

struct ClickRippleEffect: Identifiable {
    let id = UUID()
    let normalizedPoint: CGPoint
    let isRightClick: Bool
    let createdAt: Date = Date()
}

@MainActor
final class CursorAndInputController: ObservableObject {
    static let shared = CursorAndInputController()

    // MARK: - Persisted Settings
    @Published var interactionMode: InteractionMode {
        didSet { UserDefaults.standard.set(interactionMode.rawValue, forKey: "ScreenPeek.interactionMode") }
    }

    @Published var isAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "ScreenPeek.isAlwaysOnTop")
            onAlwaysOnTopChanged?(isAlwaysOnTop)
        }
    }

    @Published var isAspectRatioLocked: Bool {
        didSet {
            UserDefaults.standard.set(isAspectRatioLocked, forKey: "ScreenPeek.isAspectRatioLocked")
            onAspectRatioLockChanged?(isAspectRatioLocked)
        }
    }

    @Published var showCursorHighlight: Bool {
        didSet { UserDefaults.standard.set(showCursorHighlight, forKey: "ScreenPeek.showCursorHighlight") }
    }

    @Published var cursorHighlightSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(cursorHighlightSize), forKey: "ScreenPeek.cursorHighlightSize") }
    }

    @Published var cursorHighlightColor: CursorHighlightColor {
        didSet { UserDefaults.standard.set(cursorHighlightColor.rawValue, forKey: "ScreenPeek.cursorHighlightColor") }
    }

    @Published var returnCursorAfterClick: Bool {
        didSet { UserDefaults.standard.set(returnCursorAfterClick, forKey: "ScreenPeek.returnCursorAfterClick") }
    }

    @Published var windowOpacity: Double {
        didSet {
            UserDefaults.standard.set(windowOpacity, forKey: "ScreenPeek.windowOpacity")
            onWindowOpacityChanged?(windowOpacity)
        }
    }

    @Published var hideFromDock: Bool {
        didSet {
            UserDefaults.standard.set(hideFromDock, forKey: "ScreenPeek.hideFromDock")
            onHideFromDockChanged?(hideFromDock)
        }
    }

    // MARK: - Live Cursor State on Target Display
    @Published private(set) var isCursorOnTargetDisplay: Bool = false
    /// Normalized (0...1, 0...1) from top-left of target display
    @Published private(set) var cursorNormalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// Clamped edge indicator (0...1, 0...1) when cursor is outside target display
    @Published private(set) var offscreenEdgePosition: CGPoint = CGPoint(x: 0.0, y: 0.5)
    @Published private(set) var cursorPixelPosition: CGPoint = .zero
    @Published private(set) var isMousePressed: Bool = false
    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var activeRipples: [ClickRippleEffect] = []
    @Published var hoverNormalizedPoint: CGPoint? = nil
    @Published var showSettingsPopover: Bool = false
    @Published var hoveredToolbarItem: ToolbarTooltipItem? = nil

    // Callbacks for WindowController
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onAspectRatioLockChanged: ((Bool) -> Void)?
    var onWindowOpacityChanged: ((Double) -> Void)?
    var onHideFromDockChanged: ((Bool) -> Void)?

    private var trackingTimer: Timer?
    private var isPerformingRemoteAction: Bool = false
    private var dragSavedLaptopCursorQuartz: CGPoint?

    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "ScreenPeek.interactionMode") ?? InteractionMode.liveView.rawValue
        self.interactionMode = InteractionMode(rawValue: savedMode) ?? .liveView

        if UserDefaults.standard.object(forKey: "ScreenPeek.isAlwaysOnTop") != nil {
            self.isAlwaysOnTop = UserDefaults.standard.bool(forKey: "ScreenPeek.isAlwaysOnTop")
        } else {
            self.isAlwaysOnTop = true
        }

        if UserDefaults.standard.object(forKey: "ScreenPeek.isAspectRatioLocked") != nil {
            self.isAspectRatioLocked = UserDefaults.standard.bool(forKey: "ScreenPeek.isAspectRatioLocked")
        } else {
            self.isAspectRatioLocked = true
        }

        if UserDefaults.standard.object(forKey: "ScreenPeek.showCursorHighlight") != nil {
            self.showCursorHighlight = UserDefaults.standard.bool(forKey: "ScreenPeek.showCursorHighlight")
        } else {
            self.showCursorHighlight = true
        }

        let savedSize = UserDefaults.standard.double(forKey: "ScreenPeek.cursorHighlightSize")
        self.cursorHighlightSize = savedSize > 10 ? CGFloat(savedSize) : 38.0

        let savedColor = UserDefaults.standard.string(forKey: "ScreenPeek.cursorHighlightColor") ?? CursorHighlightColor.yellow.rawValue
        self.cursorHighlightColor = CursorHighlightColor(rawValue: savedColor) ?? .yellow

        if UserDefaults.standard.object(forKey: "ScreenPeek.returnCursorAfterClick") != nil {
            self.returnCursorAfterClick = UserDefaults.standard.bool(forKey: "ScreenPeek.returnCursorAfterClick")
        } else {
            self.returnCursorAfterClick = true
        }

        let savedOpacity = UserDefaults.standard.double(forKey: "ScreenPeek.windowOpacity")
        self.windowOpacity = (savedOpacity >= 0.4 && savedOpacity <= 1.0) ? savedOpacity : 1.0

        if UserDefaults.standard.object(forKey: "ScreenPeek.hideFromDock") != nil {
            self.hideFromDock = UserDefaults.standard.bool(forKey: "ScreenPeek.hideFromDock")
        } else {
            self.hideFromDock = true
            UserDefaults.standard.set(true, forKey: "ScreenPeek.hideFromDock")
        }

        self.hasAccessibilityPermission = AXIsProcessTrusted()
        startTrackingCursor()
    }

    func startTrackingCursor() {
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCursorState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func updateCursorState() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()

        // Clean up expired ripple effects (> 0.55s)
        if !activeRipples.isEmpty {
            let now = Date()
            activeRipples.removeAll { now.timeIntervalSince($0.createdAt) > 0.55 }
        }

        guard let targetDisplay = ScreenCaptureManager.shared.selectedDisplay else {
            isCursorOnTargetDisplay = false
            return
        }

        let mouseAppKit = NSEvent.mouseLocation
        let screenFrame = targetDisplay.frame
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }

        let nx = (mouseAppKit.x - screenFrame.minX) / screenFrame.width
        let nyFromBottom = (mouseAppKit.y - screenFrame.minY) / screenFrame.height
        let nyTopDown = 1.0 - nyFromBottom

        let pressed = NSEvent.pressedMouseButtons != 0
        if isMousePressed != pressed {
            isMousePressed = pressed
        }

        let inside = (nx >= 0.0 && nx <= 1.0 && nyTopDown >= 0.0 && nyTopDown <= 1.0)
        if inside {
            isCursorOnTargetDisplay = true
            cursorNormalizedPosition = CGPoint(x: nx, y: nyTopDown)
            cursorPixelPosition = CGPoint(
                x: round(nx * screenFrame.width),
                y: round(nyTopDown * screenFrame.height)
            )
        } else {
            isCursorOnTargetDisplay = false
            offscreenEdgePosition = CGPoint(
                x: min(max(nx, 0.02), 0.98),
                y: min(max(nyTopDown, 0.02), 0.98)
            )
        }
    }

    // MARK: - Accessibility Permission Helper
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Coordinate Conversion
    func quartzPoint(forNormalized normalized: CGPoint, in display: DisplayInfo) -> CGPoint {
        let clampedX = min(max(normalized.x, 0.0), 1.0)
        let clampedY = min(max(normalized.y, 0.0), 1.0)
        let bounds = display.quartzBounds
        return CGPoint(
            x: bounds.minX + clampedX * bounds.width,
            y: bounds.minY + clampedY * bounds.height
        )
    }

    // MARK: - Teleport Cursor
    /// Warps the physical cursor to the specified normalized position (0...1, 0...1) on the target display.
    func teleportCursor(toNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(targetPt)
        addRipple(at: normalized, isRightClick: false)
    }

    /// Warps the physical cursor to the center of the target display.
    func teleportCursorToCenterOfTargetDisplay() {
        teleportCursor(toNormalized: CGPoint(x: 0.5, y: 0.5))
    }

    // MARK: - Interactive Remote Actions
    func addRipple(at normalized: CGPoint, isRightClick: Bool) {
        let clamped = CGPoint(
            x: min(max(normalized.x, 0.0), 1.0),
            y: min(max(normalized.y, 0.0), 1.0)
        )
        activeRipples.append(ClickRippleEffect(normalizedPoint: clamped, isRightClick: isRightClick))
        cursorNormalizedPosition = clamped
    }

    func performRemoteClick(atNormalized normalized: CGPoint, clickCount: Int = 1, isRightClick: Bool = false) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        let savedPos = CGEvent(source: nil)?.location

        addRipple(at: normalized, isRightClick: isRightClick)

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(targetPt)

        guard AXIsProcessTrusted() else {
            // Without Accessibility permission, warping the cursor still works; prompt user once if they want auto-click
            requestAccessibilityPermission()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let button: CGMouseButton = isRightClick ? .right : .left
        let downType: CGEventType = isRightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRightClick ? .rightMouseUp : .leftMouseUp

        for currentClick in 1...max(clickCount, 1) {
            if let downEvent = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: targetPt, mouseButton: button),
               let upEvent = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: targetPt, mouseButton: button) {
                downEvent.setIntegerValueField(.mouseEventClickState, value: Int64(currentClick))
                upEvent.setIntegerValueField(.mouseEventClickState, value: Int64(currentClick))
                downEvent.post(tap: .cghidEventTap)
                upEvent.post(tap: .cghidEventTap)
            }
        }

        if returnCursorAfterClick, let savedPos {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                CGWarpMouseCursorPosition(savedPos)
            }
        }
    }

    func beginRemoteDrag(atNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        guard AXIsProcessTrusted() else {
            teleportCursor(toNormalized: normalized)
            requestAccessibilityPermission()
            return
        }

        if dragSavedLaptopCursorQuartz == nil {
            dragSavedLaptopCursorQuartz = CGEvent(source: nil)?.location
        }

        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        addRipple(at: normalized, isRightClick: false)

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(targetPt)

        let source = CGEventSource(stateID: .hidSystemState)
        if let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: targetPt, mouseButton: .left) {
            downEvent.post(tap: .cghidEventTap)
        }
    }

    func updateRemoteDrag(atNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay, AXIsProcessTrusted() else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        CGWarpMouseCursorPosition(targetPt)

        let source = CGEventSource(stateID: .hidSystemState)
        if let dragEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: targetPt, mouseButton: .left) {
            dragEvent.post(tap: .cghidEventTap)
        }
    }

    func endRemoteDrag(atNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay, AXIsProcessTrusted() else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        CGWarpMouseCursorPosition(targetPt)

        let source = CGEventSource(stateID: .hidSystemState)
        if let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: targetPt, mouseButton: .left) {
            upEvent.post(tap: .cghidEventTap)
        }

        let savedPos = dragSavedLaptopCursorQuartz
        dragSavedLaptopCursorQuartz = nil
        if returnCursorAfterClick, let savedPos {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                CGWarpMouseCursorPosition(savedPos)
            }
        }
    }

    func performRemoteScroll(atNormalized normalized: CGPoint, deltaX: CGFloat, deltaY: CGFloat) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        guard AXIsProcessTrusted() else { return }

        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        let savedPos = CGEvent(source: nil)?.location

        CGWarpMouseCursorPosition(targetPt)

        let source = CGEventSource(stateID: .hidSystemState)
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY * 3),
            wheel2: Int32(deltaX * 3),
            wheel3: 0
        ) {
            scrollEvent.location = targetPt
            scrollEvent.post(tap: .cghidEventTap)
        }

        if returnCursorAfterClick, let savedPos {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                CGWarpMouseCursorPosition(savedPos)
            }
        }
    }
}
