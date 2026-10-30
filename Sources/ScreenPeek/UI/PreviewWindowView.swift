import SwiftUI
import AppKit

struct PreviewWindowView: View {
    @ObservedObject var captureManager = ScreenCaptureManager.shared
    @ObservedObject var controller = CursorAndInputController.shared
    @ObservedObject var overlayManager = ProjectorOverlayManager.shared
    @ObservedObject var updateManager = GitHubUpdateManager.shared

    static let topTierHeight: CGFloat = 34
    static let actionBarHeight: CGFloat = 48
    static let startupBarHeight: CGFloat = 28
    static var headerHeight: CGFloat { topTierHeight + 1 + actionBarHeight + 1 + startupBarHeight }

    private var currentAspectRatio: CGFloat {
        captureManager.selectedDisplay?.aspectRatio ?? (16.0 / 9.0)
    }

    private var hkPrefix: String {
        let p = controller.hotKeyPreset.symbolPrefix
        return p.isEmpty ? "" : p
    }

    private func hkKey(_ key: String, fallback: String) -> String {
        hkPrefix.isEmpty ? fallback : "\(hkPrefix)\(key)"
    }

    private var showFloatingBottomHUD: Bool {
        if captureManager.isStoppedByUser || (!captureManager.hasScreenRecordingPermission && !captureManager.isCapturing) {
            return false
        }
        if controller.effectiveIgnoresMouseEvents {
            return false
        }
        if controller.interactionMode == .interactive && !controller.hasAccessibilityPermission {
            return true
        }
        return controller.isMouseInsidePreviewWindow
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Standard mode: 2-tier unified header sits cleanly above the video canvas.
                if !controller.autoHideToolbar {
                    unifiedTwoTierHeader
                        .frame(height: Self.headerHeight)
                    Divider()
                        .opacity(0.65)
                }

                videoPreviewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }

            // Borderless PiP mode: float the 2-tier frosted header smoothly over the video on hover with zero layout jump.
            if controller.autoHideToolbar && controller.shouldShowWindowChrome {
                VStack(spacing: 0) {
                    unifiedTwoTierHeader
                        .frame(height: Self.headerHeight)
                    Divider()
                        .opacity(0.55)
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 610, minHeight: 340)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.16)) {
                controller.isMouseInsidePreviewWindow = inside
            }
            if !inside {
                controller.hoveredToolbarItem = nil
            }
        }
    }

    // MARK: - Unified 2-Tier macOS Header (Title/Mode Strip + Labeled Action & Shortcut Bar)
    private var unifiedTwoTierHeader: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)

            WindowDragArea()

            VStack(spacing: 0) {
                topTitleAndModeRow
                    .frame(height: Self.topTierHeight)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                labeledActionShortcutRow
                    .frame(height: Self.actionBarHeight)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                startupOptionsRow
                    .frame(height: Self.startupBarHeight)
            }
        }
    }

    // MARK: - Tier 1: Traffic Lights + Display Picker + Mode Switcher (⌃⌥I) + Settings (⌘,)
    private var topTitleAndModeRow: some View {
        HStack(spacing: 8) {
            // Leading space reserved for native macOS traffic lights (Close / Minimize / Zoom)
            Spacer()
                .frame(width: 66)

            displaySelectorMenu

            Spacer(minLength: 6)

            modeSegmentedControl
                .layoutPriority(1)

            Spacer(minLength: 6)

            if let release = updateManager.availableRelease {
                Button {
                    ScreenPeekAppDelegate.shared?.openSettingsWindow(tab: .updates)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Cập nhật v\(release.versionString)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemTeal)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .onHover { setHoveredItem(.updateAvailable, hovering: $0) }
            }

            // Settings Button with caption & shortcut (⌘,)
            Button {
                ScreenPeekAppDelegate.shared?.openSettingsWindow(tab: .general)
            } label: {
                let hovered = controller.hoveredToolbarItem == .openSettings
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Cài đặt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                    Text("⌘,")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.11 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .onHover { setHoveredItem(.openSettings, hovering: $0) }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Tier 2: Re-laid-out Icons > Caption on Top + Shortcut Key Underneath
    private var labeledActionShortcutRow: some View {
        HStack(spacing: 5) {
            // 1. Pause / Resume Stream (⌃⌥S)
            actionShortcutTile(
                item: .stopResume,
                icon: captureManager.isCapturing ? "pause.fill" : "play.fill",
                caption: captureManager.isCapturing ? "Tạm dừng" : "Tiếp tục",
                shortcutText: hkKey("S", fallback: captureManager.isCapturing ? "Đang thu" : "Đã dừng"),
                isActive: !captureManager.isCapturing,
                activeColor: Color(nsColor: .systemGreen)
            ) {
                if captureManager.isCapturing {
                    captureManager.userStopSharing()
                } else {
                    captureManager.resumeSharing()
                }
            }

            // 2. Teleport Cursor (⌃⌥C)
            actionShortcutTile(
                item: .teleportCursor,
                icon: "location.viewfinder",
                caption: "Nhảy chuột",
                shortcutText: hkKey("C", fallback: "Nhấp đúp"),
                isActive: false,
                activeColor: .accentColor
            ) {
                controller.teleportCursorToCenterOfTargetDisplay()
            }

            // 3. Zoom Loupe (⌥ / ⌃⌥Z)
            actionShortcutTile(
                item: .loupeZoom,
                icon: controller.loupeMode == .off ? "magnifyingglass" : "plus.magnifyingglass",
                caption: "Kính lúp",
                shortcutText: hkPrefix.isEmpty ? "Giữ ⌥" : "⌥ • \(hkPrefix)Z",
                isActive: controller.loupeMode != .off,
                activeColor: controller.loupeMode == .always ? Color(nsColor: .systemGreen) : .accentColor
            ) {
                switch controller.loupeMode {
                case .off: controller.loupeMode = .holdOption
                case .holdOption: controller.loupeMode = .always
                case .always: controller.loupeMode = .off
                }
            }

            // 4. Audience Laser / Spotlight (⌃⌥L)
            actionShortcutTile(
                item: .audienceLaser,
                icon: "light.beacon.max.fill",
                caption: "Đèn Laser",
                shortcutText: hkKey("L", fallback: "Máy chiếu"),
                isActive: overlayManager.isAudienceLaserEnabled,
                activeColor: Color(nsColor: .systemRed)
            ) {
                overlayManager.isAudienceLaserEnabled.toggle()
            }

            // 5. Privacy Blackout Shield (⌃⌥B)
            actionShortcutTile(
                item: .privacyBlackout,
                icon: overlayManager.isBlackoutEnabled ? "eye.slash.fill" : "eye.slash",
                caption: "Màn che",
                shortcutText: hkKey("B", fallback: "Bảo mật"),
                isActive: overlayManager.isBlackoutEnabled,
                activeColor: Color(nsColor: .systemPurple)
            ) {
                overlayManager.isBlackoutEnabled.toggle()
            }

            // 6. Click-Through Ghost Mode (⌃⌥T)
            actionShortcutTile(
                item: .clickThrough,
                icon: "hand.point.up.braille.fill",
                caption: "Xuyên chuột",
                shortcutText: hkKey("T", fallback: "Giữ ⌥⌘"),
                isActive: controller.isClickThroughEnabled,
                activeColor: Color(nsColor: .systemCyan)
            ) {
                controller.isClickThroughEnabled.toggle()
            }

            // 7. Pin Always on Top (⌃⌥P)
            actionShortcutTile(
                item: .alwaysOnTop,
                icon: controller.isAlwaysOnTop ? "pin.fill" : "pin",
                caption: "Ghim nổi",
                shortcutText: hkKey("P", fallback: "Trên cùng"),
                isActive: controller.isAlwaysOnTop,
                activeColor: .accentColor
            ) {
                controller.isAlwaysOnTop.toggle()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func actionShortcutTile(
        item: ToolbarTooltipItem,
        icon: String,
        caption: String,
        shortcutText: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = controller.hoveredToolbarItem == item
        return Button(action: action) {
            VStack(spacing: 2.5) {
                // Top line: Icon > Caption ("trích dẫn")
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? activeColor : (hovered ? .primary : .secondary))

                    Text(caption)
                        .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }

                // Bottom line: Shortcut badge ("phía dưới là phím tắt để tiện thao tác")
                Text(shortcutText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isActive ? activeColor : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isActive ? activeColor.opacity(0.18) : Color.primary.opacity(0.075))
                    )
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 39, maxHeight: 39)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? activeColor.opacity(hovered ? 0.22 : 0.14)
                            : Color.primary.opacity(hovered ? 0.10 : 0.045)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isActive
                            ? activeColor.opacity(0.48)
                            : Color.primary.opacity(hovered ? 0.16 : 0.07),
                        lineWidth: isActive ? 1.0 : 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { setHoveredItem(item, hovering: $0) }
    }

    // MARK: - Tier 3: Startup & Quick Options Checkboxes ("Khởi động cùng macOS" & "Bật bảng này khi khởi động")
    private var startupOptionsRow: some View {
        HStack(spacing: 10) {
            macStartupCheckbox(
                item: .launchAtLoginToggle,
                title: "Khởi động cùng macOS",
                icon: "power.circle",
                isChecked: controller.launchAtLogin
            ) {
                controller.setLaunchAtLogin(!controller.launchAtLogin)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 12)

            macStartupCheckbox(
                item: .showWindowOnLaunchToggle,
                title: "Bật bảng này khi khởi động",
                icon: "macwindow.badge.plus",
                isChecked: controller.showWindowOnLaunch
            ) {
                controller.showWindowOnLaunch.toggle()
            }

            Spacer(minLength: 6)

            macStartupCheckbox(
                item: .headerHideFromDock,
                title: "Ẩn trên thanh Dock",
                icon: "dock.rectangle",
                isChecked: controller.hideFromDock
            ) {
                controller.hideFromDock.toggle()
            }
        }
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.02))
    }

    private func macStartupCheckbox(
        item: ToolbarTooltipItem,
        title: String,
        icon: String,
        isChecked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = controller.hoveredToolbarItem == item
        return Button(action: action) {
            HStack(spacing: 5.5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.8, style: .continuous)
                        .fill(isChecked ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .frame(width: 13.5, height: 13.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.8, style: .continuous)
                                .stroke(
                                    isChecked ? Color.accentColor.opacity(0.9) : Color.primary.opacity(hovered ? 0.35 : 0.22),
                                    lineWidth: 0.9
                                )
                        )
                        .shadow(color: isChecked ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.08), radius: 1, x: 0, y: 0.5)

                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }

                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)

                Text(title)
                    .font(.system(size: 11, weight: isChecked ? .semibold : .medium))
                    .foregroundStyle(isChecked ? Color.primary : Color.primary.opacity(0.84))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.08 : 0.0))
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { setHoveredItem(item, hovering: $0) }
    }

    // MARK: - Display Picker & Segmented Mode Control
    private var displaySelectorMenu: some View {
        Menu {
            Section("Chọn màn hình hiển thị") {
                ForEach(captureManager.availableDisplays) { display in
                    Button {
                        captureManager.selectedDisplayID = display.id
                    } label: {
                        HStack {
                            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                            Text(display.displayLabel)
                            if captureManager.selectedDisplay?.id == display.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                captureManager.refreshDisplays(autoSelectExternal: true)
                Task { await captureManager.restartCaptureStream() }
            } label: {
                Label("Làm mới & Tự chọn màn hình phụ", systemImage: "arrow.clockwise")
            }

            Divider()

            Button {
                Task { await updateManager.checkForUpdates(userInitiated: true) }
            } label: {
                Label("Kiểm tra cập nhật qua GitHub…", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                ScreenPeekAppDelegate.shared?.openSettingsWindow(tab: .general)
            } label: {
                Label("Cài đặt ScreenPeek… (⌘,)", systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(captureManager.isCapturing ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                    .frame(width: 6.5, height: 6.5)

                Image(systemName: (captureManager.selectedDisplay?.isBuiltin == false) ? "display" : "laptopcomputer")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(captureManager.selectedDisplay?.name ?? "Màn hình")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 230, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(controller.hoveredToolbarItem == .displayPicker ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
            )
        }
        .menuStyle(.borderlessButton)
        .onHover { setHoveredItem(.displayPicker, hovering: $0) }
    }

    private var modeSegmentedControl: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(InteractionMode.allCases) { mode in
                    let isSelected = controller.interactionMode == mode
                    let tooltipItem: ToolbarTooltipItem = (mode == .liveView) ? .modeLiveView : .modeInteractive
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            controller.interactionMode = mode
                        }
                        if mode == .interactive && !controller.hasAccessibilityPermission {
                            controller.requestAccessibilityPermission()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode == .liveView ? "eye" : "cursorarrow.click.2")
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            Text(mode.shortTitle)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(
                            isSelected
                                ? (mode == .interactive ? Color.white : Color.primary)
                                : Color.secondary
                        )
                        .background {
                            if isSelected {
                                if mode == .interactive {
                                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                        .fill(Color(nsColor: .systemOrange))
                                        .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 0.5)
                                } else {
                                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 0.5)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { setHoveredItem(tooltipItem, hovering: $0) }
                }
            }

            if !hkPrefix.isEmpty {
                Text("\(hkPrefix)I")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                    )
                    .padding(.trailing, 3)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Video Preview Area & Floating macOS Overlays
    private var videoPreviewArea: some View {
        GeometryReader { geo in
            let fittedRect = aspectFittedRect(aspectRatio: currentAspectRatio, in: geo.size)
            let topOverlayInset: CGFloat = (controller.autoHideToolbar && controller.shouldShowWindowChrome) ? (Self.headerHeight + 8) : 8

            ZStack(alignment: .topLeading) {
                VideoSurfaceRepresentable(
                    aspectRatio: currentAspectRatio,
                    interactionMode: controller.interactionMode,
                    isLoupeActive: controller.isLoupeCurrentlyActive,
                    loupeNormalizedPoint: controller.activeLoupeNormalizedPoint,
                    loupeZoomFactor: controller.loupeZoomFactor,
                    loupeDiameter: controller.loupeDiameter,
                    loupeBorderColor: controller.cursorHighlightColor.nsColor
                )
                .frame(width: geo.size.width, height: geo.size.height)

                // Click / Teleport Ripple Effects
                ForEach(controller.activeRipples) { ripple in
                    let rx = fittedRect.minX + ripple.normalizedPoint.x * fittedRect.width
                    let ry = fittedRect.minY + ripple.normalizedPoint.y * fittedRect.height
                    RippleCircleView(color: ripple.isRightClick ? .orange : controller.cursorHighlightColor.color)
                        .position(x: rx, y: ry)
                        .allowsHitTesting(false)
                }

                // Live Cursor Highlight Ring
                if controller.showCursorHighlight && controller.isCursorOnTargetDisplay {
                    let cx = fittedRect.minX + controller.cursorNormalizedPosition.x * fittedRect.width
                    let cy = fittedRect.minY + controller.cursorNormalizedPosition.y * fittedRect.height
                    let ringSize = controller.cursorHighlightSize * (controller.isMousePressed ? 0.78 : 1.0)

                    ZStack {
                        Circle()
                            .stroke(Color.black.opacity(0.72), lineWidth: 4.0)
                            .frame(width: ringSize + 2.5, height: ringSize + 2.5)

                        Circle()
                            .fill(controller.cursorHighlightColor.color.opacity(controller.isMousePressed ? 0.30 : 0.15))
                            .frame(width: ringSize, height: ringSize)

                        Circle()
                            .stroke(controller.cursorHighlightColor.color, lineWidth: controller.isMousePressed ? 3.2 : 2.4)
                            .frame(width: ringSize, height: ringSize)
                            .shadow(color: controller.cursorHighlightColor.color.opacity(0.75), radius: 6)

                        Circle()
                            .fill(controller.isMousePressed ? Color.white : controller.cursorHighlightColor.color)
                            .frame(width: 5.5, height: 5.5)
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.75), lineWidth: 1)
                            )
                    }
                    .position(x: cx, y: cy)
                    .animation(.easeOut(duration: 0.08), value: controller.isMousePressed)
                    .allowsHitTesting(false)
                } else if controller.showCursorHighlight && !controller.isCursorOnTargetDisplay {
                    let ex = fittedRect.minX + controller.offscreenEdgePosition.x * fittedRect.width
                    let ey = fittedRect.minY + controller.offscreenEdgePosition.y * fittedRect.height

                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 15, height: 15)
                        Circle()
                            .stroke(controller.cursorHighlightColor.color.opacity(0.85), lineWidth: 2)
                            .frame(width: 13, height: 13)
                    }
                    .position(x: ex, y: ey)
                    .allowsHitTesting(false)
                }

                // Interactive Mode Hover Reticle
                if controller.interactionMode == .interactive, let hoverPt = controller.hoverNormalizedPoint {
                    let hx = fittedRect.minX + hoverPt.x * fittedRect.width
                    let hy = fittedRect.minY + hoverPt.y * fittedRect.height

                    ZStack {
                        Circle()
                            .stroke(Color.orange.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 22, height: 22)
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                    }
                    .position(x: hx, y: hy)
                    .allowsHitTesting(false)
                }

                // Top Floating Vibrancy Status Pills (Blackout / Click-Through / Single-Monitor Info)
                VStack(spacing: 6) {
                    if overlayManager.isBlackoutEnabled {
                        Button {
                            overlayManager.isBlackoutEnabled = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "eye.slash.circle.fill")
                                    .foregroundStyle(Color(nsColor: .systemPurple))
                                Text("Đang che máy chiếu với khán giả • Bạn vẫn thao tác riêng tư được (Nhấn để mở)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color(nsColor: .systemPurple).opacity(0.75), lineWidth: 1.2)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                    }

                    if controller.isClickThroughEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.up.braille.fill")
                                .foregroundStyle(Color(nsColor: .systemCyan))
                            Text("Xuyên chuột đang bật • Giữ ⌥⌘ để kéo cửa sổ\(hkPrefix.isEmpty ? "" : " • \(hkPrefix)T để tắt")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .systemCyan).opacity(0.55), lineWidth: 1)
                        )
                        .allowsHitTesting(false)
                    } else if !captureManager.hasExternalDisplay && captureManager.isCapturing && !overlayManager.isBlackoutEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color(nsColor: .systemYellow))
                            Text("Chế độ 1 màn hình — Cắm thêm máy chiếu để tự động chuyển sang màn hình phụ")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 2)
                        .allowsHitTesting(false)
                    }
                    Spacer()
                }
                .padding(.top, topOverlayInset)
                .frame(maxWidth: .infinity)

                // Floating QuickTime-style Bottom HUD Capsule (Window Controls + Shortcuts + FPS)
                VStack {
                    Spacer()
                    floatingBottomHUD
                        .opacity(showFloatingBottomHUD ? 1.0 : 0.0)
                        .offset(y: showFloatingBottomHUD ? 0 : 6)
                        .allowsHitTesting(showFloatingBottomHUD)
                }
                .padding(.bottom, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.18), value: showFloatingBottomHUD)

                // Stopped & Permission Native Glass Cards
                if captureManager.isStoppedByUser {
                    stoppedOverlay
                } else if !captureManager.hasScreenRecordingPermission && !captureManager.isCapturing {
                    permissionOverlay
                }

                // Instant Feature Note Tooltip Card
                if let hoveredItem = controller.hoveredToolbarItem {
                    toolbarTooltipOverlay(for: hoveredItem, topInset: topOverlayInset)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Floating Bottom HUD Capsule (Labeled Ergonomic Toggles + Shortcuts)
    private var floatingBottomHUD: some View {
        HStack(spacing: 8) {
            // Left: Live Cursor / Laser Telemetry
            if overlayManager.isAudienceLaserEnabled {
                Circle()
                    .fill(Color(nsColor: .systemRed))
                    .frame(width: 7, height: 7)
                Text("Laser khán giả")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else if controller.isCursorOnTargetDisplay {
                Circle()
                    .fill(controller.cursorHighlightColor.color)
                    .frame(width: 7, height: 7)
                Text("Chuột: \(Int(controller.cursorPixelPosition.x))×\(Int(controller.cursorPixelPosition.y))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 6.5, height: 6.5)
                Text(controller.interactionMode == .liveView ? "Nhấp đúp: Nhảy chuột" : "Click hình: Thao tác")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            hudDivider

            // Center: Labeled Window Controls with Shortcuts
            HStack(spacing: 4) {
                hudLabeledPill(
                    item: .aspectRatioLock,
                    icon: "aspectratio",
                    label: "Tỷ lệ",
                    shortcut: nil,
                    isActive: controller.isAspectRatioLocked
                ) {
                    controller.isAspectRatioLocked.toggle()
                }

                hudLabeledPill(
                    item: .autoHideChrome,
                    icon: "pip",
                    label: "Tràn viền",
                    shortcut: hkPrefix.isEmpty ? nil : "\(hkPrefix)H",
                    isActive: controller.autoHideToolbar
                ) {
                    controller.autoHideToolbar.toggle()
                }

                hudLabeledPill(
                    item: .hideFromDock,
                    icon: "dock.rectangle",
                    label: "Ẩn Dock",
                    shortcut: nil,
                    isActive: controller.hideFromDock
                ) {
                    controller.hideFromDock.toggle()
                }

                hudLabeledPill(
                    item: .quickHideWindow,
                    icon: "eye.slash",
                    label: "Ẩn cửa sổ",
                    shortcut: hkPrefix.isEmpty ? nil : "\(hkPrefix)M",
                    isActive: false
                ) {
                    ScreenPeekAppDelegate.shared?.togglePreviewWindow()
                }
            }

            hudDivider

            // Right: Accessibility Warning or FPS Telemetry
            if controller.interactionMode == .interactive && !controller.hasAccessibilityPermission {
                Button {
                    controller.requestAccessibilityPermission()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                        Text("Cấp Trợ năng")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                    }
                }
                .buttonStyle(.plain)
            } else if captureManager.isCapturing {
                Text("\(captureManager.currentFPS) FPS")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5.5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 10, x: 0, y: 4)
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 13)
    }

    private func hudLabeledPill(
        item: ToolbarTooltipItem,
        icon: String,
        label: String,
        shortcut: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = controller.hoveredToolbarItem == item
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 10.5, weight: isActive ? .semibold : .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .opacity(0.85)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
            }
            .foregroundStyle(isActive ? Color(nsColor: .systemCyan) : Color.white.opacity(hovered ? 0.96 : 0.76))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? Color(nsColor: .systemCyan).opacity(hovered ? 0.28 : 0.18)
                            : (hovered ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { setHoveredItem(item, hovering: $0) }
    }

    // MARK: - Instant Feature Tooltip Logic (macOS Vibrancy Card)
    private func setHoveredItem(_ item: ToolbarTooltipItem, hovering: Bool) {
        if hovering {
            controller.hoveredToolbarItem = item
        } else if controller.hoveredToolbarItem == item {
            controller.hoveredToolbarItem = nil
        }
    }

    private func tooltipContent(for item: ToolbarTooltipItem) -> (title: String, badge: String?, badgeColor: Color, description: String) {
        switch item {
        case .displayPicker:
            return (
                title: "Chọn màn hình hiển thị",
                badge: captureManager.selectedDisplay?.resolutionText,
                badgeColor: .accentColor,
                description: "Chuyển nhanh giữa các màn hình đang kết nối, làm mới máy chiếu hoặc kiểm tra cập nhật."
            )
        case .stopResume:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)S"
            return (
                title: captureManager.isCapturing ? "Tạm dừng thu hình" : "Tiếp tục thu hình",
                badge: (captureManager.isCapturing ? "Đang phát" : "Đã dừng") + hk,
                badgeColor: captureManager.isCapturing ? .orange : .green,
                description: captureManager.isCapturing
                    ? "Ngắt hoàn toàn luồng thu hình & tắt biểu tượng chia sẻ màu tím trên thanh Menu Bar macOS để tiết kiệm pin."
                    : "Khởi động lại luồng truyền hình 60 FPS của màn hình đã chọn."
            )
        case .modeLiveView:
            let active = controller.interactionMode == .liveView
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)I"
            return (
                title: "Chế độ Chỉ xem (Live View)",
                badge: active ? "Đang dùng\(hk)" : "Nhấn để chuyển\(hk)",
                badgeColor: active ? .accentColor : .secondary,
                description: "Quan sát vị trí chuột trên màn hình phụ mà không cần ngoái đầu. Nhấp đúp vào hình để nhảy nhanh chuột sang đó."
            )
        case .modeInteractive:
            let active = controller.interactionMode == .interactive
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)I"
            return (
                title: "Điều khiển trực tiếp (Interactive)",
                badge: active ? "Đang dùng\(hk)" : "Nhấn để chuyển\(hk)",
                badgeColor: active ? .orange : .secondary,
                description: "Click trái/phải, kéo thả hoặc cuộn trang ngay trong cửa sổ nhỏ này để thao tác trực tiếp lên màn hình phụ."
            )
        case .teleportCursor:
            return (
                title: "Nhảy nhanh chuột qua lại 2 màn hình",
                badge: hkPrefix.isEmpty ? nil : "\(hkPrefix)C",
                badgeColor: .accentColor,
                description: "Đưa tức thì con trỏ chuột sang giữa màn hình phụ (hoặc nhấn \(hkPrefix.isEmpty ? "lần nữa" : "\(hkPrefix)C lần nữa") để đưa chuột quay về lại laptop)."
            )
        case .loupeZoom:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)Z"
            return (
                title: "Kính lúp phóng đại GPU (Zoom Loupe)",
                badge: controller.loupeMode.label + hk,
                badgeColor: controller.loupeMode == .off ? .secondary : .green,
                description: "Phóng đại sắc nét \(String(format: "%.1fx", controller.loupeZoomFactor)) vùng chữ & nút nhỏ quanh mũi chuột. Giữ phím ⌥ Option để soi nhanh hoặc nhấn để chuyển chế độ."
            )
        case .audienceLaser:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)L"
            return (
                title: "Đèn Laser / Spotlight khán giả",
                badge: (overlayManager.isAudienceLaserEnabled ? "Đang BẬT" : "Đang TẮT") + hk,
                badgeColor: overlayManager.isAudienceLaserEnabled ? .red : .secondary,
                description: "Chiếu trực tiếp tia Laser đỏ hoặc đèn Spotlight lên màn hình máy chiếu thật giúp khán giả nhìn rõ điểm bạn trỏ."
            )
        case .privacyBlackout:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)B"
            return (
                title: "Màn che bảo mật máy chiếu (Blackout)",
                badge: (overlayManager.isBlackoutEnabled ? "Đang CHE" : "Đang TẮT") + hk,
                badgeColor: overlayManager.isBlackoutEnabled ? .purple : .secondary,
                description: "Hiển thị màn hình chờ lịch sự với khán giả trên máy chiếu, trong khi bạn VẪN thấy và thao tác riêng tư trong ScreenPeek."
            )
        case .clickThrough:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)T"
            return (
                title: "Chế độ Xuyên chuột (Click-Through)",
                badge: (controller.isClickThroughEnabled ? "Đang BẬT" : "Đang TẮT") + hk,
                badgeColor: controller.isClickThroughEnabled ? .cyan : .secondary,
                description: "Cho phép click xuyên qua cửa sổ ScreenPeek xuống ứng dụng bên dưới trên laptop (giữ ⌥⌘ khi cần nắm kéo cửa sổ)."
            )
        case .alwaysOnTop:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)P"
            return (
                title: "Ghim cửa sổ nổi (Always on Top)",
                badge: (controller.isAlwaysOnTop ? "Đang GHIM" : "Đang TẮT") + hk,
                badgeColor: controller.isAlwaysOnTop ? .accentColor : .secondary,
                description: "Giữ cửa sổ ScreenPeek luôn nổi phía trên Keynote, PowerPoint hoặc trình duyệt khi đang thuyết trình."
            )
        case .updateAvailable:
            let ver = updateManager.availableRelease?.versionString ?? ""
            return (
                title: "Đã có bản cập nhật mới v\(ver) trên GitHub!",
                badge: "Sẵn sàng tải",
                badgeColor: .blue,
                description: "Nhấn để xem chi tiết ghi chú phát hành và tự động tải về, cài đặt & khởi động lại ngay trong ứng dụng."
            )
        case .openSettings:
            return (
                title: "Cài đặt ScreenPeek & Cập nhật GitHub",
                badge: "⌘,",
                badgeColor: .accentColor,
                description: "Mở cửa sổ Cài đặt chuẩn macOS: tùy chỉnh Vòng sáng chuột, Kính lúp, Đèn Laser, Phím tắt và Cập nhật tự động qua GitHub."
            )
        case .launchAtLoginToggle:
            return (
                title: "Khởi động cùng macOS (Launch at Login)",
                badge: controller.launchAtLogin ? "Đang BẬT" : "Đang TẮT",
                badgeColor: controller.launchAtLogin ? .green : .secondary,
                description: "Tự động mở ứng dụng ScreenPeek ngay khi đăng nhập vào máy Mac để luôn sẵn sàng cho buổi thuyết trình."
            )
        case .showWindowOnLaunchToggle:
            let openHK = hkKey("M", fallback: "Menu Bar")
            return (
                title: "Bật bảng này khi khởi động",
                badge: controller.showWindowOnLaunch ? "Mở ngay" : "Chạy ngầm",
                badgeColor: controller.showWindowOnLaunch ? .accentColor : .orange,
                description: controller.showWindowOnLaunch
                    ? "Tự động hiện bảng xem trước này ngay khi mở ứng dụng. Bỏ chọn nếu bạn muốn chạy ngầm trên thanh Menu Bar (0% CPU/Pin) và chỉ mở khi nhấn \(openHK)."
                    : "Ứng dụng sẽ khởi động êm trên thanh Menu Bar (0% CPU/Pin, chưa mở bảng này) cho đến khi bạn nhấn \(openHK)."
            )
        case .headerHideFromDock:
            return (
                title: "Ẩn biểu tượng khỏi thanh Dock",
                badge: controller.hideFromDock ? "Đang ẨN" : "Đang HIỆN",
                badgeColor: controller.hideFromDock ? .cyan : .secondary,
                description: "Giữ thanh Dock gọn gàng trong lúc thuyết trình; bạn luôn mở lại nhanh được qua thanh Menu Bar hoặc phím tắt."
            )
        case .aspectRatioLock:
            return (
                title: "Khóa tỷ lệ khung hình (Aspect Ratio)",
                badge: controller.isAspectRatioLocked ? "Đang KHÓA" : "Tự do",
                badgeColor: controller.isAspectRatioLocked ? .cyan : .secondary,
                description: "Giữ cửa sổ co dãn đúng tỷ lệ chuẩn của màn hình kết nối để hình ảnh sắc nét, không có viền đen."
            )
        case .autoHideChrome:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)H"
            return (
                title: "Giao diện tràn viền tự ẩn (Picture-in-Picture)",
                badge: (controller.autoHideToolbar ? "Đang BẬT" : "Đang TẮT") + hk,
                badgeColor: controller.autoHideToolbar ? .cyan : .secondary,
                description: "Ẩn hoàn toàn thanh công cụ và nút cửa sổ khi rời chuột để hiển thị 100% khung hình tràn viền như QuickTime PiP."
            )
        case .hideFromDock:
            return (
                title: "Ẩn biểu tượng khỏi thanh Dock",
                badge: controller.hideFromDock ? "Đang ẨN" : "Đang HIỆN",
                badgeColor: controller.hideFromDock ? .cyan : .secondary,
                description: "Giữ thanh Dock gọn gàng trong lúc thuyết trình; bạn luôn mở lại nhanh được qua thanh Menu Bar hoặc phím tắt."
            )
        case .quickHideWindow:
            let hk = hkPrefix.isEmpty ? "Menu Bar" : "\(hkPrefix)M"
            return (
                title: "Ẩn nhanh cửa sổ ScreenPeek",
                badge: hk,
                badgeColor: .accentColor,
                description: "Tạm ẩn cửa sổ xem trước và ngắt thu hình tiết kiệm pin. Nhấn lại \(hk) bất kỳ lúc nào để mở lại ngay."
            )
        }
    }

    private func toolbarTooltipOverlay(for item: ToolbarTooltipItem, topInset: CGFloat) -> some View {
        let info = tooltipContent(for: item)
        return VStack {
            if item.isBottomHUDItem {
                Spacer()
            }

            HStack {
                if !item.isLeftAligned && !item.isBottomHUDItem {
                    Spacer(minLength: 14)
                } else if item.isBottomHUDItem {
                    Spacer(minLength: 14)
                }

                HStack(alignment: .top, spacing: 10) {
                    SystemSettingsIconBadge(
                        systemName: item.iconName,
                        color: info.badgeColor == .secondary ? Color(nsColor: .systemGray) : info.badgeColor,
                        size: 26
                    )
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(info.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)

                            if let badge = info.badge {
                                Text(badge)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule()
                                            .fill(info.badgeColor == .secondary ? Color.white.opacity(0.18) : info.badgeColor.opacity(0.85))
                                    )
                            }
                        }

                        Text(info.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 365, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.42), radius: 12, x: 0, y: 5)

                if item.isLeftAligned || item.isBottomHUDItem {
                    Spacer(minLength: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, item.isBottomHUDItem ? 0 : topInset)
            .padding(.bottom, item.isBottomHUDItem ? 48 : 0)

            if !item.isBottomHUDItem {
                Spacer()
            }
        }
    }

    // MARK: - Native macOS Vibrancy Empty / Stopped / Permission Overlays
    private var stoppedOverlay: some View {
        ZStack {
            Color.black.opacity(0.75)

            VStack(spacing: 14) {
                Image(systemName: "pause.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Đã tạm dừng chia sẻ màn hình")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Luồng thu hình và bộ đếm nền đã được ngắt hoàn toàn để tiết kiệm tối đa pin MacBook.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)

                HStack(spacing: 10) {
                    Button {
                        captureManager.resumeSharing()
                    } label: {
                        Label("Tiếp tục hiển thị (\(hkKey("S", fallback: "Chạy")))", systemImage: "play.fill")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        ScreenPeekAppDelegate.shared?.openSettingsWindow(tab: .general)
                    } label: {
                        Label("Cài đặt (⌘,)", systemImage: "gearshape")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 2)
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.82)

            VStack(spacing: 14) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 42))
                    .foregroundStyle(Color(nsColor: .systemOrange))

                Text("Cần cấp quyền Ghi màn hình")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Bật quyền cho ScreenPeek trong Cài đặt Hệ thống › Quyền riêng tư & Bảo mật › Ghi màn hình để xem trực tiếp màn hình kết nối.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                HStack(spacing: 10) {
                    Button {
                        captureManager.requestScreenCapturePermission()
                    } label: {
                        Label("Mở Cài đặt Hệ thống", systemImage: "lock.open.display")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        captureManager.checkPermissionAndStart()
                    } label: {
                        Label("Thử lại", systemImage: "arrow.clockwise")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 2)
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RippleCircleView: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2.5)
                .frame(width: 42, height: 42)
                .opacity(0.85)
            Circle()
                .fill(color.opacity(0.24))
                .frame(width: 22, height: 22)
        }
    }
}
