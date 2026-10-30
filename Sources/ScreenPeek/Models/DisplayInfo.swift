import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import Carbon

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect          // AppKit global coordinates (origin: bottom-left of primary screen)
    let quartzBounds: CGRect   // Quartz global coordinates (origin: top-left of primary screen)
    let pixelWidth: Int
    let pixelHeight: Int
    let isBuiltin: Bool
    let isMain: Bool

    var aspectRatio: CGFloat {
        guard frame.height > 0 else { return 16.0 / 9.0 }
        return frame.width / frame.height
    }

    var resolutionText: String {
        "\(Int(frame.width))×\(Int(frame.height))"
    }

    var badgeText: String {
        if !isBuiltin {
            return "Màn hình phụ"
        } else {
            return "Màn hình chính"
        }
    }

    var displayLabel: String {
        "\(name) (\(badgeText) • \(resolutionText))"
    }
}

enum InteractionMode: String, CaseIterable, Identifiable {
    case liveView = "liveView"
    case interactive = "interactive"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveView:
            return "Chỉ xem (Live View)"
        case .interactive:
            return "Điều khiển (Interactive)"
        }
    }

    var shortTitle: String {
        switch self {
        case .liveView:
            return "Chỉ xem"
        case .interactive:
            return "Điều khiển"
        }
    }

    var subtitle: String {
        switch self {
        case .liveView:
            return "Bạn tự di chuột sang màn hình phụ và quan sát vị trí chuột qua cửa sổ này. Nhấp đúp vào hình để nhảy nhanh chuột sang màn hình phụ."
        case .interactive:
            return "Click, kéo thả hoặc cuộn chuột ngay bên trong cửa sổ này để thao tác trực tiếp lên màn hình phụ."
        }
    }
}

enum CursorHighlightColor: String, CaseIterable, Identifiable {
    case yellow = "yellow"
    case red = "red"
    case cyan = "cyan"
    case green = "green"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Vàng nổi bật"
        case .red: return "Đỏ Laser"
        case .cyan: return "Xanh Cyan"
        case .green: return "Xanh Neon"
        }
    }

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .red: return Color(red: 1.0, green: 0.23, blue: 0.19)
        case .cyan: return Color(red: 0.20, green: 0.78, blue: 0.98)
        case .green: return Color(red: 0.19, green: 0.82, blue: 0.35)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor.systemYellow
        case .red: return NSColor.systemRed
        case .cyan: return NSColor.systemCyan
        case .green: return NSColor.systemGreen
        }
    }
}

enum LoupeMode: String, CaseIterable, Identifiable {
    case off = "off"
    case holdOption = "holdOption"
    case always = "always"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Tắt"
        case .holdOption: return "Giữ phím ⌥ Option"
        case .always: return "Luôn bật"
        }
    }
}

enum AudienceLaserStyle: String, CaseIterable, Identifiable {
    case redLaser = "redLaser"
    case spotlight = "spotlight"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .redLaser: return "Đèn Laser Đỏ"
        case .spotlight: return "Đèn sân khấu (Spotlight)"
        }
    }
}

enum HotKeyModifierPreset: String, CaseIterable, Identifiable {
    case controlOption = "controlOption"   // ⌃⌥ (Recommended — avoids Chrome/Safari ⌘⇧C conflict)
    case controlShift = "controlShift"     // ⌃⇧
    case commandShift = "commandShift"     // ⌘⇧
    case disabled = "disabled"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlOption: return "⌃⌥ (Control + Option — Khuyên dùng)"
        case .controlShift: return "⌃⇧ (Control + Shift)"
        case .commandShift: return "⌘⇧ (Command + Shift)"
        case .disabled: return "Tắt phím tắt toàn cục"
        }
    }

    var symbolPrefix: String {
        switch self {
        case .controlOption: return "⌃⌥"
        case .controlShift: return "⌃⇧"
        case .commandShift: return "⌘⇧"
        case .disabled: return ""
        }
    }

    var modifierKeycaps: [String] {
        switch self {
        case .controlOption: return ["⌃", "⌥"]
        case .controlShift: return ["⌃", "⇧"]
        case .commandShift: return ["⌘", "⇧"]
        case .disabled: return []
        }
    }

    var carbonModifiers: UInt32? {
        switch self {
        case .controlOption: return UInt32(controlKey | optionKey)
        case .controlShift: return UInt32(controlKey | shiftKey)
        case .commandShift: return UInt32(cmdKey | shiftKey)
        case .disabled: return nil
        }
    }

    var cocoaModifierMask: NSEvent.ModifierFlags {
        switch self {
        case .controlOption: return [.control, .option]
        case .controlShift: return [.control, .shift]
        case .commandShift: return [.command, .shift]
        case .disabled: return []
        }
    }
}

enum ScreenCorner: String, CaseIterable, Identifiable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: return "Trên Trái"
        case .topRight: return "Trên Phải"
        case .bottomLeft: return "Dưới Trái"
        case .bottomRight: return "Dưới Phải"
        }
    }

    var iconName: String {
        switch self {
        case .topLeft: return "inset.filled.topleft.rectangle"
        case .topRight: return "inset.filled.topright.rectangle"
        case .bottomLeft: return "inset.filled.bottomleft.rectangle"
        case .bottomRight: return "inset.filled.bottomright.rectangle"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "general"
    case cursorAndLoupe = "cursorAndLoupe"
    case presentation = "presentation"
    case shortcuts = "shortcuts"
    case updates = "updates"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Cài đặt chung"
        case .cursorAndLoupe: return "Con trỏ & Kính lúp"
        case .presentation: return "Trình chiếu"
        case .shortcuts: return "Phím tắt"
        case .updates: return "Cập nhật"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "display"
        case .cursorAndLoupe: return "scope"
        case .presentation: return "light.beacon.max.fill"
        case .shortcuts: return "command"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var badgeColor: Color {
        switch self {
        case .general: return Color(nsColor: .systemBlue)
        case .cursorAndLoupe: return Color(nsColor: .systemOrange)
        case .presentation: return Color(nsColor: .systemRed)
        case .shortcuts: return Color(nsColor: .systemIndigo)
        case .updates: return Color(nsColor: .systemGreen)
        }
    }
}

enum ToolbarTooltipItem: String, Equatable {
    case displayPicker
    case stopResume
    case modeLiveView
    case modeInteractive
    case teleportCursor
    case loupeZoom
    case audienceLaser
    case privacyBlackout
    case clickThrough
    case alwaysOnTop
    case updateAvailable
    case openSettings
    // Startup & Quick Options strip on header
    case launchAtLoginToggle
    case showWindowOnLaunchToggle
    case headerHideFromDock
    // Bottom floating HUD controls
    case aspectRatioLock
    case autoHideChrome
    case hideFromDock
    case quickHideWindow

    var iconName: String {
        switch self {
        case .displayPicker: return "display"
        case .stopResume: return "playpause.fill"
        case .modeLiveView: return "eye.fill"
        case .modeInteractive: return "cursorarrow.click.2"
        case .teleportCursor: return "location.viewfinder"
        case .loupeZoom: return "plus.magnifyingglass"
        case .audienceLaser: return "light.beacon.max.fill"
        case .privacyBlackout: return "eye.slash.fill"
        case .clickThrough: return "hand.point.up.braille.fill"
        case .alwaysOnTop: return "pin.fill"
        case .updateAvailable: return "arrow.down.circle.fill"
        case .openSettings: return "gearshape.fill"
        case .launchAtLoginToggle: return "power.circle.fill"
        case .showWindowOnLaunchToggle: return "macwindow.badge.plus"
        case .headerHideFromDock: return "dock.rectangle"
        case .aspectRatioLock: return "aspectratio"
        case .autoHideChrome: return "pip"
        case .hideFromDock: return "dock.rectangle"
        case .quickHideWindow: return "macwindow"
        }
    }

    var isLeftAligned: Bool {
        switch self {
        case .displayPicker, .stopResume, .teleportCursor, .loupeZoom, .launchAtLoginToggle, .showWindowOnLaunchToggle:
            return true
        default:
            return false
        }
    }

    var isBottomHUDItem: Bool {
        switch self {
        case .aspectRatioLock, .autoHideChrome, .hideFromDock, .quickHideWindow:
            return true
        default:
            return false
        }
    }
}
