import SwiftUI
import AppKit

struct PreviewWindowView: View {
    @ObservedObject var captureManager = ScreenCaptureManager.shared
    @ObservedObject var controller = CursorAndInputController.shared
    @ObservedObject var overlayManager = ProjectorOverlayManager.shared

    static let toolbarHeight: CGFloat = 42
    static let bottomBarHeight: CGFloat = 24
    static var chromeHeight: CGFloat { toolbarHeight + bottomBarHeight }

    private var currentAspectRatio: CGFloat {
        captureManager.selectedDisplay?.aspectRatio ?? (16.0 / 9.0)
    }

    private var hkPrefix: String {
        let p = controller.hotKeyPreset.symbolPrefix
        return p.isEmpty ? "" : p
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.shouldShowWindowChrome {
                topToolbar
                    .frame(height: Self.toolbarHeight)
                    .background(Color(nsColor: .windowBackgroundColor))

                Divider()
            }

            videoPreviewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            if controller.shouldShowWindowChrome {
                Divider()

                bottomStatusBar
                    .frame(height: Self.bottomBarHeight)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 420, minHeight: 240)
        .onHover { inside in
            controller.isMouseInsidePreviewWindow = inside
            if !inside {
                controller.hoveredToolbarItem = nil
            }
        }
    }

    // MARK: - Top Toolbar
    private var topToolbar: some View {
        HStack(spacing: 6) {
            // Display Picker Menu
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
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(captureManager.isCapturing ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Image(systemName: (captureManager.selectedDisplay?.isBuiltin == false) ? "display" : "laptopcomputer")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(captureManager.selectedDisplay?.name ?? "Màn hình")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 130, alignment: .leading)
                    if let disp = captureManager.selectedDisplay {
                        Text(disp.isBuiltin ? "(Chính)" : "(Phụ)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(disp.isBuiltin ? .secondary : Color.accentColor)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .onHover { setHoveredItem(.displayPicker, hovering: $0) }

            // Stop / Resume Sharing Button
            if captureManager.isCapturing {
                Button {
                    captureManager.userStopSharing()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Dừng")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .onHover { setHoveredItem(.stopResume, hovering: $0) }
            } else {
                Button {
                    captureManager.resumeSharing()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Tiếp tục")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
                .onHover { setHoveredItem(.stopResume, hovering: $0) }
            }

            Spacer(minLength: 2)

            // Mode Switcher (Live View vs Interactive Control)
            HStack(spacing: 2) {
                ForEach(InteractionMode.allCases) { mode in
                    let isSelected = controller.interactionMode == mode
                    let tooltipItem: ToolbarTooltipItem = (mode == .liveView) ? .modeLiveView : .modeInteractive
                    Button {
                        controller.interactionMode = mode
                        if mode == .interactive && !controller.hasAccessibilityPermission {
                            controller.requestAccessibilityPermission()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: mode == .liveView ? "eye.fill" : "cursorarrow.click.2")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(mode.shortTitle)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? (mode == .interactive ? Color.orange : Color.accentColor) : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .onHover { setHoveredItem(tooltipItem, hovering: $0) }
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.08))
            )

            // 1. Teleport Cursor
            toolbarButton(
                item: .teleportCursor,
                icon: "location.viewfinder",
                isActive: false,
                activeColor: .accentColor
            ) {
                controller.teleportCursorToCenterOfTargetDisplay()
            }

            // 2. Zoom Loupe Cycle (Off -> Hold Option -> Always)
            toolbarButton(
                item: .loupeZoom,
                icon: controller.loupeMode == .off ? "magnifyingglass" : "plus.magnifyingglass",
                isActive: controller.loupeMode != .off,
                activeColor: controller.loupeMode == .always ? .green : .accentColor
            ) {
                switch controller.loupeMode {
                case .off: controller.loupeMode = .holdOption
                case .holdOption: controller.loupeMode = .always
                case .always: controller.loupeMode = .off
                }
            }

            // 3. Audience Laser Pointer / Spotlight on External Projector
            toolbarButton(
                item: .audienceLaser,
                icon: "light.beacon.max.fill",
                isActive: overlayManager.isAudienceLaserEnabled,
                activeColor: .red
            ) {
                overlayManager.isAudienceLaserEnabled.toggle()
            }

            // 4. Privacy Blackout Shield on External Projector
            toolbarButton(
                item: .privacyBlackout,
                icon: overlayManager.isBlackoutEnabled ? "eye.slash.circle.fill" : "eye.slash",
                isActive: overlayManager.isBlackoutEnabled,
                activeColor: .purple
            ) {
                overlayManager.isBlackoutEnabled.toggle()
            }

            // 5. Auto-Hide PiP Chrome
            toolbarButton(
                item: .autoHideChrome,
                icon: "rectangle.expand.vertical",
                isActive: controller.autoHideToolbar,
                activeColor: .accentColor
            ) {
                controller.autoHideToolbar.toggle()
            }

            // 6. Cursor Highlight & Master Settings Popover
            Button {
                controller.showSettingsPopover.toggle()
            } label: {
                Image(systemName: controller.showCursorHighlight ? "scope" : "slider.horizontal.3")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(controller.showCursorHighlight ? controller.cursorHighlightColor.color : .secondary)
                    .frame(width: 25, height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(controller.hoveredToolbarItem == .cursorSettings ? Color.primary.opacity(0.18) : (controller.showCursorHighlight ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05)))
                    )
            }
            .buttonStyle(.plain)
            .onHover { setHoveredItem(.cursorSettings, hovering: $0) }
            .popover(isPresented: $controller.showSettingsPopover, arrowEdge: .bottom) {
                cursorSettingsPopover
            }

            // 7. Aspect Ratio Lock
            toolbarButton(
                item: .aspectRatioLock,
                icon: "aspectratio.fill",
                isActive: controller.isAspectRatioLocked,
                activeColor: .accentColor
            ) {
                controller.isAspectRatioLocked.toggle()
            }

            // 8. Always on Top
            toolbarButton(
                item: .alwaysOnTop,
                icon: controller.isAlwaysOnTop ? "pin.fill" : "pin.slash",
                isActive: controller.isAlwaysOnTop,
                activeColor: .accentColor
            ) {
                controller.isAlwaysOnTop.toggle()
            }

            // 9. Hide from Dock
            toolbarButton(
                item: .hideFromDock,
                icon: controller.hideFromDock ? "dock.arrow.down.rectangle" : "dock.rectangle",
                isActive: controller.hideFromDock,
                activeColor: .accentColor
            ) {
                controller.hideFromDock.toggle()
            }
        }
        .padding(.horizontal, 8)
    }

    private func toolbarButton(
        item: ToolbarTooltipItem,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = controller.hoveredToolbarItem == item
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? activeColor : .secondary)
                .frame(width: 25, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered
                              ? activeColor.opacity(0.24)
                              : (isActive ? activeColor.opacity(0.15) : Color.primary.opacity(0.05)))
                )
        }
        .buttonStyle(.plain)
        .onHover { setHoveredItem(item, hovering: $0) }
    }

    // MARK: - Video Preview Area + Overlays
    private var videoPreviewArea: some View {
        GeometryReader { geo in
            let fittedRect = aspectFittedRect(aspectRatio: currentAspectRatio, in: geo.size)

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
                            .stroke(Color.black.opacity(0.75), lineWidth: 4.5)
                            .frame(width: ringSize + 3, height: ringSize + 3)

                        Circle()
                            .fill(controller.cursorHighlightColor.color.opacity(controller.isMousePressed ? 0.32 : 0.16))
                            .frame(width: ringSize, height: ringSize)

                        Circle()
                            .stroke(controller.cursorHighlightColor.color, lineWidth: controller.isMousePressed ? 3.5 : 2.5)
                            .frame(width: ringSize, height: ringSize)
                            .shadow(color: controller.cursorHighlightColor.color.opacity(0.8), radius: 6)

                        Circle()
                            .fill(controller.isMousePressed ? Color.white : controller.cursorHighlightColor.color)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.8), lineWidth: 1)
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
                            .frame(width: 16, height: 16)
                        Circle()
                            .stroke(controller.cursorHighlightColor.color.opacity(0.85), lineWidth: 2)
                            .frame(width: 14, height: 14)
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
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                    }
                    .position(x: hx, y: hy)
                    .allowsHitTesting(false)
                }

                // Active Status Pills (Privacy Blackout / Audience Laser / Click-Through / Single-Screen Info)
                VStack(spacing: 6) {
                    if overlayManager.isBlackoutEnabled {
                        Button {
                            overlayManager.isBlackoutEnabled = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "eye.slash.circle.fill")
                                    .foregroundStyle(.purple)
                                Text("Đang che màn hình phụ với khán giả (Bạn vẫn thấy & thao tác được) • Bấm để mở lại")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.84))
                                    .overlay(Capsule().stroke(Color.purple.opacity(0.8), lineWidth: 1.5))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if controller.isClickThroughEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.up.braille.fill")
                                .foregroundStyle(.cyan)
                            Text("Chế độ Xuyên chuột đang bật (Giữ ⌥⌘ để nắm cửa sổ\(hkPrefix.isEmpty ? "" : " • \(hkPrefix)T để tắt"))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.78))
                                .overlay(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                        )
                        .allowsHitTesting(false)
                    } else if !captureManager.hasExternalDisplay && captureManager.isCapturing && !overlayManager.isBlackoutEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.yellow)
                            Text("Chưa cắm màn hình phụ — Đang hiển thị màn hình chính để thử nghiệm")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.72))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        )
                        .allowsHitTesting(false)
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity)

                // Stopped Overlay
                if captureManager.isStoppedByUser {
                    stoppedOverlay
                } else if !captureManager.hasScreenRecordingPermission && !captureManager.isCapturing {
                    permissionOverlay
                }

                // Instant Feature Note Tooltip when hovering toolbar buttons
                if let hoveredItem = controller.hoveredToolbarItem, !controller.showSettingsPopover {
                    toolbarTooltipOverlay(for: hoveredItem)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Instant Feature Tooltip Logic
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
                description: "Chuyển đổi giữa các màn hình đang kết nối hoặc làm mới danh sách khi cắm thêm máy chiếu / màn hình phụ."
            )
        case .stopResume:
            return (
                title: captureManager.isCapturing ? "Dừng chia sẻ màn hình" : "Tiếp tục chia sẻ màn hình",
                badge: captureManager.isCapturing ? "Đang thu" : "Đã dừng",
                badgeColor: captureManager.isCapturing ? .red : .green,
                description: captureManager.isCapturing
                    ? "Tạm dừng truyền hình ảnh và tắt biểu tượng chia sẻ màu tím trên thanh Menu Bar của macOS."
                    : "Bắt đầu truyền hình trực tiếp lại nội dung của màn hình đã chọn."
            )
        case .modeLiveView:
            let active = controller.interactionMode == .liveView
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)I"
            return (
                title: "Chế độ Chỉ xem (Live View)",
                badge: active ? "Đang dùng\(hk)" : "Nhấn để bật\(hk)",
                badgeColor: active ? .accentColor : .secondary,
                description: "Bạn tự rê chuột sang màn hình phụ và nhìn vị trí chuột qua cửa sổ này. Nhấp đúp vào hình để nhảy nhanh chuột sang vị trí đó."
            )
        case .modeInteractive:
            let active = controller.interactionMode == .interactive
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)I"
            return (
                title: "Chế độ Điều khiển trực tiếp (Interactive)",
                badge: active ? "Đang dùng\(hk)" : "Nhấn để bật\(hk)",
                badgeColor: active ? .orange : .secondary,
                description: "Click trái, click phải, kéo thả hoặc cuộn trang ngay trong cửa sổ nhỏ này để thao tác trực tiếp lên màn hình phụ."
            )
        case .teleportCursor:
            return (
                title: "Đưa chuột sang màn hình phụ",
                badge: hkPrefix.isEmpty ? nil : "Phím tắt: \(hkPrefix)C",
                badgeColor: .accentColor,
                description: "Nhảy tức thì con trỏ chuột sang giữa màn hình phụ (hoặc nhấn phím tắt lần nữa để đưa chuột quay về màn hình chính)."
            )
        case .loupeZoom:
            return (
                title: "Kính lúp phóng đại quanh chuột (Zoom Loupe)",
                badge: controller.loupeMode.label,
                badgeColor: controller.loupeMode == .off ? .secondary : .green,
                description: "Phóng to \(String(format: "%.1fx", controller.loupeZoomFactor)) vùng chữ & nút bấm quanh mũi chuột giúp dễ đọc khi cửa sổ thu nhỏ. Nhấn để chuyển: Tắt → Giữ phím ⌥ Option → Luôn bật."
            )
        case .audienceLaser:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)L"
            return (
                title: "Đèn Laser / Spotlight trên màn hình chiếu",
                badge: (overlayManager.isAudienceLaserEnabled ? "Đang BẬT" : "Đang TẮT") + hk,
                badgeColor: overlayManager.isAudienceLaserEnabled ? .red : .secondary,
                description: "Chiếu trực tiếp tia Laser đỏ (hoặc đèn Spotlight làm tối nền) lên màn hình máy chiếu thật để khán giả dưới hội trường nhìn rõ điểm bạn đang trỏ."
            )
        case .privacyBlackout:
            let hk = hkPrefix.isEmpty ? "" : " • \(hkPrefix)B"
            return (
                title: "Màn che bảo mật màn hình phụ (Blackout)",
                badge: (overlayManager.isBlackoutEnabled ? "Đang CHE" : "Đang TẮT") + hk,
                badgeColor: overlayManager.isBlackoutEnabled ? .purple : .secondary,
                description: "Phủ màn hình chờ lịch sự lên máy chiếu với khán giả trong khi bạn VẪN nhìn thấy và thao tác riêng tư trên màn hình phụ ngay trong cửa sổ ScreenPeek!"
            )
        case .autoHideChrome:
            return (
                title: "Chế độ Tối giản tự ẩn thanh công cụ (PiP)",
                badge: controller.autoHideToolbar ? "Đang BẬT" : "Đang TẮT",
                badgeColor: controller.autoHideToolbar ? .accentColor : .secondary,
                description: "Tự động ẩn thanh công cụ và viền cửa sổ khi chuột rời khỏi ScreenPeek (tràn viền giống Picture-in-Picture), tự hiện lại ngay khi rê chuột vào."
            )
        case .clickThrough:
            return (
                title: "Chế độ Xuyên chuột (Click-Through)",
                badge: controller.isClickThroughEnabled ? "Đang BẬT" : "Đang TẮT",
                badgeColor: controller.isClickThroughEnabled ? .cyan : .secondary,
                description: "Cho phép click xuyên qua cửa sổ ScreenPeek xuống ứng dụng bên dưới trên laptop."
            )
        case .cursorSettings:
            return (
                title: "Vòng sáng con trỏ & Bảng Cài đặt nâng cao",
                badge: controller.showCursorHighlight ? "Vòng sáng: BẬT" : "Vòng sáng: TẮT",
                badgeColor: controller.showCursorHighlight ? controller.cursorHighlightColor.color : .secondary,
                description: "Tuỳ chỉnh màu/cỡ vòng sáng chuột, Kính lúp, kiểu Đèn Laser, Xuyên chuột, Hít 4 góc màn hình, Tổ hợp phím tắt và Khởi động cùng máy."
            )
        case .aspectRatioLock:
            return (
                title: "Khóa tỷ lệ khung hình (Aspect Ratio)",
                badge: controller.isAspectRatioLocked ? "Đang BẬT" : "Đang TẮT",
                badgeColor: controller.isAspectRatioLocked ? .accentColor : .secondary,
                description: "Giữ cửa sổ co dãn đúng tỷ lệ thực của màn hình kết nối để không bị méo hình. Nhấn để bật/tắt co dãn tự do."
            )
        case .alwaysOnTop:
            return (
                title: "Luôn nổi trên cùng (Always on Top)",
                badge: controller.isAlwaysOnTop ? "Đang BẬT" : "Đang TẮT",
                badgeColor: controller.isAlwaysOnTop ? .accentColor : .secondary,
                description: "Ghim cửa sổ nổi phía trên tất cả ứng dụng khác để bạn luôn quan sát được màn hình phụ khi thuyết trình."
            )
        case .hideFromDock:
            return (
                title: "Ẩn biểu tượng trên thanh Dock",
                badge: controller.hideFromDock ? "Đang ẨN" : "Đang HIỆN",
                badgeColor: controller.hideFromDock ? .accentColor : .secondary,
                description: "Ẩn biểu tượng ScreenPeek khỏi thanh Dock cho gọn gàng (vẫn mở nhanh qua thanh Menu Bar hoặc phím tắt)."
            )
        }
    }

    private func toolbarTooltipOverlay(for item: ToolbarTooltipItem) -> some View {
        let info = tooltipContent(for: item)
        return VStack {
            HStack {
                if !item.isLeftAligned {
                    Spacer(minLength: 12)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(info.badgeColor == .secondary ? Color.white : info.badgeColor)

                        Text(info.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)

                        if let badge = info.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(info.badgeColor.opacity(0.85))
                                )
                        }
                    }

                    Text(info.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: 345, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(white: 0.11).opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
                )

                if item.isLeftAligned {
                    Spacer(minLength: 12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Spacer()
        }
    }

    // MARK: - Stopped & Permission Overlays
    private var stoppedOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("Đã dừng chia sẻ màn hình")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text("Bạn đã bấm Stop Sharing. Ứng dụng đã ngắt hoàn toàn luồng thu hình & bộ đếm nền để tiết kiệm pin.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)

            HStack(spacing: 10) {
                Button {
                    captureManager.resumeSharing()
                } label: {
                    Label("Tiếp tục hiển thị", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Thoát ScreenPeek", systemImage: "power")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
    }

    private var permissionOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Cần quyền Ghi màn hình (Screen Recording)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text("Để hiển thị trực tiếp nội dung của màn hình kết nối, hãy cấp quyền cho ScreenPeek trong Cài đặt Hệ thống > Quyền riêng tư & Bảo mật > Ghi màn hình.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button {
                    captureManager.requestScreenCapturePermission()
                } label: {
                    Label("Mở Cài đặt & Cấp quyền", systemImage: "lock.open.display")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    captureManager.checkPermissionAndStart()
                } label: {
                    Label("Thử kết nối lại", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack(spacing: 8) {
            if overlayManager.isAudienceLaserEnabled {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Text("🔴 Laser khán giả đang bật (\(overlayManager.laserStyle.label))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if controller.isCursorOnTargetDisplay {
                Circle()
                    .fill(controller.cursorHighlightColor.color)
                    .frame(width: 7, height: 7)
                Text("Chuột trên màn hình này (\(Int(controller.cursorPixelPosition.x)), \(Int(controller.cursorPixelPosition.y)))\(controller.loupeMode == .holdOption ? " • Giữ ⌥ để soi kính lúp" : "")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 7, height: 7)
                Text(controller.interactionMode == .liveView
                     ? "Chuột ở màn hình khác • Nhấp đúp vào hình\(hkPrefix.isEmpty ? "" : " (hoặc \(hkPrefix)C)") để nhảy chuột sang"
                     : "Chế độ Điều khiển: Click/cuộn trực tiếp trên hình để thao tác")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if controller.interactionMode == .interactive && !controller.hasAccessibilityPermission {
                Button {
                    controller.requestAccessibilityPermission()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Cấp quyền Trợ năng để Click từ xa")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
            } else if captureManager.isCapturing {
                Text("\(captureManager.currentFPS) FPS • \(captureManager.selectedDisplay?.resolutionText ?? "")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Comprehensive Settings Popover
    private var cursorSettingsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cài đặt Thuyết trình & Cửa sổ")
                    .font(.system(size: 13.5, weight: .bold))

                // 1. Cursor Highlight
                Group {
                    Toggle("Vòng tròn nổi bật chuột (Cursor Highlight)", isOn: $controller.showCursorHighlight)
                        .font(.system(size: 12, weight: .medium))

                    if controller.showCursorHighlight {
                        HStack(spacing: 6) {
                            ForEach(CursorHighlightColor.allCases) { item in
                                Button {
                                    controller.cursorHighlightColor = item
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle().fill(item.color).frame(width: 10, height: 10)
                                        Text(item.label).font(.system(size: 10.5))
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(controller.cursorHighlightColor == item ? item.color : Color.secondary.opacity(0.25), lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            Text("Cỡ vòng sáng:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Slider(value: $controller.cursorHighlightSize, in: 22...76, step: 2)
                            Text("\(Int(controller.cursorHighlightSize))px")
                                .font(.system(size: 10.5, design: .monospaced))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                Divider()

                // 2. Zoom Loupe Magnifier
                Group {
                    HStack {
                        Text("Kính lúp phóng đại quanh chuột:")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Picker("", selection: $controller.loupeMode) {
                            ForEach(LoupeMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 145)
                    }

                    if controller.loupeMode != .off {
                        HStack {
                            Text("Độ phóng đại:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Slider(value: $controller.loupeZoomFactor, in: 1.8...4.5, step: 0.2)
                            Text(String(format: "%.1fx", controller.loupeZoomFactor))
                                .font(.system(size: 10.5, design: .monospaced))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                Divider()

                // 3. Audience Laser & Blackout
                Group {
                    HStack {
                        Toggle("Đèn Laser chiếu cho khán giả", isOn: $overlayManager.isAudienceLaserEnabled)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Picker("", selection: $overlayManager.laserStyle) {
                            ForEach(AudienceLaserStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 155)
                    }

                    Toggle("Màn che bảo mật màn hình phụ (Blackout)", isOn: $overlayManager.isBlackoutEnabled)
                        .font(.system(size: 12, weight: .medium))
                    TextField("Nội dung thông báo chờ...", text: $overlayManager.blackoutMessage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }

                Divider()

                // 4. PiP Window Ergonomics (Auto-hide, Click-Through, Snap Corners)
                Group {
                    Toggle("Tự ẩn thanh công cụ khi chuột rời cửa sổ (PiP)", isOn: $controller.autoHideToolbar)
                        .font(.system(size: 12))

                    Toggle("Chế độ Xuyên chuột (Click-Through Ghost)", isOn: $controller.isClickThroughEnabled)
                        .font(.system(size: 12))

                    Toggle("Tự hít gọn vào 4 góc màn hình khi kéo thả", isOn: $controller.snapToCorners)
                        .font(.system(size: 12))

                    HStack(spacing: 6) {
                        Text("Đặt nhanh góc:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        ForEach(ScreenCorner.allCases) { corner in
                            Button {
                                controller.onSnapCornerRequested?(corner)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: corner.iconName)
                                        .font(.system(size: 11))
                                    Text(corner.label)
                                        .font(.system(size: 10))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Độ trong suốt:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(value: $controller.windowOpacity, in: 0.45...1.0, step: 0.05)
                        Text("\(Int(controller.windowOpacity * 100))%")
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Divider()

                // 5. Hotkeys & System Integration
                Group {
                    Toggle("Điều khiển từ xa: Giữ chuột ở cửa sổ nhỏ sau khi click", isOn: $controller.returnCursorAfterClick)
                        .font(.system(size: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Phím bổ trợ cho Phím tắt toàn cục:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $controller.hotKeyPreset) {
                            ForEach(HotKeyModifierPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        if !hkPrefix.isEmpty {
                            Text("\(hkPrefix)M: Ẩn/Hiện • \(hkPrefix)C: Đổi màn hình chuột • \(hkPrefix)I: Đổi chế độ • \(hkPrefix)L: Laser • \(hkPrefix)B: Màn che • \(hkPrefix)T: Xuyên chuột")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Toggle("Ẩn biểu tượng ứng dụng trên thanh Dock", isOn: $controller.hideFromDock)
                        .font(.system(size: 12))

                    Toggle("Tự khởi động cùng macOS (Launch at Login)", isOn: Binding(
                        get: { controller.launchAtLogin },
                        set: { controller.setLaunchAtLogin($0) }
                    ))
                    .font(.system(size: 12))
                }
            }
            .padding(14)
        }
        .frame(width: 390, height: 470)
    }
}

private struct RippleCircleView: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2.5)
                .frame(width: 44, height: 44)
                .opacity(0.85)
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 24, height: 24)
        }
    }
}
