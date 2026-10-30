import SwiftUI
import AppKit

struct SettingsWindowView: View {
    @ObservedObject var captureManager = ScreenCaptureManager.shared
    @ObservedObject var controller = CursorAndInputController.shared
    @ObservedObject var overlayManager = ProjectorOverlayManager.shared
    @ObservedObject var updateManager = GitHubUpdateManager.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebarPane
                .frame(width: 215)

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - macOS System Settings Vibrancy Sidebar
    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top area for native traffic lights + Window drag
            ZStack(alignment: .bottomLeading) {
                WindowDragArea()
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ScreenPeek")
                            .font(.system(size: 13.5, weight: .bold))
                        Text("Phiên bản \(updateManager.currentVersion)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .frame(height: 78)

            VStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarRow(for: tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Quick status card at bottom of sidebar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(captureManager.isCapturing ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(captureManager.isCapturing ? "Đang truyền hình trực tiếp" : "Đã tạm dừng thu hình")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let disp = captureManager.selectedDisplay {
                    Text("\(disp.name) • \(disp.resolutionText)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        let isSelected = controller.selectedSettingsTab == tab
        return Button {
            controller.selectedSettingsTab = tab
        } label: {
            HStack(spacing: 10) {
                SystemSettingsIconBadge(
                    systemName: tab.iconName,
                    color: tab.badgeColor,
                    size: 24
                )

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Spacer(minLength: 4)

                if tab == .updates && updateManager.hasUpdateAvailable {
                    Text("Mới")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.28) : Color.red)
                        )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Detail Pane
    private var detailPane: some View {
        VStack(spacing: 0) {
            // Unified macOS Header Bar
            ZStack {
                WindowDragArea()
                HStack(spacing: 10) {
                    SystemSettingsIconBadge(
                        systemName: controller.selectedSettingsTab.iconName,
                        color: controller.selectedSettingsTab.badgeColor,
                        size: 22
                    )
                    Text(controller.selectedSettingsTab.title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()

                    if controller.selectedSettingsTab == .updates {
                        Button {
                            updateManager.openGitHubRepoInBrowser()
                        } label: {
                            Label("GitHub", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 46)
            .background(.regularMaterial)

            Divider()

            Group {
                switch controller.selectedSettingsTab {
                case .general:
                    generalSettingsForm
                case .cursorAndLoupe:
                    cursorAndLoupeForm
                case .presentation:
                    presentationForm
                case .shortcuts:
                    shortcutsForm
                case .updates:
                    updatesForm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Tab 1: General Settings
    private var generalSettingsForm: some View {
        Form {
            Section("Màn hình & Chế độ tương tác") {
                Picker("Màn hình theo dõi", selection: Binding(
                    get: { captureManager.selectedDisplay?.id ?? 0 },
                    set: { newID in captureManager.selectedDisplayID = newID }
                )) {
                    ForEach(captureManager.availableDisplays) { display in
                        Text(display.displayLabel).tag(display.id)
                    }
                }

                Picker("Chế độ điều khiển", selection: $controller.interactionMode) {
                    ForEach(InteractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                LabeledContent("Trạng thái truyền hình") {
                    HStack(spacing: 8) {
                        Button {
                            captureManager.refreshDisplays(autoSelectExternal: true)
                            Task { await captureManager.restartCaptureStream() }
                        } label: {
                            Label("Làm mới màn hình", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)

                        if captureManager.isCapturing {
                            Button(role: .destructive) {
                                captureManager.userStopSharing()
                            } label: {
                                Label("Tạm dừng", systemImage: "pause.fill")
                            }
                            .controlSize(.small)
                        } else {
                            Button {
                                captureManager.resumeSharing()
                            } label: {
                                Label("Tiếp tục", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("Cửa sổ nổi & Picture-in-Picture") {
                Toggle("Luôn nổi trên cùng các cửa sổ khác (Always on Top)", isOn: $controller.isAlwaysOnTop)
                Toggle("Khóa đúng tỷ lệ khung hình thực của màn hình kết nối", isOn: $controller.isAspectRatioLocked)
                Toggle("Tự động ẩn thanh công cụ tràn viền khi rời chuột (PiP)", isOn: $controller.autoHideToolbar)
                Toggle("Chế độ Xuyên chuột (Click-Through — Giữ ⌥⌘ để nắm cửa sổ)", isOn: $controller.isClickThroughEnabled)
                Toggle("Tự động hít gọn vào 4 góc màn hình khi kéo thả", isOn: $controller.snapToCorners)

                LabeledContent("Đặt nhanh vị trí góc") {
                    HStack(spacing: 6) {
                        ForEach(ScreenCorner.allCases) { corner in
                            Button {
                                controller.onSnapCornerRequested?(corner)
                            } label: {
                                Label(corner.label, systemImage: corner.iconName)
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                LabeledContent("Độ trong suốt cửa sổ (\(Int(controller.windowOpacity * 100))%)") {
                    Slider(value: $controller.windowOpacity, in: 0.45...1.0, step: 0.05)
                        .frame(width: 190)
                }
            }

            Section("Hệ thống & Quyền macOS") {
                Toggle("Ẩn biểu tượng ứng dụng trên thanh Dock", isOn: $controller.hideFromDock)

                Toggle("Tự khởi động cùng macOS (Launch at Login)", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))

                LabeledContent("Quyền Ghi màn hình (Screen Recording)") {
                    HStack(spacing: 6) {
                        Image(systemName: captureManager.hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(captureManager.hasScreenRecordingPermission ? .green : .orange)
                        Text(captureManager.hasScreenRecordingPermission ? "Đã cấp quyền" : "Chưa cấp quyền")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        if !captureManager.hasScreenRecordingPermission {
                            Button("Mở Cài đặt") {
                                captureManager.requestScreenCapturePermission()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                LabeledContent("Quyền Trợ năng (Điều khiển click từ xa)") {
                    HStack(spacing: 6) {
                        Image(systemName: controller.hasAccessibilityPermission ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(controller.hasAccessibilityPermission ? .green : .orange)
                        Text(controller.hasAccessibilityPermission ? "Đã cấp quyền" : "Chưa cấp")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        if !controller.hasAccessibilityPermission {
                            Button("Cấp quyền") {
                                controller.requestAccessibilityPermission()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab 2: Cursor & Loupe Settings
    private var cursorAndLoupeForm: some View {
        Form {
            Section("Vòng sáng định vị con trỏ (Cursor Highlight)") {
                Toggle("Hiển thị vòng sáng nổi bật quanh vị trí chuột thật", isOn: $controller.showCursorHighlight)

                if controller.showCursorHighlight {
                    LabeledContent("Màu sắc vòng sáng") {
                        HStack(spacing: 8) {
                            ForEach(CursorHighlightColor.allCases) { item in
                                let selected = controller.cursorHighlightColor == item
                                Button {
                                    controller.cursorHighlightColor = item
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(item.color)
                                            .frame(width: 11, height: 11)
                                        Text(item.label)
                                            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selected ? item.color.opacity(0.16) : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(selected ? item.color : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    LabeledContent("Đường kính vòng sáng (\(Int(controller.cursorHighlightSize)) px)") {
                        Slider(value: $controller.cursorHighlightSize, in: 22...76, step: 2)
                            .frame(width: 210)
                    }

                    // Live Visual Preview Card
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Xem trước trực quan")
                                .font(.system(size: 12, weight: .medium))
                            Text("Giúp bạn nhận diện ngay vị trí chuột trên slide thuyết trình mà không cần căng mắt tìm.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.14), Color(white: 0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )

                            Circle()
                                .fill(controller.cursorHighlightColor.color.opacity(0.18))
                                .frame(width: controller.cursorHighlightSize, height: controller.cursorHighlightSize)
                            Circle()
                                .stroke(controller.cursorHighlightColor.color, lineWidth: 2.5)
                                .frame(width: controller.cursorHighlightSize, height: controller.cursorHighlightSize)
                                .shadow(color: controller.cursorHighlightColor.color.opacity(0.75), radius: 5)
                            Image(systemName: "cursorarrow")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 3, y: 4)
                        }
                        .frame(width: 130, height: 84)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Kính lúp phóng đại quanh chuột (GPU Zoom Loupe)") {
                Picker("Chế độ kích hoạt kính lúp", selection: $controller.loupeMode) {
                    ForEach(LoupeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                LabeledContent("Mức độ phóng đại (\(String(format: "%.1fx", controller.loupeZoomFactor)))") {
                    Slider(value: $controller.loupeZoomFactor, in: 1.8...4.5, step: 0.2)
                        .frame(width: 210)
                }

                LabeledContent("Kích thước ống kính (\(Int(controller.loupeDiameter)) px)") {
                    Slider(value: $controller.loupeDiameter, in: 110...240, step: 10)
                        .frame(width: 210)
                }
            }

            Section("Hành vi điều khiển từ xa (Interactive Mode)") {
                Toggle("Giữ nguyên con trỏ chuột tại cửa sổ nhỏ trên laptop sau khi click từ xa", isOn: $controller.returnCursorAfterClick)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab 3: Presentation Tools
    private var presentationForm: some View {
        Form {
            Section {
                Toggle("Bật Đèn chỉ dẫn trực tiếp trên màn hình máy chiếu", isOn: $overlayManager.isAudienceLaserEnabled)

                Picker("Kiểu hiển thị cho khán giả", selection: $overlayManager.laserStyle) {
                    ForEach(AudienceLaserStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            } header: {
                Text("Đèn Laser & Spotlight Khán giả")
            } footer: {
                Text("Chiếu trực tiếp tia Laser đỏ rực hoặc quầng sáng Spotlight làm tối nền xung quanh lên màn hình phụ thực tế để khán giả dưới hội trường theo dõi dễ dàng.")
            }

            Section {
                Toggle("Bật Màn che bảo mật trên màn hình chiếu (Privacy Blackout)", isOn: $overlayManager.isBlackoutEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Thông điệp chờ hiển thị cho khán giả:")
                        .font(.system(size: 12, weight: .medium))

                    HStack(spacing: 8) {
                        TextField("Nhập thông điệp lịch sự hiển thị trên máy chiếu...", text: $overlayManager.blackoutMessage)
                            .textFieldStyle(.roundedBorder)

                        Button("Mặc định") {
                            overlayManager.blackoutMessage = "Đang chuẩn bị nội dung tiếp theo — Vui lòng đợi trong giây lát..."
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Màn che bảo mật (Privacy Blackout Shield)")
            } footer: {
                Text("Khi bật Màn che, khán giả nhìn lên máy chiếu chỉ thấy màn hình chờ lịch sự, trong khi bạn VẪN nhìn thấy và thao tác riêng tư bình thường với các ứng dụng bên dưới ngay trong cửa sổ ScreenPeek.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab 4: Global Shortcuts
    private var shortcutsForm: some View {
        Form {
            Section {
                Picker("Bộ phím bổ trợ (Modifiers)", selection: $controller.hotKeyPreset) {
                    ForEach(HotKeyModifierPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
            } header: {
                Text("Cấu hình phím tắt toàn cục")
            } footer: {
                Text("Mặc định sử dụng ⌃⌥ (Control + Option) để hoạt động tức thì từ bất kỳ ứng dụng nào mà không xung đột với phím tắt của Safari, Chrome hay Keynote.")
            }

            if controller.hotKeyPreset != .disabled {
                let mods = controller.hotKeyPreset.modifierKeycaps
                Section("Danh sách phím tắt đang hoạt động") {
                    shortcutRow(icon: "macwindow", title: "Hiện / Ẩn nhanh cửa sổ ScreenPeek", keys: mods + ["M"])
                    shortcutRow(icon: "location.viewfinder", title: "Chuyển nhanh con trỏ chuột qua lại 2 màn hình", keys: mods + ["C"])
                    shortcutRow(icon: "cursorarrow.click.2", title: "Đổi chế độ Chỉ xem ↔ Điều khiển trực tiếp", keys: mods + ["I"])
                    shortcutRow(icon: "light.beacon.max.fill", title: "Bật / Tắt Đèn Laser / Spotlight khán giả", keys: mods + ["L"])
                    shortcutRow(icon: "eye.slash.fill", title: "Bật / Tắt Màn che bảo mật máy chiếu (Blackout)", keys: mods + ["B"])
                    shortcutRow(icon: "hand.point.up.braille.fill", title: "Bật / Tắt Chế độ Xuyên chuột (Click-Through)", keys: mods + ["T"])
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(icon: String, title: String, keys: [String]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 12.5))
            Spacer()
            MacKeycapGroup(keys: keys)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tab 5: Software Update via GitHub Releases
    private var updatesForm: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("ScreenPeek")
                                .font(.system(size: 16, weight: .bold))
                            Text("v\(updateManager.currentVersion)")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                                .foregroundStyle(Color.accentColor)
                        }

                        Text("Nguồn cập nhật: github.com/\(GitHubUpdateManager.repoOwner)/\(GitHubUpdateManager.repoName)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        if let lastDate = updateManager.lastCheckedDate {
                            Text("Kiểm tra gần nhất: \(formattedDate(lastDate))")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if updateManager.state == .checking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Đang kiểm tra…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { await updateManager.checkForUpdates(userInitiated: true) }
                        } label: {
                            Label("Kiểm tra cập nhật", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.regular)
                    }
                }
                .padding(.vertical, 4)

                Toggle("Tự động kiểm tra bản cập nhật mới từ GitHub khi khởi động", isOn: $updateManager.autoCheckUpdates)
            } header: {
                Text("Cập nhật phần mềm (GitHub Releases)")
            }

            // Dynamic Update State Section
            Section("Trạng thái phiên bản") {
                updateStatusDetailContent
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateStatusDetailContent: some View {
        switch updateManager.state {
        case .idle:
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sẵn sàng kiểm tra bản cập nhật qua GitHub")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Nhấn \"Kiểm tra cập nhật\" để đối chiếu phiên bản hiện tại với bản phát hành mới nhất trên GitHub Releases.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Đang kết nối tới GitHub API để kiểm tra bản phát hành mới nhất…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)

        case .upToDate(let checkedAt):
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScreenPeek đang ở phiên bản mới nhất (v\(updateManager.currentVersion))")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Đã xác nhận đồng bộ với GitHub Releases lúc \(formattedDate(checkedAt)).")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

        case .updateAvailable(let release):
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Đã có phiên bản mới: \(release.title)")
                                .font(.system(size: 13.5, weight: .bold))
                            if let sizeText = release.formattedZipSize {
                                Text(sizeText)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                        }
                        Text("Phiên bản hiện tại: v\(updateManager.currentVersion) → Bản mới: v\(release.versionString)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ghi chú phát hành (Release Notes):")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(release.releaseNotes)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 70, maxHeight: 135)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        updateManager.downloadAndInstallUpdate()
                    } label: {
                        Label(
                            release.zipDownloadURL != nil ? "Cập nhật & Khởi động lại ngay" : "Tải bản mới trên GitHub",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        updateManager.openReleasePageInBrowser()
                    } label: {
                        Label("Xem trên GitHub", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)

        case .downloading(let progress, let downloadedMB, let totalMB):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Đang tải bản cập nhật từ GitHub Releases…")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("\(Int(progress * 100))% (\(String(format: "%.2f", downloadedMB)) / \(String(format: "%.2f", totalMB)) MB)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)

                HStack {
                    Spacer()
                    Button("Hủy tải") {
                        updateManager.cancelDownload()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 6)

        case .installing:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đang giải nén và cài đặt bản cập nhật…")
                        .font(.system(size: 13, weight: .semibold))
                    Text("ScreenPeek sẽ tự động thay thế phiên bản cũ và khởi động lại ngay trong giây lát.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

        case .downloadedToDownloadsFolder(let fileURL):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .foregroundStyle(.blue)
                    Text("Đã tải gói cập nhật về thư mục Downloads")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("Do ứng dụng hiện đang chạy trong thư mục chỉ đọc, gói cập nhật đã được lưu tại: \(fileURL.lastPathComponent)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Button("Hiển thị trong Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)

        case .error(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Không thể hoàn tất kiểm tra / cập nhật tự động")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await updateManager.checkForUpdates(userInitiated: true) }
                    } label: {
                        Label("Thử lại", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)

                    Button {
                        updateManager.openReleasePageInBrowser()
                    } label: {
                        Label("Mở trang GitHub Releases", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
