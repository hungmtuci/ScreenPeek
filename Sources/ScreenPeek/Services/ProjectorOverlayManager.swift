import Foundation
import AppKit
import SwiftUI

@MainActor
final class ProjectorOverlayManager: ObservableObject {
    static let shared = ProjectorOverlayManager()

    @Published var isAudienceLaserEnabled: Bool = false {
        didSet {
            updateOverlayWindows()
            CursorAndInputController.shared.refreshTrackingTimerState()
        }
    }

    @Published var laserStyle: AudienceLaserStyle {
        didSet {
            UserDefaults.standard.set(laserStyle.rawValue, forKey: "ScreenPeek.laserStyle")
        }
    }

    @Published var isBlackoutEnabled: Bool = false {
        didSet {
            updateOverlayWindows()
        }
    }

    @Published var blackoutMessage: String {
        didSet {
            UserDefaults.standard.set(blackoutMessage, forKey: "ScreenPeek.blackoutMessage")
        }
    }

    private var laserWindow: NSWindow?
    private var blackoutWindow: NSWindow?

    private init() {
        let savedStyle = UserDefaults.standard.string(forKey: "ScreenPeek.laserStyle") ?? AudienceLaserStyle.redLaser.rawValue
        self.laserStyle = AudienceLaserStyle(rawValue: savedStyle) ?? .redLaser

        let savedMsg = UserDefaults.standard.string(forKey: "ScreenPeek.blackoutMessage")
        self.blackoutMessage = (savedMsg?.isEmpty == false) ? savedMsg! : "Đang chuẩn bị nội dung tiếp theo — Vui lòng đợi trong giây lát..."
    }

    func updateOverlayWindows() {
        updateOverlayWindows(for: ScreenCaptureManager.shared.selectedDisplay)
    }

    func updateOverlayWindows(for targetDisplay: DisplayInfo?) {
        guard let targetDisplay else {
            hideLaserWindow()
            hideBlackoutWindow()
            return
        }

        if isAudienceLaserEnabled {
            showOrUpdateLaserWindow(on: targetDisplay)
        } else {
            hideLaserWindow()
        }

        if isBlackoutEnabled {
            showOrUpdateBlackoutWindow(on: targetDisplay)
        } else {
            hideBlackoutWindow()
        }
    }

    func disableAllOverlays() {
        isAudienceLaserEnabled = false
        isBlackoutEnabled = false
    }

    private func showOrUpdateLaserWindow(on display: DisplayInfo) {
        if laserWindow == nil {
            let win = NSWindow(
                contentRect: display.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isReleasedWhenClosed = false
            win.isRestorable = false
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.level = .statusBar
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            win.contentView = NSHostingView(rootView: AudienceLaserOverlayView())
            self.laserWindow = win
        }
        laserWindow?.setFrame(display.frame, display: true)
        laserWindow?.orderFrontRegardless()
    }

    private func hideLaserWindow() {
        laserWindow?.orderOut(nil)
    }

    private func showOrUpdateBlackoutWindow(on display: DisplayInfo) {
        if blackoutWindow == nil {
            let win = NSWindow(
                contentRect: display.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isReleasedWhenClosed = false
            win.isRestorable = false
            win.isOpaque = true
            win.backgroundColor = .black
            win.hasShadow = false
            // Click-through so presenter can still click/interact with apps underneath via ScreenPeek!
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            win.contentView = NSHostingView(rootView: AudienceBlackoutOverlayView())
            self.blackoutWindow = win
        }

        // If preview window sits on the same physical screen (single-monitor test), keep blackout right below ScreenPeek's floating window so the presenter never loses sight of ScreenPeek!
        let previewScreenFrame = ScreenPeekAppDelegate.shared?.previewWindowScreenFrame
        let isSameScreenAsPreview: Bool = {
            guard let pf = previewScreenFrame else { return false }
            return abs(pf.minX - display.frame.minX) < 5 && abs(pf.minY - display.frame.minY) < 5
        }()

        if isSameScreenAsPreview {
            blackoutWindow?.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        } else {
            blackoutWindow?.level = .screenSaver
        }

        blackoutWindow?.setFrame(display.frame, display: true)
        blackoutWindow?.orderFrontRegardless()
    }

    private func hideBlackoutWindow() {
        blackoutWindow?.orderOut(nil)
    }
}

private struct AudienceLaserOverlayView: View {
    @ObservedObject var controller = CursorAndInputController.shared
    @ObservedObject var overlayManager = ProjectorOverlayManager.shared

    var body: some View {
        GeometryReader { geo in
            if controller.isCursorOnTargetDisplay {
                let x = controller.cursorNormalizedPosition.x * geo.size.width
                let y = controller.cursorNormalizedPosition.y * geo.size.height

                if overlayManager.laserStyle == .redLaser {
                    ZStack {
                        // Outer soft laser glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.red.opacity(0.65),
                                        Color.red.opacity(0.22),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: controller.isMousePressed ? 38 : 28
                                )
                            )
                            .frame(width: 76, height: 76)

                        // Outer laser ring
                        Circle()
                            .stroke(Color.red.opacity(0.9), lineWidth: 2.5)
                            .frame(width: controller.isMousePressed ? 34 : 24, height: controller.isMousePressed ? 34 : 24)

                        // Core bright laser dot
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().stroke(Color.red, lineWidth: 3)
                            )
                            .shadow(color: .red, radius: 8)
                    }
                    .position(x: x, y: y)
                } else {
                    // Presenter Spotlight: dim entire screen except a bright circle around the cursor
                    Canvas { context, size in
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.black.opacity(0.58))
                        )
                        let radius: CGFloat = controller.isMousePressed ? 110 : 140
                        let spotlightRect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.blendMode = .destinationOut
                        context.fill(Path(ellipseIn: spotlightRect), with: .color(.white))

                        context.blendMode = .normal
                        context.stroke(
                            Path(ellipseIn: spotlightRect),
                            with: .color(Color.yellow.opacity(0.85)),
                            lineWidth: 3
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AudienceBlackoutOverlayView: View {
    @ObservedObject var overlayManager = ProjectorOverlayManager.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.09, green: 0.11, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white.opacity(0.65))

                Text(overlayManager.blackoutMessage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
