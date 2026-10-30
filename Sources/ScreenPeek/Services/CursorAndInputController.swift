import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import ServiceManagement

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
            onWindowOpacityChanged?(effectiveWindowOpacity)
        }
    }

    @Published var hideFromDock: Bool {
        didSet {
            UserDefaults.standard.set(hideFromDock, forKey: "ScreenPeek.hideFromDock")
            onHideFromDockChanged?(hideFromDock)
        }
    }

    // MARK: - v1.1 Enhancements: Loupe, PiP Chrome, Click-Through, Snap, HotKeys, Launch at Login
    @Published var loupeMode: LoupeMode {
        didSet {
            UserDefaults.standard.set(loupeMode.rawValue, forKey: "ScreenPeek.loupeMode")
            ScreenCaptureManager.shared.scheduleDynamicConfigUpdate()
        }
    }

    @Published var loupeZoomFactor: CGFloat {
        didSet { UserDefaults.standard.set(Double(loupeZoomFactor), forKey: "ScreenPeek.loupeZoomFactor") }
    }

    @Published var loupeDiameter: CGFloat {
        didSet { UserDefaults.standard.set(Double(loupeDiameter), forKey: "ScreenPeek.loupeDiameter") }
    }

    @Published var autoHideToolbar: Bool {
        didSet {
            UserDefaults.standard.set(autoHideToolbar, forKey: "ScreenPeek.autoHideToolbar")
            onAutoHideToolbarChanged?(autoHideToolbar)
        }
    }

    @Published var isClickThroughEnabled: Bool = false {
        didSet {
            onClickThroughChanged?(effectiveIgnoresMouseEvents)
            onWindowOpacityChanged?(effectiveWindowOpacity)
            onChromeVisibilityChanged?()
            refreshTrackingTimerState()
        }
    }

    @Published var snapToCorners: Bool {
        didSet { UserDefaults.standard.set(snapToCorners, forKey: "ScreenPeek.snapToCorners") }
    }

    @Published var hotKeyPreset: HotKeyModifierPreset {
        didSet {
            UserDefaults.standard.set(hotKeyPreset.rawValue, forKey: "ScreenPeek.hotKeyPreset")
            onHotKeyPresetChanged?(hotKeyPreset)
        }
    }

    @Published var launchAtLogin: Bool = false

    // MARK: - Live Runtime State
    @Published private(set) var isCursorOnTargetDisplay: Bool = false
    @Published private(set) var cursorNormalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var offscreenEdgePosition: CGPoint = CGPoint(x: 0.0, y: 0.5)
    @Published private(set) var cursorPixelPosition: CGPoint = .zero
    @Published private(set) var isMousePressed: Bool = false
    @Published private(set) var isOptionKeyPressed: Bool = false
    @Published private(set) var isBypassClickThroughModifierPressed: Bool = false {
        didSet {
            if oldValue != isBypassClickThroughModifierPressed && isClickThroughEnabled {
                onClickThroughChanged?(effectiveIgnoresMouseEvents)
                onChromeVisibilityChanged?()
            }
        }
    }
    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var activeRipples: [ClickRippleEffect] = []

    @Published var hoverNormalizedPoint: CGPoint? = nil
    @Published var showSettingsPopover: Bool = false
    @Published var hoveredToolbarItem: ToolbarTooltipItem? = nil
    @Published var selectedSettingsTab: SettingsTab = .general
    @Published var isMouseInsidePreviewWindow: Bool = true {
        didSet {
            if oldValue != isMouseInsidePreviewWindow {
                onChromeVisibilityChanged?()
            }
        }
    }
    var isPreviewWindowVisible: Bool = true {
        didSet { refreshTrackingTimerState() }
    }

    var effectiveIgnoresMouseEvents: Bool {
        isClickThroughEnabled && !isBypassClickThroughModifierPressed
    }

    var effectiveWindowOpacity: Double {
        if isClickThroughEnabled && windowOpacity > 0.78 {
            return 0.72
        }
        return windowOpacity
    }

    /// Whether the Magnifier Loupe should currently be rendered
    var isLoupeCurrentlyActive: Bool {
        switch loupeMode {
        case .off:
            return false
        case .holdOption:
            return isOptionKeyPressed
        case .always:
            return true
        }
    }

    /// Active normalized coordinate for the Loupe (prefers hover inside interactive preview, else real cursor on target display)
    var activeLoupeNormalizedPoint: CGPoint? {
        if let hover = hoverNormalizedPoint {
            return hover
        }
        if isCursorOnTargetDisplay {
            return cursorNormalizedPosition
        }
        return nil
    }

    var shouldShowWindowChrome: Bool {
        if !autoHideToolbar { return true }
        if showSettingsPopover { return true }
        if effectiveIgnoresMouseEvents { return false }
        return isMouseInsidePreviewWindow
    }

    // Callbacks for WindowController
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onAspectRatioLockChanged: ((Bool) -> Void)?
    var onWindowOpacityChanged: ((Double) -> Void)?
    var onHideFromDockChanged: ((Bool) -> Void)?
    var onAutoHideToolbarChanged: ((Bool) -> Void)?
    var onClickThroughChanged: ((Bool) -> Void)?
    var onHotKeyPresetChanged: ((HotKeyModifierPreset) -> Void)?
    var onSnapCornerRequested: ((ScreenCorner) -> Void)?
    var onChromeVisibilityChanged: (() -> Void)?

    private var trackingTimer: Timer?
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

        let savedLoupe = UserDefaults.standard.string(forKey: "ScreenPeek.loupeMode") ?? LoupeMode.holdOption.rawValue
        self.loupeMode = LoupeMode(rawValue: savedLoupe) ?? .holdOption

        let savedZoom = UserDefaults.standard.double(forKey: "ScreenPeek.loupeZoomFactor")
        self.loupeZoomFactor = (savedZoom >= 1.5 && savedZoom <= 5.0) ? CGFloat(savedZoom) : 2.8

        let savedDiameter = UserDefaults.standard.double(forKey: "ScreenPeek.loupeDiameter")
        self.loupeDiameter = (savedDiameter >= 100 && savedDiameter <= 260) ? CGFloat(savedDiameter) : 155.0

        if UserDefaults.standard.object(forKey: "ScreenPeek.autoHideToolbar") != nil {
            self.autoHideToolbar = UserDefaults.standard.bool(forKey: "ScreenPeek.autoHideToolbar")
        } else {
            self.autoHideToolbar = false
        }

        if UserDefaults.standard.object(forKey: "ScreenPeek.snapToCorners") != nil {
            self.snapToCorners = UserDefaults.standard.bool(forKey: "ScreenPeek.snapToCorners")
        } else {
            self.snapToCorners = true
        }

        let savedHotKey = UserDefaults.standard.string(forKey: "ScreenPeek.hotKeyPreset") ?? HotKeyModifierPreset.controlOption.rawValue
        self.hotKeyPreset = HotKeyModifierPreset(rawValue: savedHotKey) ?? .controlOption

        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        self.hasAccessibilityPermission = AXIsProcessTrusted()

        startTrackingCursor()
    }

    // MARK: - Launch at Login
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    // MARK: - Battery-Aware Cursor Tracking Timer
    func refreshTrackingTimerState() {
        let shouldRun = (isPreviewWindowVisible && !ScreenCaptureManager.shared.isStoppedByUser)
            || ProjectorOverlayManager.shared.isAudienceLaserEnabled
            || isClickThroughEnabled

        if shouldRun {
            if trackingTimer == nil {
                startTrackingCursor()
            }
        } else {
            stopTrackingCursor()
        }
    }

    func startTrackingCursor() {
        guard trackingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCursorState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    func stopTrackingCursor() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updateCursorState() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()

        // Track modifier keys (Option for Loupe, Option+Command to temporarily grab Click-Through window)
        let flags = NSEvent.modifierFlags
        let optionDown = flags.contains(.option)
        if isOptionKeyPressed != optionDown {
            isOptionKeyPressed = optionDown
        }
        let bypassDown = flags.contains([.option, .command])
        if isBypassClickThroughModifierPressed != bypassDown {
            isBypassClickThroughModifierPressed = bypassDown
        }

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
    func teleportCursor(toNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(targetPt)
        addRipple(at: normalized, isRightClick: false)
    }

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
