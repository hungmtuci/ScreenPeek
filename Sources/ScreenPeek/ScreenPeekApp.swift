import SwiftUI
import AppKit
import Carbon

@main
struct ScreenPeekApp: App {
    @NSApplicationDelegateAdaptor(ScreenPeekAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class ScreenPeekAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static weak var shared: ScreenPeekAppDelegate?

    private var statusItem: NSStatusItem!
    private var previewWindow: NSWindow?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private var lastLaptopCursorPoint: CGPoint?
    private var lastExternalCursorNormalized: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var snapSettleWorkItem: DispatchWorkItem?
    private var isProgrammaticWindowMove: Bool = false

    var previewWindowScreenFrame: CGRect? {
        previewWindow?.screen?.frame
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        let capture = ScreenCaptureManager.shared
        let controller = CursorAndInputController.shared

        applyDockVisibilityPolicy(hideFromDock: controller.hideFromDock)

        controller.onAlwaysOnTopChanged = { [weak self] isOnTop in
            self?.applyWindowLevel(isOnTop: isOnTop)
        }
        controller.onAspectRatioLockChanged = { [weak self] locked in
            if locked {
                self?.snapWindowToDisplayAspectRatio(animated: true)
            }
        }
        controller.onWindowOpacityChanged = { [weak self] opacity in
            self?.previewWindow?.alphaValue = CGFloat(opacity)
        }
        controller.onHideFromDockChanged = { [weak self] hide in
            self?.applyDockVisibilityPolicy(hideFromDock: hide)
        }
        controller.onAutoHideToolbarChanged = { [weak self] autoHide in
            self?.applyWindowTitlebarStyle(autoHide: autoHide)
            if controller.isAspectRatioLocked {
                self?.snapWindowToDisplayAspectRatio(animated: true)
            }
        }
        controller.onClickThroughChanged = { [weak self] ignoresMouse in
            self?.previewWindow?.ignoresMouseEvents = ignoresMouse
        }
        controller.onHotKeyPresetChanged = { [weak self] preset in
            self?.reRegisterGlobalHotKeys(for: preset)
        }
        controller.onSnapCornerRequested = { [weak self] corner in
            self?.snapWindow(to: corner, animated: true)
        }
        capture.onSelectedDisplayChanged = { [weak self] _ in
            if CursorAndInputController.shared.isAspectRatioLocked {
                self?.snapWindowToDisplayAspectRatio(animated: true)
            }
            self?.updateWindowTitle()
        }

        setupStatusBarMenu()
        installHotKeyEventHandlerIfNeeded()
        reRegisterGlobalHotKeys(for: controller.hotKeyPreset)
        showPreviewWindow()

        capture.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreviewWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applyDockVisibilityPolicy(hideFromDock: Bool) {
        let wasVisible = previewWindow?.isVisible ?? false
        NSApp.setActivationPolicy(hideFromDock ? .accessory : .regular)
        if wasVisible {
            DispatchQueue.main.async { [weak self] in
                guard let self, let win = self.previewWindow else { return }
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Preview Window Management
    func showPreviewWindow() {
        let controller = CursorAndInputController.shared

        if previewWindow == nil {
            let aspect = ScreenCaptureManager.shared.selectedDisplay?.aspectRatio ?? (16.0 / 9.0)
            let initialWidth: CGFloat = 620
            let initialVideoHeight = round(initialWidth / aspect)
            let initialHeight = initialVideoHeight + PreviewWindowView.chromeHeight

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.minSize = NSSize(width: 420, height: 240)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.alphaValue = CGFloat(controller.effectiveWindowOpacity)
            win.ignoresMouseEvents = controller.effectiveIgnoresMouseEvents
            win.contentView = NSHostingView(rootView: PreviewWindowView())

            if let mainScreen = NSScreen.screens.first {
                let visible = mainScreen.visibleFrame
                let originX = visible.maxX - initialWidth - 20
                let originY = visible.minY + 24
                win.setFrameOrigin(NSPoint(x: max(visible.minX + 16, originX), y: max(visible.minY + 16, originY)))
            } else {
                win.center()
            }

            self.previewWindow = win
            updateWindowTitle()
            applyWindowLevel(isOnTop: controller.isAlwaysOnTop)
            applyWindowTitlebarStyle(autoHide: controller.autoHideToolbar)
        }

        controller.isPreviewWindowVisible = true
        NSApp.activate(ignoringOtherApps: true)
        previewWindow?.makeKeyAndOrderFront(nil)
        snapWindowToDisplayAspectRatio(animated: false)
    }

    func togglePreviewWindow() {
        guard let win = previewWindow else {
            showPreviewWindow()
            return
        }
        if win.isVisible {
            win.orderOut(nil)
            CursorAndInputController.shared.isPreviewWindowVisible = false
            ScreenCaptureManager.shared.userStopSharing()
        } else {
            showPreviewWindow()
            ScreenCaptureManager.shared.resumeSharing()
        }
    }

    private func applyWindowTitlebarStyle(autoHide: Bool) {
        guard let win = previewWindow else { return }
        if autoHide {
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
        } else {
            win.titleVisibility = .visible
            win.titlebarAppearsTransparent = false
        }
    }

    private func updateWindowTitle() {
        guard let win = previewWindow else { return }
        if let disp = ScreenCaptureManager.shared.selectedDisplay {
            win.title = "ScreenPeek — \(disp.name) (\(disp.resolutionText))"
        } else {
            win.title = "ScreenPeek — Màn hình kết nối"
        }
    }

    private func applyWindowLevel(isOnTop: Bool) {
        guard let win = previewWindow else { return }
        win.level = isOnTop ? .floating : .normal
    }

    private func windowChromeHeight(for window: NSWindow) -> CGFloat {
        let titleBarHeight = max(window.frame.height - window.contentLayoutRect.height, 0)
        let innerChrome = CursorAndInputController.shared.shouldShowWindowChrome ? PreviewWindowView.chromeHeight : 0
        return titleBarHeight + innerChrome
    }

    func snapWindowToDisplayAspectRatio(animated: Bool) {
        guard let win = previewWindow,
              CursorAndInputController.shared.isAspectRatioLocked else { return }

        let aspect = max(ScreenCaptureManager.shared.selectedDisplay?.aspectRatio ?? (16.0 / 9.0), 0.4)
        let currentFrame = win.frame
        let chromeH = windowChromeHeight(for: win)
        let targetVideoHeight = round(currentFrame.width / aspect)
        let targetHeight = max(targetVideoHeight + chromeH, win.minSize.height)

        guard abs(targetHeight - currentFrame.height) > 2 else { return }

        var newFrame = currentFrame
        newFrame.origin.y += (currentFrame.height - targetHeight)
        newFrame.size.height = targetHeight

        isProgrammaticWindowMove = true
        win.setFrame(newFrame, display: true, animate: animated)
        isProgrammaticWindowMove = false
    }

    // MARK: - Snap to 4 Screen Corners
    func snapWindow(to corner: ScreenCorner, animated: Bool) {
        guard let win = previewWindow,
              let screen = win.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let visible = screen.visibleFrame
        let size = win.frame.size
        let inset: CGFloat = 16

        let targetOrigin: NSPoint
        switch corner {
        case .topLeft:
            targetOrigin = NSPoint(x: visible.minX + inset, y: visible.maxY - size.height - inset)
        case .topRight:
            targetOrigin = NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        case .bottomLeft:
            targetOrigin = NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .bottomRight:
            targetOrigin = NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
        }

        var newFrame = win.frame
        newFrame.origin = targetOrigin

        isProgrammaticWindowMove = true
        win.setFrame(newFrame, display: true, animate: animated)
        isProgrammaticWindowMove = false
        ProjectorOverlayManager.shared.updateOverlayWindows()
    }

    private func evaluateMagneticCornerSnapIfNeeded() {
        guard CursorAndInputController.shared.snapToCorners,
              NSEvent.pressedMouseButtons == 0,
              let win = previewWindow,
              let screen = win.screen else { return }

        let visible = screen.visibleFrame
        let f = win.frame
        let threshold: CGFloat = 34
        let inset: CGFloat = 16

        let nearLeft = abs(f.minX - visible.minX) <= threshold
        let nearRight = abs(visible.maxX - f.maxX) <= threshold
        let nearBottom = abs(f.minY - visible.minY) <= threshold
        let nearTop = abs(visible.maxY - f.maxY) <= threshold

        var targetX = f.origin.x
        var targetY = f.origin.y
        var shouldSnap = false

        if nearLeft && (nearTop || nearBottom) {
            targetX = visible.minX + inset
            shouldSnap = true
        } else if nearRight && (nearTop || nearBottom) {
            targetX = visible.maxX - f.width - inset
            shouldSnap = true
        }

        if nearBottom && (nearLeft || nearRight) {
            targetY = visible.minY + inset
            shouldSnap = true
        } else if nearTop && (nearLeft || nearRight) {
            targetY = visible.maxY - f.height - inset
            shouldSnap = true
        }

        guard shouldSnap else { return }
        guard hypot(targetX - f.origin.x, targetY - f.origin.y) > 2 else { return }

        var snappedFrame = f
        snappedFrame.origin = NSPoint(x: targetX, y: targetY)
        isProgrammaticWindowMove = true
        win.setFrame(snappedFrame, display: true, animate: true)
        isProgrammaticWindowMove = false
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        CursorAndInputController.shared.isPreviewWindowVisible = false
        ScreenCaptureManager.shared.userStopSharing()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticWindowMove else { return }
        ProjectorOverlayManager.shared.updateOverlayWindows()

        guard CursorAndInputController.shared.snapToCorners else { return }
        snapSettleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.evaluateMagneticCornerSnapIfNeeded()
            }
        }
        snapSettleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard CursorAndInputController.shared.isAspectRatioLocked else {
            return frameSize
        }
        let aspect = max(ScreenCaptureManager.shared.selectedDisplay?.aspectRatio ?? (16.0 / 9.0), 0.4)
        let chromeH = windowChromeHeight(for: sender)
        let width = max(frameSize.width, sender.minSize.width)
        let targetVideoHeight = round(width / aspect)
        let targetHeight = max(targetVideoHeight + chromeH, sender.minSize.height)
        return NSSize(width: width, height: targetHeight)
    }

    // MARK: - Smart Cursor Switcher
    func toggleCursorBetweenDisplays() {
        let controller = CursorAndInputController.shared
        let capture = ScreenCaptureManager.shared

        if controller.isCursorOnTargetDisplay {
            lastExternalCursorNormalized = controller.cursorNormalizedPosition
            if let savedPt = lastLaptopCursorPoint {
                CGAssociateMouseAndMouseCursorPosition(1)
                CGWarpMouseCursorPosition(savedPt)
            } else if let builtin = capture.availableDisplays.first(where: { $0.isBuiltin }) ?? capture.availableDisplays.first {
                let centerPt = CGPoint(x: builtin.quartzBounds.midX, y: builtin.quartzBounds.midY)
                CGAssociateMouseAndMouseCursorPosition(1)
                CGWarpMouseCursorPosition(centerPt)
            }
        } else {
            lastLaptopCursorPoint = CGEvent(source: nil)?.location
            controller.teleportCursor(toNormalized: lastExternalCursorNormalized)
        }
    }

    // MARK: - Menu Bar Status Item
    private func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: "ScreenPeek")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ScreenPeek — Xem & điều khiển màn hình kết nối"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let controller = CursorAndInputController.shared
        let overlay = ProjectorOverlayManager.shared
        let modMask = controller.hotKeyPreset.cocoaModifierMask
        let hasHK = controller.hotKeyPreset != .disabled

        let header = NSMenuItem(title: "ScreenPeek — Trợ lý Thuyết trình Màn hình phụ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let toggleWinItem = NSMenuItem(
            title: (previewWindow?.isVisible == true) ? "Ẩn cửa sổ ScreenPeek" : "Hiện cửa sổ ScreenPeek",
            action: #selector(toggleWindowAction),
            keyEquivalent: hasHK ? "m" : ""
        )
        if hasHK { toggleWinItem.keyEquivalentModifierMask = modMask }
        toggleWinItem.target = self
        menu.addItem(toggleWinItem)

        let jumpCursorItem = NSMenuItem(
            title: "Chuyển nhanh chuột qua lại 2 màn hình",
            action: #selector(jumpCursorAction),
            keyEquivalent: hasHK ? "c" : ""
        )
        if hasHK { jumpCursorItem.keyEquivalentModifierMask = modMask }
        jumpCursorItem.target = self
        menu.addItem(jumpCursorItem)

        let switchModeItem = NSMenuItem(
            title: "Đổi chế độ: Chỉ xem ↔ Điều khiển trực tiếp",
            action: #selector(switchModeAction),
            keyEquivalent: hasHK ? "i" : ""
        )
        if hasHK { switchModeItem.keyEquivalentModifierMask = modMask }
        switchModeItem.target = self
        menu.addItem(switchModeItem)

        menu.addItem(.separator())

        let laserItem = NSMenuItem(
            title: "Đèn Laser / Spotlight trên màn hình chiếu",
            action: #selector(toggleAudienceLaserAction),
            keyEquivalent: hasHK ? "l" : ""
        )
        if hasHK { laserItem.keyEquivalentModifierMask = modMask }
        laserItem.state = overlay.isAudienceLaserEnabled ? .on : .off
        laserItem.target = self
        menu.addItem(laserItem)

        let blackoutItem = NSMenuItem(
            title: "Màn che bảo mật màn hình phụ (Blackout)",
            action: #selector(toggleBlackoutAction),
            keyEquivalent: hasHK ? "b" : ""
        )
        if hasHK { blackoutItem.keyEquivalentModifierMask = modMask }
        blackoutItem.state = overlay.isBlackoutEnabled ? .on : .off
        blackoutItem.target = self
        menu.addItem(blackoutItem)

        let clickThroughItem = NSMenuItem(
            title: "Chế độ Xuyên chuột (Click-Through)",
            action: #selector(toggleClickThroughAction),
            keyEquivalent: hasHK ? "t" : ""
        )
        if hasHK { clickThroughItem.keyEquivalentModifierMask = modMask }
        clickThroughItem.state = controller.isClickThroughEnabled ? .on : .off
        clickThroughItem.target = self
        menu.addItem(clickThroughItem)

        menu.addItem(.separator())

        let displaysHeader = NSMenuItem(title: "Màn hình đang kết nối", action: nil, keyEquivalent: "")
        displaysHeader.isEnabled = false
        menu.addItem(displaysHeader)

        for display in ScreenCaptureManager.shared.availableDisplays {
            let item = NSMenuItem(
                title: display.displayLabel,
                action: #selector(selectDisplayFromMenu(_:)),
                keyEquivalent: ""
            )
            item.representedObject = display.id
            item.state = (ScreenCaptureManager.shared.selectedDisplay?.id == display.id) ? .on : .off
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let pinItem = NSMenuItem(
            title: "Luôn nổi trên cùng (Always on Top)",
            action: #selector(toggleAlwaysOnTopAction),
            keyEquivalent: ""
        )
        pinItem.state = controller.isAlwaysOnTop ? .on : .off
        pinItem.target = self
        menu.addItem(pinItem)

        let autoHideItem = NSMenuItem(
            title: "Tự ẩn thanh công cụ (Borderless PiP)",
            action: #selector(toggleAutoHideAction),
            keyEquivalent: ""
        )
        autoHideItem.state = controller.autoHideToolbar ? .on : .off
        autoHideItem.target = self
        menu.addItem(autoHideItem)

        let hideDockItem = NSMenuItem(
            title: "Ẩn biểu tượng trên thanh Dock",
            action: #selector(toggleHideFromDockAction),
            keyEquivalent: ""
        )
        hideDockItem.state = controller.hideFromDock ? .on : .off
        hideDockItem.target = self
        menu.addItem(hideDockItem)

        let launchItem = NSMenuItem(
            title: "Tự khởi động cùng macOS",
            action: #selector(toggleLaunchAtLoginAction),
            keyEquivalent: ""
        )
        launchItem.state = controller.launchAtLogin ? .on : .off
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Thoát ScreenPeek",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleWindowAction() { togglePreviewWindow() }
    @objc private func jumpCursorAction() { toggleCursorBetweenDisplays() }
    @objc private func switchModeAction() {
        let controller = CursorAndInputController.shared
        controller.interactionMode = (controller.interactionMode == .liveView) ? .interactive : .liveView
    }
    @objc private func toggleAudienceLaserAction() {
        ProjectorOverlayManager.shared.isAudienceLaserEnabled.toggle()
    }
    @objc private func toggleBlackoutAction() {
        ProjectorOverlayManager.shared.isBlackoutEnabled.toggle()
    }
    @objc private func toggleClickThroughAction() {
        CursorAndInputController.shared.isClickThroughEnabled.toggle()
    }
    @objc private func selectDisplayFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID else { return }
        ScreenCaptureManager.shared.selectedDisplayID = id
        showPreviewWindow()
    }
    @objc private func toggleAlwaysOnTopAction() {
        CursorAndInputController.shared.isAlwaysOnTop.toggle()
    }
    @objc private func toggleAutoHideAction() {
        CursorAndInputController.shared.autoHideToolbar.toggle()
    }
    @objc private func toggleHideFromDockAction() {
        CursorAndInputController.shared.hideFromDock.toggle()
    }
    @objc private func toggleLaunchAtLoginAction() {
        let ctrl = CursorAndInputController.shared
        ctrl.setLaunchAtLogin(!ctrl.launchAtLogin)
    }
    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Customizable Global Carbon Hotkeys
    private func installHotKeyEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            Task { @MainActor in
                switch hotKeyID.id {
                case 1:
                    ScreenPeekAppDelegate.shared?.togglePreviewWindow()
                case 2:
                    ScreenPeekAppDelegate.shared?.toggleCursorBetweenDisplays()
                case 3:
                    let ctrl = CursorAndInputController.shared
                    ctrl.interactionMode = (ctrl.interactionMode == .liveView) ? .interactive : .liveView
                case 4:
                    ProjectorOverlayManager.shared.isAudienceLaserEnabled.toggle()
                case 5:
                    ProjectorOverlayManager.shared.isBlackoutEnabled.toggle()
                case 6:
                    CursorAndInputController.shared.isClickThroughEnabled.toggle()
                default:
                    break
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    func reRegisterGlobalHotKeys(for preset: HotKeyModifierPreset) {
        // Unregister existing hotkeys cleanly
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()

        guard let modifiers = preset.carbonModifiers else { return }

        registerSingleHotKey(id: 1, keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers) // Show/Hide Window
        registerSingleHotKey(id: 2, keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers) // Switch Cursor Screen
        registerSingleHotKey(id: 3, keyCode: UInt32(kVK_ANSI_I), modifiers: modifiers) // Switch Mode
        registerSingleHotKey(id: 4, keyCode: UInt32(kVK_ANSI_L), modifiers: modifiers) // Audience Laser
        registerSingleHotKey(id: 5, keyCode: UInt32(kVK_ANSI_B), modifiers: modifiers) // Privacy Blackout
        registerSingleHotKey(id: 6, keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers) // Click-Through
    }

    private func registerSingleHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        let signature = OSType(0x53504B32) // 'SPK2'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }
}
