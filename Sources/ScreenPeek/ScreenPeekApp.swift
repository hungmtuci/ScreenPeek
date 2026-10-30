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
    private var settingsWindow: NSWindow?
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
        let updater = GitHubUpdateManager.shared

        setupApplicationMainMenu()
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
        controller.onAutoHideToolbarChanged = { [weak self] _ in
            self?.syncTrafficLightsVisibility()
            if controller.isAspectRatioLocked {
                self?.snapWindowToDisplayAspectRatio(animated: true)
            }
        }
        controller.onChromeVisibilityChanged = { [weak self] in
            self?.syncTrafficLightsVisibility()
        }
        controller.onClickThroughChanged = { [weak self] ignoresMouse in
            self?.previewWindow?.ignoresMouseEvents = ignoresMouse
            self?.syncTrafficLightsVisibility()
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
        updater.startAutomaticChecksIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreviewWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Standard macOS Main Menu (Enables ⌘, ⌘W ⌘Q ⌘C ⌘V ⌘A everywhere)
    private func setupApplicationMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Giới thiệu về ScreenPeek", action: #selector(openAboutTabAction), keyEquivalent: "")
        appMenu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Cài đặt…", action: #selector(openSettingsAction), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)

        let updateItem = NSMenuItem(title: "Kiểm tra cập nhật…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ẩn ScreenPeek", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Thoát ScreenPeek", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit Menu (Enables Cut/Copy/Paste/Select All in Settings TextFields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Chỉnh sửa")
        editMenu.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Làm lại", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenu.addItem(withTitle: "Đóng cửa sổ", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applyDockVisibilityPolicy(hideFromDock: Bool) {
        let previewWasVisible = previewWindow?.isVisible ?? false
        let settingsWasVisible = settingsWindow?.isVisible ?? false
        NSApp.setActivationPolicy(hideFromDock ? .accessory : .regular)
        if previewWasVisible || settingsWasVisible {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                if previewWasVisible {
                    self.previewWindow?.makeKeyAndOrderFront(nil)
                }
                if settingsWasVisible {
                    self.settingsWindow?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // MARK: - Preview Window Management (Unified macOS Vibrancy Style)
    func showPreviewWindow() {
        let controller = CursorAndInputController.shared

        if previewWindow == nil {
            let aspect = ScreenCaptureManager.shared.selectedDisplay?.aspectRatio ?? (16.0 / 9.0)
            let initialWidth: CGFloat = 680
            let chromeH: CGFloat = controller.autoHideToolbar ? 0 : (PreviewWindowView.headerHeight + 1)
            let initialHeight = round(initialWidth / aspect) + chromeH

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.minSize = NSSize(width: 610, height: 320)
            win.isReleasedWhenClosed = false
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.backgroundColor = .black
            win.hasShadow = true
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
            syncTrafficLightsVisibility()
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

    // MARK: - Native macOS Settings & Software Update Window
    func openSettingsWindow(tab: SettingsTab = .general) {
        let controller = CursorAndInputController.shared
        controller.selectedSettingsTab = tab

        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 730, height: 530),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.minSize = NSSize(width: 700, height: 500)
            win.isReleasedWhenClosed = false
            win.title = "Cài đặt ScreenPeek"
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            win.contentView = NSHostingView(rootView: SettingsWindowView())
            win.center()
            self.settingsWindow = win
        }

        // Keep Settings visible even if the preview window is pinned as Always on Top
        if controller.isAlwaysOnTop {
            settingsWindow?.level = .floating
        } else {
            settingsWindow?.level = .normal
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func syncTrafficLightsVisibility() {
        guard let win = previewWindow else { return }
        let visible = CursorAndInputController.shared.shouldShowWindowChrome
        win.standardWindowButton(.closeButton)?.isHidden = !visible
        win.standardWindowButton(.miniaturizeButton)?.isHidden = !visible
        win.standardWindowButton(.zoomButton)?.isHidden = !visible
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
        previewWindow?.level = isOnTop ? .floating : .normal
        if settingsWindow?.isVisible == true {
            settingsWindow?.level = isOnTop ? .floating : .normal
        }
    }

    private func windowChromeHeight(for window: NSWindow) -> CGFloat {
        // With .fullSizeContentView, stacked layout chrome is headerHeight + 1pt divider in standard mode, or 0pt in Borderless PiP mode.
        return CursorAndInputController.shared.autoHideToolbar ? 0 : (PreviewWindowView.headerHeight + 1)
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
        guard (notification.object as? NSWindow) === previewWindow else { return }
        CursorAndInputController.shared.isPreviewWindowVisible = false
        ScreenCaptureManager.shared.userStopSharing()
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === previewWindow else { return }
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
        guard sender === previewWindow,
              CursorAndInputController.shared.isAspectRatioLocked else {
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

    // MARK: - Menu Bar Status Item (Modern macOS Menu with SF Symbols)
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

    private func menuIcon(_ symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let controller = CursorAndInputController.shared
        let overlay = ProjectorOverlayManager.shared
        let updater = GitHubUpdateManager.shared
        let modMask = controller.hotKeyPreset.cocoaModifierMask
        let hasHK = controller.hotKeyPreset != .disabled

        let header = NSMenuItem(
            title: "ScreenPeek v\(updater.currentVersion) — Trợ lý Màn hình phụ",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if let release = updater.availableRelease {
            let newVerItem = NSMenuItem(
                title: "Có bản cập nhật mới v\(release.versionString) — Cài đặt ngay…",
                action: #selector(openAboutTabAction),
                keyEquivalent: ""
            )
            newVerItem.image = menuIcon("arrow.down.circle.fill")
            newVerItem.target = self
            menu.addItem(newVerItem)
            menu.addItem(.separator())
        }

        let toggleWinItem = NSMenuItem(
            title: (previewWindow?.isVisible == true) ? "Ẩn cửa sổ ScreenPeek" : "Hiện cửa sổ ScreenPeek",
            action: #selector(toggleWindowAction),
            keyEquivalent: hasHK ? "m" : ""
        )
        toggleWinItem.image = menuIcon((previewWindow?.isVisible == true) ? "eye.slash" : "macwindow")
        if hasHK { toggleWinItem.keyEquivalentModifierMask = modMask }
        toggleWinItem.target = self
        menu.addItem(toggleWinItem)

        let streamItem = NSMenuItem(
            title: ScreenCaptureManager.shared.isCapturing ? "Tạm dừng thu hình màn hình" : "Tiếp tục thu hình màn hình",
            action: #selector(toggleStreamAction),
            keyEquivalent: hasHK ? "s" : ""
        )
        streamItem.image = menuIcon(ScreenCaptureManager.shared.isCapturing ? "pause.fill" : "play.fill")
        if hasHK { streamItem.keyEquivalentModifierMask = modMask }
        streamItem.target = self
        menu.addItem(streamItem)

        let jumpCursorItem = NSMenuItem(
            title: "Chuyển nhanh chuột qua lại 2 màn hình",
            action: #selector(jumpCursorAction),
            keyEquivalent: hasHK ? "c" : ""
        )
        jumpCursorItem.image = menuIcon("location.viewfinder")
        if hasHK { jumpCursorItem.keyEquivalentModifierMask = modMask }
        jumpCursorItem.target = self
        menu.addItem(jumpCursorItem)

        let loupeItem = NSMenuItem(
            title: "Kính lúp phóng đại (\(controller.loupeMode.label))",
            action: #selector(cycleLoupeModeAction),
            keyEquivalent: hasHK ? "z" : ""
        )
        loupeItem.image = menuIcon("plus.magnifyingglass")
        if hasHK { loupeItem.keyEquivalentModifierMask = modMask }
        loupeItem.state = controller.loupeMode != .off ? .on : .off
        loupeItem.target = self
        menu.addItem(loupeItem)

        let switchModeItem = NSMenuItem(
            title: "Đổi chế độ: Chỉ xem ↔ Điều khiển trực tiếp",
            action: #selector(switchModeAction),
            keyEquivalent: hasHK ? "i" : ""
        )
        switchModeItem.image = menuIcon("cursorarrow.click.2")
        if hasHK { switchModeItem.keyEquivalentModifierMask = modMask }
        switchModeItem.target = self
        menu.addItem(switchModeItem)

        menu.addItem(.separator())

        let laserItem = NSMenuItem(
            title: "Đèn Laser / Spotlight trên màn hình chiếu",
            action: #selector(toggleAudienceLaserAction),
            keyEquivalent: hasHK ? "l" : ""
        )
        laserItem.image = menuIcon("light.beacon.max.fill")
        if hasHK { laserItem.keyEquivalentModifierMask = modMask }
        laserItem.state = overlay.isAudienceLaserEnabled ? .on : .off
        laserItem.target = self
        menu.addItem(laserItem)

        let blackoutItem = NSMenuItem(
            title: "Màn che bảo mật màn hình phụ (Blackout)",
            action: #selector(toggleBlackoutAction),
            keyEquivalent: hasHK ? "b" : ""
        )
        blackoutItem.image = menuIcon("eye.slash.fill")
        if hasHK { blackoutItem.keyEquivalentModifierMask = modMask }
        blackoutItem.state = overlay.isBlackoutEnabled ? .on : .off
        blackoutItem.target = self
        menu.addItem(blackoutItem)

        let clickThroughItem = NSMenuItem(
            title: "Chế độ Xuyên chuột (Click-Through)",
            action: #selector(toggleClickThroughAction),
            keyEquivalent: hasHK ? "t" : ""
        )
        clickThroughItem.image = menuIcon("hand.point.up.braille.fill")
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
            item.image = menuIcon(display.isBuiltin ? "laptopcomputer" : "display")
            item.representedObject = display.id
            item.state = (ScreenCaptureManager.shared.selectedDisplay?.id == display.id) ? .on : .off
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let pinItem = NSMenuItem(
            title: "Luôn nổi trên cùng (Always on Top)",
            action: #selector(toggleAlwaysOnTopAction),
            keyEquivalent: hasHK ? "p" : ""
        )
        pinItem.image = menuIcon("pin.fill")
        if hasHK { pinItem.keyEquivalentModifierMask = modMask }
        pinItem.state = controller.isAlwaysOnTop ? .on : .off
        pinItem.target = self
        menu.addItem(pinItem)

        let autoHideItem = NSMenuItem(
            title: "Giao diện tràn viền tự ẩn (Picture-in-Picture)",
            action: #selector(toggleAutoHideAction),
            keyEquivalent: hasHK ? "h" : ""
        )
        autoHideItem.image = menuIcon("pip")
        if hasHK { autoHideItem.keyEquivalentModifierMask = modMask }
        autoHideItem.state = controller.autoHideToolbar ? .on : .off
        autoHideItem.target = self
        menu.addItem(autoHideItem)

        let hideDockItem = NSMenuItem(
            title: "Ẩn biểu tượng trên thanh Dock",
            action: #selector(toggleHideFromDockAction),
            keyEquivalent: ""
        )
        hideDockItem.image = menuIcon("dock.rectangle")
        hideDockItem.state = controller.hideFromDock ? .on : .off
        hideDockItem.target = self
        menu.addItem(hideDockItem)

        let launchItem = NSMenuItem(
            title: "Tự khởi động cùng macOS",
            action: #selector(toggleLaunchAtLoginAction),
            keyEquivalent: ""
        )
        launchItem.image = menuIcon("power.circle")
        launchItem.state = controller.launchAtLogin ? .on : .off
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Cài đặt ScreenPeek…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.image = menuIcon("gearshape")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkUpdatesItem = NSMenuItem(
            title: "Kiểm tra cập nhật qua GitHub…",
            action: #selector(checkForUpdatesAction),
            keyEquivalent: ""
        )
        checkUpdatesItem.image = menuIcon("arrow.triangle.2.circlepath")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Thoát ScreenPeek",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.image = menuIcon("power")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleWindowAction() { togglePreviewWindow() }
    @objc private func toggleStreamAction() {
        let cap = ScreenCaptureManager.shared
        if cap.isCapturing {
            cap.userStopSharing()
        } else {
            cap.resumeSharing()
        }
    }
    @objc private func jumpCursorAction() { toggleCursorBetweenDisplays() }
    @objc private func cycleLoupeModeAction() {
        let ctrl = CursorAndInputController.shared
        switch ctrl.loupeMode {
        case .off: ctrl.loupeMode = .holdOption
        case .holdOption: ctrl.loupeMode = .always
        case .always: ctrl.loupeMode = .off
        }
    }
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
    @objc private func openSettingsAction() {
        openSettingsWindow(tab: .general)
    }
    @objc private func openAboutTabAction() {
        openSettingsWindow(tab: .updates)
    }
    @objc private func checkForUpdatesAction() {
        Task {
            await GitHubUpdateManager.shared.checkForUpdates(userInitiated: true)
        }
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
                case 7:
                    let cap = ScreenCaptureManager.shared
                    if cap.isCapturing {
                        cap.userStopSharing()
                    } else {
                        cap.resumeSharing()
                    }
                case 8:
                    let ctrl = CursorAndInputController.shared
                    switch ctrl.loupeMode {
                    case .off: ctrl.loupeMode = .holdOption
                    case .holdOption: ctrl.loupeMode = .always
                    case .always: ctrl.loupeMode = .off
                    }
                case 9:
                    CursorAndInputController.shared.isAlwaysOnTop.toggle()
                case 10:
                    CursorAndInputController.shared.autoHideToolbar.toggle()
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
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()

        guard let modifiers = preset.carbonModifiers else { return }

        registerSingleHotKey(id: 1, keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers)  // Show/Hide Window
        registerSingleHotKey(id: 2, keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers)  // Switch Cursor Screen
        registerSingleHotKey(id: 3, keyCode: UInt32(kVK_ANSI_I), modifiers: modifiers)  // Switch Mode
        registerSingleHotKey(id: 4, keyCode: UInt32(kVK_ANSI_L), modifiers: modifiers)  // Audience Laser
        registerSingleHotKey(id: 5, keyCode: UInt32(kVK_ANSI_B), modifiers: modifiers)  // Privacy Blackout
        registerSingleHotKey(id: 6, keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers)  // Click-Through
        registerSingleHotKey(id: 7, keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers)  // Pause/Resume Stream
        registerSingleHotKey(id: 8, keyCode: UInt32(kVK_ANSI_Z), modifiers: modifiers)  // Cycle Zoom Loupe
        registerSingleHotKey(id: 9, keyCode: UInt32(kVK_ANSI_P), modifiers: modifiers)  // Pin Always on Top
        registerSingleHotKey(id: 10, keyCode: UInt32(kVK_ANSI_H), modifiers: modifiers) // Toggle Borderless PiP
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
