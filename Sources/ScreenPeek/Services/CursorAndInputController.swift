import Foundation
import AppKit
import CoreGraphics
import QuartzCore
import ApplicationServices
import ServiceManagement

struct ClickRippleEffect: Identifiable {
    let id = UUID()
    let normalizedPoint: CGPoint
    let isRightClick: Bool
    let createdAt: CFTimeInterval = CACurrentMediaTime()
}

/// Dedicated high-frequency observable store for 60Hz cursor coordinates and click ripples.
/// Isolating this from `CursorAndInputController` prevents SwiftUI header toolbars, menus,
/// and `SettingsWindowView` from re-evaluating their `body` on every mouse movement.
@MainActor
final class CursorTelemetryState: ObservableObject {
    static let shared = CursorTelemetryState()

    @Published fileprivate(set) var isCursorOnTargetDisplay: Bool = false
    @Published fileprivate(set) var cursorNormalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published fileprivate(set) var offscreenEdgePosition: CGPoint = CGPoint(x: 0.0, y: 0.5)
    @Published fileprivate(set) var cursorPixelPosition: CGPoint = .zero
    @Published fileprivate(set) var isMousePressed: Bool = false
    @Published fileprivate(set) var activeRipples: [ClickRippleEffect] = []
    @Published private(set) var hoverNormalizedPoint: CGPoint? = nil

    private init() {}

    var activeLoupeNormalizedPoint: CGPoint? {
        if let hover = hoverNormalizedPoint {
            return hover
        }
        if isCursorOnTargetDisplay {
            return cursorNormalizedPosition
        }
        return nil
    }

    func setHoverNormalizedPoint(_ newPoint: CGPoint?) {
        switch (hoverNormalizedPoint, newPoint) {
        case (nil, nil):
            return
        case let (.some(old), .some(new)):
            if abs(old.x - new.x) < 0.0004 && abs(old.y - new.y) < 0.0004 {
                return
            }
            hoverNormalizedPoint = new
        default:
            hoverNormalizedPoint = newPoint
        }
    }
}

@MainActor
final class CursorAndInputController: ObservableObject {
    static let shared = CursorAndInputController()

    // MARK: - Persisted Settings
    @Published var interactionMode: InteractionMode {
        didSet {
            UserDefaults.standard.set(interactionMode.rawValue, forKey: "ScreenPeek.interactionMode")
            cancelPendingCursorRestore()
        }
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
        didSet {
            UserDefaults.standard.set(returnCursorAfterClick, forKey: "ScreenPeek.returnCursorAfterClick")
            if !returnCursorAfterClick {
                cancelPendingCursorRestore()
            }
        }
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

    @Published var showWindowOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(showWindowOnLaunch, forKey: "ScreenPeek.showWindowOnLaunch")
        }
    }

    // MARK: - Low-Frequency Runtime UI State
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

    // Non-@Published read-only passthroughs for imperative callers (zero SwiftUI invalidation overhead)
    var isCursorOnTargetDisplay: Bool { CursorTelemetryState.shared.isCursorOnTargetDisplay }
    var cursorNormalizedPosition: CGPoint { CursorTelemetryState.shared.cursorNormalizedPosition }

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
    private var pendingOriginCursorPos: CGPoint?
    private var restoreCursorWorkItem: DispatchWorkItem?
    private lazy var hidEventSource: CGEventSource? = CGEventSource(stateID: .hidSystemState)

    // Change-detection caches to guarantee 0% CPU / 0 SwiftUI invalidations when cursor is idle
    private var lastSampledMouseLocation: NSPoint = NSPoint(x: -99_999, y: -99_999)
    private var lastSampledButtons: Int = -1
    private var lastSampledTargetDisplayID: CGDirectDisplayID = 0
    private var lastAXCheckTimestamp: CFTimeInterval = 0

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

        if UserDefaults.standard.object(forKey: "ScreenPeek.showWindowOnLaunch") != nil {
            self.showWindowOnLaunch = UserDefaults.standard.bool(forKey: "ScreenPeek.showWindowOnLaunch")
        } else {
            self.showWindowOnLaunch = true
            UserDefaults.standard.set(true, forKey: "ScreenPeek.showWindowOnLaunch")
        }

        let loginStatus = SMAppService.mainApp.status
        self.launchAtLogin = (loginStatus == .enabled || loginStatus == .requiresApproval)
        self.hasAccessibilityPermission = AXIsProcessTrusted()

        startTrackingCursor()
    }

    // MARK: - Launch at Login
    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        let isRegistered = (status == .enabled || status == .requiresApproval)
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fall through and sync with actual SMAppService status below
        }

        let status = SMAppService.mainApp.status
        if enabled && status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = (status == .enabled || status == .requiresApproval)
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
            MainActor.assumeIsolated {
                self?.updateCursorState()
            }
        }
        timer.tolerance = 0.003
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    func stopTrackingCursor() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updateCursorState() {
        let now = CACurrentMediaTime()
        let telemetry = CursorTelemetryState.shared

        // Throttle TCC Accessibility IPC check to once every 2.5s and only publish if changed
        if now - lastAXCheckTimestamp >= 2.5 {
            lastAXCheckTimestamp = now
            let trusted = AXIsProcessTrusted()
            if hasAccessibilityPermission != trusted {
                hasAccessibilityPermission = trusted
            }
        }

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

        if !telemetry.activeRipples.isEmpty {
            telemetry.activeRipples.removeAll { now - $0.createdAt > 0.55 }
        }

        guard let targetDisplay = ScreenCaptureManager.shared.selectedDisplay else {
            if telemetry.isCursorOnTargetDisplay {
                telemetry.isCursorOnTargetDisplay = false
            }
            return
        }

        let mouseAppKit = NSEvent.mouseLocation
        let buttonsMask = NSEvent.pressedMouseButtons

        // Fast idle short-circuit: skip all math & @Published writes if mouse, buttons, and display haven't changed
        if mouseAppKit == lastSampledMouseLocation
            && buttonsMask == lastSampledButtons
            && targetDisplay.id == lastSampledTargetDisplayID {
            return
        }

        lastSampledMouseLocation = mouseAppKit
        lastSampledButtons = buttonsMask
        lastSampledTargetDisplayID = targetDisplay.id

        let screenFrame = targetDisplay.frame
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }

        let pressed = buttonsMask != 0
        if telemetry.isMousePressed != pressed {
            telemetry.isMousePressed = pressed
        }

        let nx = (mouseAppKit.x - screenFrame.minX) / screenFrame.width
        let nyFromBottom = (mouseAppKit.y - screenFrame.minY) / screenFrame.height
        let nyTopDown = 1.0 - nyFromBottom

        let inside = (nx >= 0.0 && nx <= 1.0 && nyTopDown >= 0.0 && nyTopDown <= 1.0)
        if telemetry.isCursorOnTargetDisplay != inside {
            telemetry.isCursorOnTargetDisplay = inside
        }

        if inside {
            let newNorm = CGPoint(x: nx, y: nyTopDown)
            if abs(newNorm.x - telemetry.cursorNormalizedPosition.x) > 0.0002
                || abs(newNorm.y - telemetry.cursorNormalizedPosition.y) > 0.0002 {
                telemetry.cursorNormalizedPosition = newNorm
            }

            let newPixel = CGPoint(
                x: round(nx * screenFrame.width),
                y: round(nyTopDown * screenFrame.height)
            )
            if newPixel != telemetry.cursorPixelPosition {
                telemetry.cursorPixelPosition = newPixel
            }
        } else {
            let newEdge = CGPoint(
                x: min(max(nx, 0.02), 0.98),
                y: min(max(nyTopDown, 0.02), 0.98)
            )
            if abs(newEdge.x - telemetry.offscreenEdgePosition.x) > 0.0005
                || abs(newEdge.y - telemetry.offscreenEdgePosition.y) > 0.0005 {
                telemetry.offscreenEdgePosition = newEdge
            }
        }
    }

    // MARK: - Accessibility Permission Helper
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let trusted = AXIsProcessTrusted()
        if hasAccessibilityPermission != trusted {
            hasAccessibilityPermission = trusted
        }
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
    private func cancelPendingCursorRestore() {
        restoreCursorWorkItem?.cancel()
        restoreCursorWorkItem = nil
        pendingOriginCursorPos = nil
    }

    private func warpAndScheduleRestore(to targetPt: CGPoint, restoreDelay: TimeInterval) {
        if returnCursorAfterClick {
            if pendingOriginCursorPos == nil {
                pendingOriginCursorPos = CGEvent(source: nil)?.location
            }
            restoreCursorWorkItem?.cancel()
            restoreCursorWorkItem = nil
        } else {
            cancelPendingCursorRestore()
        }

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(targetPt)

        guard returnCursorAfterClick, let originPos = pendingOriginCursorPos else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restoreCursorWorkItem = nil
            self.pendingOriginCursorPos = nil
            CGWarpMouseCursorPosition(originPos)
        }
        restoreCursorWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: item)
    }

    func teleportCursor(toNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        cancelPendingCursorRestore()
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
        let telemetry = CursorTelemetryState.shared
        telemetry.activeRipples.append(ClickRippleEffect(normalizedPoint: clamped, isRightClick: isRightClick))
        telemetry.cursorNormalizedPosition = clamped
    }

    func performRemoteClick(atNormalized normalized: CGPoint, clickCount: Int = 1, isRightClick: Bool = false) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)

        addRipple(at: normalized, isRightClick: isRightClick)

        guard AXIsProcessTrusted() else {
            cancelPendingCursorRestore()
            CGAssociateMouseAndMouseCursorPosition(1)
            CGWarpMouseCursorPosition(targetPt)
            requestAccessibilityPermission()
            return
        }

        warpAndScheduleRestore(to: targetPt, restoreDelay: 0.04)

        let source = hidEventSource
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
    }

    func beginRemoteDrag(atNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay else { return }
        guard AXIsProcessTrusted() else {
            teleportCursor(toNormalized: normalized)
            requestAccessibilityPermission()
            return
        }

        if dragSavedLaptopCursorQuartz == nil {
            dragSavedLaptopCursorQuartz = pendingOriginCursorPos ?? CGEvent(source: nil)?.location
        }
        cancelPendingCursorRestore()

        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        addRipple(at: normalized, isRightClick: false)

        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(targetPt)

        if let downEvent = CGEvent(mouseEventSource: hidEventSource, mouseType: .leftMouseDown, mouseCursorPosition: targetPt, mouseButton: .left) {
            downEvent.post(tap: .cghidEventTap)
        }
    }

    func updateRemoteDrag(atNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay, AXIsProcessTrusted() else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        CGWarpMouseCursorPosition(targetPt)

        if let dragEvent = CGEvent(mouseEventSource: hidEventSource, mouseType: .leftMouseDragged, mouseCursorPosition: targetPt, mouseButton: .left) {
            dragEvent.post(tap: .cghidEventTap)
        }
    }

    func endRemoteDrag(atNormalized normalized: CGPoint) {
        guard let display = ScreenCaptureManager.shared.selectedDisplay, AXIsProcessTrusted() else { return }
        let targetPt = quartzPoint(forNormalized: normalized, in: display)
        CGWarpMouseCursorPosition(targetPt)

        if let upEvent = CGEvent(mouseEventSource: hidEventSource, mouseType: .leftMouseUp, mouseCursorPosition: targetPt, mouseButton: .left) {
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
        warpAndScheduleRestore(to: targetPt, restoreDelay: 0.06)

        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: hidEventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY * 3),
            wheel2: Int32(deltaX * 3),
            wheel3: 0
        ) {
            scrollEvent.location = targetPt
            scrollEvent.post(tap: .cghidEventTap)
        }
    }
}
