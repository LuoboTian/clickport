#!/usr/bin/env swift
import AppKit

// Original geometric artwork. Render each macOS size directly, without external assets.
let output = URL(fileURLWithPath: "Apps/Clickport/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes = [16, 32, 128, 256, 512]
var images: [[String: String]] = []
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 26,
                          color: NSColor.black.withAlphaComponent(0.2).cgColor)
        let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
        NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.88, alpha: 1).setFill()
        tile.fill()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.62, blue: 1, alpha: 1),
                   ending: NSColor(calibratedRed: 0.04, green: 0.34, blue: 0.83, alpha: 1))!.draw(in: tile, angle: -90)

        // Open corner suggests a destination; the pointer represents a contextual action.
        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: 538, y: 742))
        corner.line(to: NSPoint(x: 724, y: 742))
        corner.curve(to: NSPoint(x: 756, y: 710), controlPoint1: NSPoint(x: 742, y: 742), controlPoint2: NSPoint(x: 756, y: 728))
        corner.line(to: NSPoint(x: 756, y: 524))
        corner.lineWidth = 54
        corner.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.5).setStroke()
        corner.stroke()

        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: 294, y: 737))
        pointer.line(to: NSPoint(x: 674, y: 478))
        pointer.line(to: NSPoint(x: 515, y: 447))
        pointer.line(to: NSPoint(x: 621, y: 273))
        pointer.line(to: NSPoint(x: 523, y: 219))
        pointer.line(to: NSPoint(x: 424, y: 399))
        pointer.line(to: NSPoint(x: 324, y: 278))
        pointer.close()
        NSColor.white.setFill()
        pointer.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let catalog: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
let metadata: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated 10 macOS app icon renditions.")
