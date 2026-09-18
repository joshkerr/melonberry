import AppKit
import SwiftUI

/// `MelonBerry --screenshots <dir>` renders the README screenshots from the app's real views,
/// using generated sample pages — no scanner, no screen-recording permission, no real documents.
@MainActor
enum Screenshots {
    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)  // menu-bar-only apps can't become active, and inactive windows draw gray
        let controller = ScanController.shared
        let pages = (0..<3).map { ScannedPage(id: $0 + 1, thumbnail: samplePage(style: $0)) }
        let scanSize = NSSize(width: 640, height: 400)

        controller.loadDemo(pages: Array(pages.prefix(2)), skippedBlanks: 1, stage: .scanning)
        save(capture(ScanWindowView(), size: scanSize, dark: true, chromeless: true), to: directory, name: "scanning")

        let saved = Prefs.defaultDestination + "/Scan 2026-09-18 10.30.00.pdf"
        controller.loadDemo(pages: Array(pages.prefix(3)), skippedBlanks: 3, stage: .done(URL(fileURLWithPath: saved)))
        save(capture(ScanWindowView(), size: scanSize, dark: false, chromeless: true), to: directory, name: "complete")

        save(capture(SettingsView(), size: NSSize(width: 480, height: 520), dark: false, chromeless: false),
             to: directory, name: "settings")
    }

    // MARK: - Window capture

    private static func capture(_ view: some View, size: NSSize, dark: Bool, chromeless: Bool) -> NSImage {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let style: NSWindow.StyleMask = chromeless ? [.titled, .closable, .fullSizeContentView] : [.titled, .closable]
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.appearance = appearance
        window.title = "MelonBerry Settings"
        if chromeless {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        window.contentView = NSHostingView(rootView: view)
        window.setFrameOrigin(NSPoint(x: 120, y: 120))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)  // key windows draw with active (colored) controls
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))  // let SwiftUI lay out and draw

        let frameView = window.contentView!.superview!
        let bounds = frameView.bounds
        let scale = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)

        var background = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance { background = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB)! }
        return framed(rep, size: bounds.size, background: background)
    }

    /// Rounds the window's corners and adds a drop shadow, like a real window screenshot.
    private static func framed(_ rep: NSBitmapImageRep, size: NSSize, background: NSColor) -> NSImage {
        let margin = 56.0
        let canvas = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
        return NSImage(size: canvas, flipped: false) { _ in
            let rect = NSRect(x: margin, y: margin + 8, width: size.width, height: size.height)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 32
            shadow.shadowOffset = NSSize(width: 0, height: -14)
            shadow.set()
            background.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            rep.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
            return true
        }
    }

    private static func save(_ image: NSImage, to directory: URL, name: String) {
        let pixels = NSSize(width: image.size.width * 2, height: image.size.height * 2)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let url = directory.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    // MARK: - Sample pages

    /// A made-up document page: letter, form, report, invoice or memo depending on `style`.
    private static func samplePage(style: Int) -> NSImage {
        let size = NSSize(width: 425, height: 550)
        return NSImage(size: size, flipped: true) { _ in
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            let ink = NSColor(white: 0.25, alpha: 1), soft = NSColor(white: 0.72, alpha: 1)
            let accent = [NSColor.systemBlue, .systemTeal, .systemIndigo, .systemOrange, .systemGreen][style % 5]

            func bar(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: NSColor) {
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
            }
            func paragraph(from y: Double, lines: Int, x: Double = 48, width: Double = 329) -> Double {
                for line in 0..<lines {
                    let last = line == lines - 1
                    bar(x, y + Double(line) * 13, last ? width * 0.55 : width - Double((line * 37) % 40), 5, soft)
                }
                return y + Double(lines) * 13 + 14
            }

            switch style % 5 {
            case 0:  // letter
                accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: 192, y: 40, width: 40, height: 40)).fill()
                bar(132, 92, 160, 7, ink)
                var y = paragraph(from: 140, lines: 3, width: 130)
                for count in [5, 6, 4] { y = paragraph(from: y, lines: count) }
                bar(48, y + 24, 110, 6, ink)
            case 1:  // form
                ink.setFill()
                NSRect(x: 36, y: 36, width: 353, height: 34).fill()
                bar(120, 49, 180, 8, .white)
                soft.setStroke()
                for row in 0..<11 {
                    let y = 92 + Double(row) * 38
                    NSBezierPath(rect: NSRect(x: 36, y: y, width: 353, height: 38)).stroke()
                    NSBezierPath(rect: NSRect(x: 36, y: y, width: 34, height: 38)).stroke()
                    bar(82, y + 16, 90 + Double((row * 53) % 80), 5, soft)
                    if row % 3 != 1 { bar(250, y + 16, 70, 5, ink) }
                }
            case 2:  // report with chart
                bar(48, 48, 210, 10, ink)
                var y = paragraph(from: 84, lines: 5)
                NSColor(white: 0.95, alpha: 1).setFill()
                NSRect(x: 48, y: y, width: 329, height: 130).fill()
                for (index, height) in [50.0, 78, 62, 104, 88, 116].enumerated() {
                    accent.withAlphaComponent(0.85).setFill()
                    NSRect(x: 74 + Double(index) * 50, y: y + 120 - height, width: 28, height: height).fill()
                }
                y += 152
                for count in [6, 5] { y = paragraph(from: y, lines: count) }
            case 3:  // invoice
                bar(48, 48, 120, 12, accent)
                bar(277, 50, 100, 8, ink)
                _ = paragraph(from: 92, lines: 3, width: 140)
                for row in 0..<8 {
                    let y = 190 + Double(row) * 30
                    if row == 0 { NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 48, y: y - 10, width: 329, height: 26).fill() }
                    bar(58, y, 120 + Double((row * 41) % 70), 5, row == 0 ? ink : soft)
                    bar(327, y, 40, 5, row == 0 ? ink : soft)
                }
                bar(287, 446, 80, 8, ink)
            default:  // memo
                bar(48, 48, 90, 10, ink)
                accent.setFill()
                NSRect(x: 48, y: 72, width: 329, height: 2).fill()
                var y = 96.0
                for count in [4, 7, 5, 6] { y = paragraph(from: y, lines: count) }
            }
            return true
        }
    }
}
