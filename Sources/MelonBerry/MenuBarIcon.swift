import AppKit

/// The app icon's scanner, reduced to a monochrome template glyph for the menu bar:
/// paper in the chute, body with the round Scan button, scanned page coming out the front.
enum MenuBarIcon {
    static let idle = make(scanning: false)
    static let scanning = make(scanning: true)

    private static func make(scanning: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // paper in the chute — solid while a scan is running
            let paper = NSBezierPath(roundedRect: NSRect(x: 5.6, y: 9.4, width: 8.8, height: 8), xRadius: 1.2, yRadius: 1.2)
            paper.lineWidth = 1.2
            if scanning {
                paper.fill()
            } else {
                paper.stroke()
                for y in [14.2, 12.0] {
                    NSBezierPath(roundedRect: NSRect(x: 7.6, y: y, width: 4.8, height: 1), xRadius: 0.5, yRadius: 0.5).fill()
                }
            }

            // scanned page coming out the front
            let output = NSBezierPath()
            output.move(to: NSPoint(x: 5.2, y: 4.4))
            output.line(to: NSPoint(x: 3.8, y: 0.9))
            output.line(to: NSPoint(x: 16.2, y: 0.9))
            output.line(to: NSPoint(x: 14.8, y: 4.4))
            output.lineWidth = 1.2
            output.lineJoinStyle = .round
            output.stroke()

            // body, with the Scan button punched out
            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 18, height: 6.4), xRadius: 2.2, yRadius: 2.2)
            body.appendOval(in: NSRect(x: 8.5, y: 5.7, width: 3, height: 3))
            body.windingRule = .evenOdd
            body.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
