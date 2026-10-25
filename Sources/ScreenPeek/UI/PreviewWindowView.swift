import SwiftUI
import AppKit

struct PreviewWindowView: View {
    @ObservedObject var captureManager = ScreenCaptureManager.shared
    @ObservedObject var controller = CursorAndInputController.shared

    static let toolbarHeight: CGFloat = 42
    static let bottomBarHeight: CGFloat = 24
    static var chromeHeight: CGFloat { toolbarHeight + bottomBarHeight }

    private var currentAspectRatio: CGFloat {
        captureManager.selectedDisplay?.aspectRatio ?? (16.0 / 9.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
                .frame(height: Self.toolbarHeight)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            videoPreviewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            Divider()

            bottomStatusBar
                .frame(height: Self.bottomBarHeight)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 360, minHeight: 240)
    }

    // MARK: - Top Toolbar
    private var topToolbar: some View {
        HStack(spacing: 8) {
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
                        .font(.system(size: 12, weight: .semibold))
                    Text(captureManager.selectedDisplay?.name ?? "Chọn màn hình")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if let disp = captureManager.selectedDisplay {
                        Text(disp.isBuiltin ? "(Chính)" : "(Phụ)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(disp.isBuiltin ? .secondary : Color.accentColor)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .onHover { hovering in
                setHoveredItem(.displayPicker, hovering: hovering)
            }
            .help("Chọn màn hình muốn xem trực tiếp")

            // Stop / Resume Sharing Button
            if captureManager.isCapturing {
                Button {
                    captureManager.userStopSharing()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Dừng")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    setHoveredItem(.stopResume, hovering: hovering)
                }
                .help("Dừng chia sẻ màn hình (tắt biểu tượng chia sẻ trên thanh Menu Bar)")
            } else {
                Button {
                    captureManager.resumeSharing()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Tiếp tục")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    setHoveredItem(.stopResume, hovering: hovering)
                }
                .help("Bắt đầu hiển thị lại màn hình")
            }

            Spacer(minLength: 4)

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
                        HStack(spacing: 4) {
                            Image(systemName: mode == .liveView ? "eye.fill" : "cursorarrow.click.2")
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.shortTitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? (mode == .interactive ? Color.orange : Color.accentColor) : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        setHoveredItem(tooltipItem, hovering: hovering)
                    }
                    .help(mode.subtitle)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.08))
            )

            // Quick Teleport Cursor to External Display Center
            Button {
                controller.teleportCursorToCenterOfTargetDisplay()
            } label: {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(controller.hoveredToolbarItem == .teleportCursor ? Color.primary.opacity(0.16) : Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                setHoveredItem(.teleportCursor, hovering: hovering)
            }
            .help("Đưa chuột nhảy ngay sang giữa màn hình này (Phím tắt: ⌘⇧C)")

            // Cursor Highlight Toggle & Settings Popover
            Button {
                controller.showSettingsPopover.toggle()
            } label: {
                Image(systemName: controller.showCursorHighlight ? "scope" : "circle.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(controller.showCursorHighlight ? controller.cursorHighlightColor.color : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(controller.hoveredToolbarItem == .cursorSettings ? Color.primary.opacity(0.18) : (controller.showCursorHighlight ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05)))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                setHoveredItem(.cursorSettings, hovering: hovering)
            }
            .help("Tuỳ chỉnh vòng tròn nổi bật con trỏ chuột & cài đặt hiển thị")
            .popover(isPresented: $controller.showSettingsPopover, arrowEdge: .bottom) {
                cursorSettingsPopover
            }

            // Aspect Ratio Lock Toggle
            Button {
                controller.isAspectRatioLocked.toggle()
            } label: {
                Image(systemName: "aspectratio.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(controller.isAspectRatioLocked ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(controller.hoveredToolbarItem == .aspectRatioLock ? Color.accentColor.opacity(0.24) : (controller.isAspectRatioLocked ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                setHoveredItem(.aspectRatioLock, hovering: hovering)
            }
            .help(controller.isAspectRatioLocked ? "Đang khóa tỷ lệ khung hình theo màn hình phụ (Nhấn để co dãn tự do)" : "Co dãn tự do (Nhấn để khóa đúng tỷ lệ màn hình phụ)")

            // Always on Top Toggle
            Button {
                controller.isAlwaysOnTop.toggle()
            } label: {
                Image(systemName: controller.isAlwaysOnTop ? "pin.fill" : "pin.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(controller.isAlwaysOnTop ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(controller.hoveredToolbarItem == .alwaysOnTop ? Color.accentColor.opacity(0.24) : (controller.isAlwaysOnTop ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                setHoveredItem(.alwaysOnTop, hovering: hovering)
            }
            .help(controller.isAlwaysOnTop ? "Đang ghim cửa sổ luôn nổi trên cùng (Always on Top)" : "Bấm để ghim cửa sổ luôn nổi trên cùng")

            // Hide from Dock Toggle
            Button {
                controller.hideFromDock.toggle()
            } label: {
                Image(systemName: controller.hideFromDock ? "dock.arrow.down.rectangle" : "dock.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(controller.hideFromDock ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(controller.hoveredToolbarItem == .hideFromDock ? Color.accentColor.opacity(0.24) : (controller.hideFromDock ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                setHoveredItem(.hideFromDock, hovering: hovering)
            }
            .help(controller.hideFromDock ? "Đang ẩn biểu tượng trên thanh Dock" : "Đang hiện biểu tượng trên thanh Dock")
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Video Preview Area + Overlays
    private var videoPreviewArea: some View {
        GeometryReader { geo in
            let fittedRect = aspectFittedRect(aspectRatio: currentAspectRatio, in: geo.size)

            ZStack(alignment: .topLeading) {
                VideoSurfaceRepresentable(
                    aspectRatio: currentAspectRatio,
                    interactionMode: controller.interactionMode
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

                // Live Cursor Highlight Ring when physical mouse is on the target display
                if controller.showCursorHighlight && controller.isCursorOnTargetDisplay {
                    let cx = fittedRect.minX + controller.cursorNormalizedPosition.x * fittedRect.width
                    let cy = fittedRect.minY + controller.cursorNormalizedPosition.y * fittedRect.height
                    let ringSize = controller.cursorHighlightSize * (controller.isMousePressed ? 0.78 : 1.0)

                    ZStack {
                        // Outer dark contrast halo so it stands out on bright white slides
                        Circle()
                            .stroke(Color.black.opacity(0.75), lineWidth: 4.5)
                            .frame(width: ringSize + 3, height: ringSize + 3)

                        // Glowing colored ring
                        Circle()
                            .fill(controller.cursorHighlightColor.color.opacity(controller.isMousePressed ? 0.32 : 0.16))
                            .frame(width: ringSize, height: ringSize)

                        Circle()
                            .stroke(controller.cursorHighlightColor.color, lineWidth: controller.isMousePressed ? 3.5 : 2.5)
                            .frame(width: ringSize, height: ringSize)
                            .shadow(color: controller.cursorHighlightColor.color.opacity(0.8), radius: 6)

                        // Center precision dot
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
                    // Subtle edge indicator showing which border the mouse will enter from
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

                // Single-screen Notice Badge (when no external monitor is connected yet)
                if !captureManager.hasExternalDisplay && captureManager.isCapturing {
                    VStack {
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
                        .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                }

                // Stopped Overlay when user clicks Stop Sharing
                if captureManager.isStoppedByUser {
                    stoppedOverlay
                } else if !captureManager.hasScreenRecordingPermission && !captureManager.isCapturing {
                    // Permission Overlay if Screen Recording is not granted
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
            let badge = captureManager.selectedDisplay?.resolutionText
            return (
                title: "Chọn màn hình hiển thị",
                badge: badge,
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
            return (
                title: "Chế độ Chỉ xem (Live View)",
                badge: active ? "Đang dùng • ⌘⇧I" : "Phím tắt: ⌘⇧I",
                badgeColor: active ? .accentColor : .secondary,
                description: "Bạn tự rê chuột sang màn hình phụ và nhìn vị trí chuột qua cửa sổ này. Mẹo: Nhấp đúp vào hình để nhảy nhanh chuột sang vị trí đó."
            )
        case .modeInteractive:
            let active = controller.interactionMode == .interactive
            return (
                title: "Chế độ Điều khiển trực tiếp (Interactive)",
                badge: active ? "Đang dùng • ⌘⇧I" : "Phím tắt: ⌘⇧I",
                badgeColor: active ? .orange : .secondary,
                description: "Click trái, click phải, kéo thả hoặc cuộn trang ngay trong cửa sổ nhỏ này để thao tác trực tiếp lên màn hình phụ."
            )
        case .teleportCursor:
            return (
                title: "Đưa chuột sang màn hình phụ",
                badge: "Phím tắt: ⌘⇧C",
                badgeColor: .accentColor,
                description: "Nhảy tức thì con trỏ chuột sang giữa màn hình phụ. Nhấn ⌘⇧C lần nữa để đưa chuột quay về màn hình chính."
            )
        case .cursorSettings:
            return (
                title: "Vòng tròn nổi bật chuột & Cài đặt",
                badge: controller.showCursorHighlight ? "Đang BẬT" : "Đang TẮT",
                badgeColor: controller.showCursorHighlight ? controller.cursorHighlightColor.color : .secondary,
                description: "Nhấn để mở bảng tuỳ chỉnh: Bật/tắt vòng sáng quanh chuột, chọn màu sắc, kích thước vòng sáng và độ trong suốt cửa sổ."
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
                description: "Ẩn biểu tượng ScreenPeek khỏi thanh Dock cho gọn gàng (bạn vẫn điều khiển được qua thanh Menu Bar phía trên hoặc phím tắt ⌘⇧M)."
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
                .frame(maxWidth: 320, alignment: .leading)
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

    // MARK: - Stopped Overlay
    private var stoppedOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("Đã dừng chia sẻ màn hình")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text("Bạn đã bấm Stop Sharing. Ứng dụng sẽ không tự động thu màn hình nữa cho tới khi bạn bấm Tiếp tục.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

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

    // MARK: - Permission Overlay
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
            if controller.isCursorOnTargetDisplay {
                Circle()
                    .fill(controller.cursorHighlightColor.color)
                    .frame(width: 7, height: 7)
                Text("Chuột đang trên màn hình này (\(Int(controller.cursorPixelPosition.x)), \(Int(controller.cursorPixelPosition.y)))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 7, height: 7)
                Text(controller.interactionMode == .liveView
                     ? "Chuột ở màn hình khác • Nhấp đúp vào hình để nhảy chuột sang"
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

    // MARK: - Settings Popover
    private var cursorSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cài đặt Con trỏ & Cửa sổ")
                .font(.system(size: 13, weight: .bold))

            Toggle("Làm nổi bật vị trí chuột (Cursor Highlight)", isOn: $controller.showCursorHighlight)
                .font(.system(size: 12))

            if controller.showCursorHighlight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Màu vòng tròn con trỏ:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(CursorHighlightColor.allCases) { item in
                            Button {
                                controller.cursorHighlightColor = item
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 12, height: 12)
                                    Text(item.label)
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(controller.cursorHighlightColor == item ? item.color : Color.secondary.opacity(0.25), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Kích thước vòng sáng:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(controller.cursorHighlightSize)) px")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    Slider(value: $controller.cursorHighlightSize, in: 22...76, step: 2)
                }
            }

            Divider()

            Toggle("Chế độ Điều khiển: Giữ chuột ở lại cửa sổ nhỏ sau khi click", isOn: $controller.returnCursorAfterClick)
                .font(.system(size: 12))
            Text("Khi bật, bạn có thể click liên tiếp các nút trên màn hình phụ ngay từ cửa sổ nhỏ mà không cần kéo chuột quay về.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Độ trong suốt cửa sổ:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(controller.windowOpacity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $controller.windowOpacity, in: 0.45...1.0, step: 0.05)
            }

            Divider()

            Toggle("Ẩn biểu tượng ứng dụng trên thanh Dock", isOn: $controller.hideFromDock)
                .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 340)
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
