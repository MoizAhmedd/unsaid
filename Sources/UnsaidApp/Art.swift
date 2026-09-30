import AppKit

/// The app icon and menu-bar icon, drawn in code so there are no image files to keep in sync.
enum Art {
    /// An orange tile with a speech bubble whose middle word is struck out.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 1024
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 100 * s, dy: 100 * s), xRadius: 185 * s, yRadius: 185 * s)
            NSColor(red: 0.91, green: 0.35, blue: 0.05, alpha: 1).setFill()
            tile.fill()

            let bubble = NSBezierPath(roundedRect: NSRect(x: 230 * s, y: 330 * s, width: 564 * s, height: 400 * s), xRadius: 110 * s, yRadius: 110 * s)
            bubble.move(to: NSPoint(x: 330 * s, y: 350 * s))
            bubble.line(to: NSPoint(x: 300 * s, y: 250 * s))
            bubble.line(to: NSPoint(x: 430 * s, y: 340 * s))
            NSColor.white.setFill()
            bubble.fill()

            // Three words; the middle one struck through.
            let ink = NSColor(red: 0.91, green: 0.35, blue: 0.05, alpha: 1)
            for (x, w) in [(310.0, 110.0), (450.0, 130.0), (610.0, 100.0)] {
                let word = NSBezierPath(roundedRect: NSRect(x: x * s, y: 505 * s, width: w * s, height: 50 * s), xRadius: 25 * s, yRadius: 25 * s)
                (x == 450 ? ink.withAlphaComponent(0.3) : ink).setFill()
                word.fill()
            }
            let strike = NSBezierPath()
            strike.move(to: NSPoint(x: 430 * s, y: 530 * s))
            strike.line(to: NSPoint(x: 600 * s, y: 530 * s))
            strike.lineWidth = 22 * s
            strike.lineCapStyle = .round
            ink.setStroke()
            strike.stroke()
            return true
        }
    }

    static var menuBarIcon: NSImage {
        let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Unsaid")!
        image.isTemplate = true
        return image
    }

    /// Writes an .iconset for `iconutil` (scripts/make-app.sh).
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png(appIcon(size: CGFloat(px)), pixels: px).write(to: dir.appendingPathComponent(name))
            }
        }
    }

    static func png(_ image: NSImage, pixels: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
