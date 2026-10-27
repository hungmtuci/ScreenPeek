import AppKit
import CoreGraphics

func drawAppIcon(size: Int) -> NSImage {
    let cgSize = CGSize(width: size, height: size)
    let image = NSImage(size: cgSize)
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = CGFloat(size)
    let pad = s * 0.08
    let iconRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let cornerRadius = iconRect.width * 0.225

    // Background squircle with rich blue-indigo gradient
    let bgPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.07, green: 0.14, blue: 0.32, alpha: 1.0),
        CGColor(red: 0.12, green: 0.34, blue: 0.72, alpha: 1.0),
        CGColor(red: 0.05, green: 0.11, blue: 0.25, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
            options: []
        )
    }

    // Subtle inner border
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(bgPath)
    ctx.strokePath()

    // Large External Monitor Frame (top-left)
    let monRect = CGRect(x: s * 0.17, y: s * 0.36, width: s * 0.54, height: s * 0.39)
    let monPath = CGPath(roundedRect: monRect, cornerWidth: s * 0.035, cornerHeight: s * 0.035, transform: nil)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.08, blue: 0.18, alpha: 0.85))
    ctx.addPath(monPath)
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 0.85))
    ctx.setLineWidth(max(1.5, s * 0.022))
    ctx.addPath(monPath)
    ctx.strokePath()

    // Floating PiP Preview Window (bottom-right)
    let pipRect = CGRect(x: s * 0.35, y: s * 0.19, width: s * 0.48, height: s * 0.34)
    let pipPath = CGPath(roundedRect: pipRect, cornerWidth: s * 0.035, cornerHeight: s * 0.035, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.setFillColor(CGColor(red: 0.09, green: 0.17, blue: 0.34, alpha: 1.0))
    ctx.addPath(pipPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 1.0))
    ctx.setLineWidth(max(1.5, s * 0.024))
    ctx.addPath(pipPath)
    ctx.strokePath()

    // Glowing Yellow Cursor Highlight Ring inside PiP window
    let ringCenter = CGPoint(x: pipRect.midX, y: pipRect.midY)
    let ringRadius = s * 0.085
    let ringRect = CGRect(x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.035, color: CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.95))
    ctx.setFillColor(CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.25))
    ctx.fillEllipse(in: ringRect)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 0.86, blue: 0.05, alpha: 1.0))
    ctx.setLineWidth(max(1.5, s * 0.026))
    ctx.strokeEllipse(in: ringRect)
    ctx.restoreGState()

    // Center white dot
    let dotR = s * 0.022
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: ringCenter.x - dotR, y: ringCenter.y - dotR, width: dotR * 2, height: dotR * 2))

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift generate_icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let iconsetPath = args[1]
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    let img = drawAppIcon(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
}
