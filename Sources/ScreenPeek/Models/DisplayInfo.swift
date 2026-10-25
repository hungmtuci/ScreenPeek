import Foundation
import AppKit
import CoreGraphics
import SwiftUI

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
}

enum ToolbarTooltipItem: String, Equatable {
    case displayPicker
    case stopResume
    case modeLiveView
    case modeInteractive
    case teleportCursor
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

