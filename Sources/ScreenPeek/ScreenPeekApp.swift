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
        capture.onSelectedDisplayChanged = { [weak self] _ in
            if CursorAndInputController.shared.isAspectRatioLocked {
                self?.snapWindowToDisplayAspectRatio(animated: true)
            }
            self?.updateWindowTitle()
        }

        setupStatusBarMenu()
        registerGlobalHotKeys()
        showPreviewWindow()

        capture.start()
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreviewWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Preview Window Management
    func showPreviewWindow() {
        if previewWindow == nil {
            let aspect = ScreenCaptureManager.shared.selectedDisplay?.aspectRatio ?? (16.0 / 9.0)
            let initialWidth: CGFloat = 560
            let initialVideoHeight = round(initialWidth / aspect)
            let initialHeight = initialVideoHeight + PreviewWindowView.chromeHeight

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.minSize = NSSize(width: 360, height: 240)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.alphaValue = CGFloat(CursorAndInputController.shared.windowOpacity)
            win.contentView = NSHostingView(rootView: PreviewWindowView())

            // Position neatly at bottom-right of primary (built-in) screen on first launch
            if let mainScreen = NSScreen.screens.first {
                let visible = mainScreen.visibleFrame
                let originX = visible.maxX - initialWidth - 24
                let originY = visible.minY + 28
                win.setFrameOrigin(NSPoint(x: max(visible.minX + 16, originX), y: max(visible.minY + 16, originY)))
            } else {
                win.center()
            }

            self.previewWindow = win
            updateWindowTitle()
            applyWindowLevel(isOnTop: CursorAndInputController.shared.isAlwaysOnTop)
        }

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
            ScreenCaptureManager.shared.userStopSharing()
        } else {
            showPreviewWindow()
            ScreenCaptureManager.shared.resumeSharing()
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
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        return max(titleBarHeight, 28) + PreviewWindowView.chromeHeight
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

        // Keep top edge anchored when resizing
        var newFrame = currentFrame
        newFrame.origin.y += (currentFrame.height - targetHeight)
        newFrame.size.height = targetHeight
        win.setFrame(newFrame, display: true, animate: animated)
    }

    // MARK: - NSWindowDelegate (Live Aspect Ratio Locking & Clean Close)
    func windowWillClose(_ notification: Notification) {
        ScreenCaptureManager.shared.userStopSharing()
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

    // MARK: - Smart Cursor Switcher (⌘⇧C)
    func toggleCursorBetweenDisplays() {
        let controller = CursorAndInputController.shared
        let capture = ScreenCaptureManager.shared

        if controller.isCursorOnTargetDisplay {
            // Save current normalized position on target display
            lastExternalCursorNormalized = controller.cursorNormalizedPosition
            // Jump back to primary/laptop display
            if let savedPt = lastLaptopCursorPoint {
                CGAssociateMouseAndMouseCursorPosition(1)
                CGWarpMouseCursorPosition(savedPt)
            } else if let builtin = capture.availableDisplays.first(where: { $0.isBuiltin }) ?? capture.availableDisplays.first {
                let centerPt = CGPoint(x: builtin.quartzBounds.midX, y: builtin.quartzBounds.midY)
                CGAssociateMouseAndMouseCursorPosition(1)
                CGWarpMouseCursorPosition(centerPt)
            }
        } else {
            // Save current position on laptop screen and jump to target display
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

        let header = NSMenuItem(title: "ScreenPeek — Màn hình phụ thu nhỏ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let toggleWinItem = NSMenuItem(
            title: (previewWindow?.isVisible == true) ? "Ẩn cửa sổ ScreenPeek" : "Hiện cửa sổ ScreenPeek",
            action: #selector(toggleWindowAction),
            keyEquivalent: "M"
        )
        toggleWinItem.keyEquivalentModifierMask = [.command, .shift]
        toggleWinItem.target = self
        menu.addItem(toggleWinItem)

        let jumpCursorItem = NSMenuItem(
            title: "Chuyển nhanh chuột qua lại 2 màn hình",
            action: #selector(jumpCursorAction),
            keyEquivalent: "C"
        )
        jumpCursorItem.keyEquivalentModifierMask = [.command, .shift]
        jumpCursorItem.target = self
        menu.addItem(jumpCursorItem)

        let switchModeItem = NSMenuItem(
            title: "Đổi chế độ: Chỉ xem ↔ Điều khiển trực tiếp",
            action: #selector(switchModeAction),
            keyEquivalent: "I"
        )
        switchModeItem.keyEquivalentModifierMask = [.command, .shift]
        switchModeItem.target = self
        menu.addItem(switchModeItem)

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
        pinItem.state = CursorAndInputController.shared.isAlwaysOnTop ? .on : .off
        pinItem.target = self
        menu.addItem(pinItem)

        let highlightItem = NSMenuItem(
            title: "Vòng tròn làm nổi bật vị trí chuột",
            action: #selector(toggleCursorHighlightAction),
            keyEquivalent: ""
        )
        highlightItem.state = CursorAndInputController.shared.showCursorHighlight ? .on : .off
        highlightItem.target = self
        menu.addItem(highlightItem)

        let aspectItem = NSMenuItem(
            title: "Khóa tỷ lệ khung hình theo màn hình phụ",
            action: #selector(toggleAspectLockAction),
            keyEquivalent: ""
        )
        aspectItem.state = CursorAndInputController.shared.isAspectRatioLocked ? .on : .off
        aspectItem.target = self
        menu.addItem(aspectItem)

        let hideDockItem = NSMenuItem(
            title: "Ẩn biểu tượng trên thanh Dock",
            action: #selector(toggleHideFromDockAction),
            keyEquivalent: ""
        )
        hideDockItem.state = CursorAndInputController.shared.hideFromDock ? .on : .off
        hideDockItem.target = self
        menu.addItem(hideDockItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Thoát ScreenPeek",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleHideFromDockAction() {
        CursorAndInputController.shared.hideFromDock.toggle()
    }

    @objc private func toggleWindowAction() {
        togglePreviewWindow()
    }

    @objc private func jumpCursorAction() {
        toggleCursorBetweenDisplays()
    }

    @objc private func switchModeAction() {
        let controller = CursorAndInputController.shared
        controller.interactionMode = (controller.interactionMode == .liveView) ? .interactive : .liveView
    }

    @objc private func selectDisplayFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID else { return }
        ScreenCaptureManager.shared.selectedDisplayID = id
        showPreviewWindow()
    }

    @objc private func toggleAlwaysOnTopAction() {
        CursorAndInputController.shared.isAlwaysOnTop.toggle()
    }

    @objc private func toggleCursorHighlightAction() {
        CursorAndInputController.shared.showCursorHighlight.toggle()
    }

    @objc private func toggleAspectLockAction() {
        CursorAndInputController.shared.isAspectRatioLocked.toggle()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Global Carbon Hotkeys
    private func registerGlobalHotKeys() {
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

        let modifiers = UInt32(cmdKey | shiftKey)
        // 1: Cmd+Shift+M (kVK_ANSI_M = 0x2E)
        registerSingleHotKey(id: 1, keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers)
        // 2: Cmd+Shift+C (kVK_ANSI_C = 0x08)
        registerSingleHotKey(id: 2, keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers)
        // 3: Cmd+Shift+I (kVK_ANSI_I = 0x22)
        registerSingleHotKey(id: 3, keyCode: UInt32(kVK_ANSI_I), modifiers: modifiers)
    }

    private func registerSingleHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        let signature = OSType(0x53504B31) // 'SPK1'
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
