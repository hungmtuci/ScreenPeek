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
        case .yellow: return Color(red: 1.0, green: 0.85, blue: 0.0)
        case .red: return Color(red: 1.0, green: 0.22, blue: 0.22)
        case .cyan: return Color(red: 0.0, green: 0.9, blue: 1.0)
        case .green: return Color(red: 0.15, green: 0.95, blue: 0.4)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        case .red: return NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.22, alpha: 1.0)
        case .cyan: return NSColor(calibratedRed: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        case .green: return NSColor(calibratedRed: 0.15, green: 0.95, blue: 0.4, alpha: 1.0)
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
    case controlOption = "controlOption"   // ⌃⌥ (Recommended — avoids Chrome/Safari ⌘⇧C conflict!)
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

enum ToolbarTooltipItem: String, Equatable {
    case displayPicker
    case stopResume
    case modeLiveView
    case modeInteractive
    case teleportCursor
    case loupeZoom
    case audienceLaser
    case privacyBlackout
    case autoHideChrome
    case clickThrough
    case cursorSettings
    case aspectRatioLock
    case alwaysOnTop
    case hideFromDock

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
        case .autoHideChrome: return "rectangle.expand.vertical"
        case .clickThrough: return "hand.point.up.braille.fill"
        case .cursorSettings: return "scope"
        case .aspectRatioLock: return "aspectratio.fill"
        case .alwaysOnTop: return "pin.fill"
        case .hideFromDock: return "dock.rectangle"
        }
    }

    var isLeftAligned: Bool {
        switch self {
        case .displayPicker, .stopResume:
            return true
        default:
            return false
        }
    }
}
