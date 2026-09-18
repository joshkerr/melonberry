// Renders the MelonBerry app icon to a 1024×1024 PNG.  usage: swift make-icon.swift out.png
// A front view of a sheet-fed document scanner: paper in the rear chute, white body
// with a touchscreen and blue Scan button, and the scanned page coming out the front.
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
func gray(_ w: Double, _ a: Double = 1) -> CGColor { color(w, w, w, a) }

func rounded(_ rect: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func polygon(_ points: [(Double, Double)]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
}

/// Fills `path` with a vertical gradient, optionally casting a shadow.
func fill(_ path: CGPath, top: CGColor, bottom: CGColor, shadow: (blur: Double, dy: Double, color: CGColor)? = nil) {
    let box = path.boundingBox
    if let shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: shadow.dy), blur: shadow.blur, color: shadow.color)
        ctx.addPath(path)
        ctx.setFillColor(bottom)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: rgb, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()
}

// MARK: plate — macOS icon grid: 824pt squircle centered on a 1024pt canvas
let plate = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 186)
fill(plate, top: color(0.36, 0.78, 1.0), bottom: color(0.05, 0.36, 0.96), shadow: (28, -12, gray(0, 0.35)))
ctx.saveGState()
ctx.addPath(plate)
ctx.clip()
let sheen = CGGradient(colorsSpace: rgb, colors: [gray(1, 0.28), gray(1, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 620), options: [])
ctx.restoreGState()

// MARK: rear paper chute
let chute = polygon([(268, 500), (756, 500), (726, 742), (298, 742)])
fill(chute, top: gray(0.97), bottom: gray(0.80), shadow: (24, -8, color(0, 0.1, 0.4, 0.35)))
// chute extension
fill(rounded(CGRect(x: 392, y: 730, width: 240, height: 66), 18), top: gray(0.98), bottom: gray(0.88))

// MARK: paper waiting in the chute
let paper = CGRect(x: 336, y: 500, width: 352, height: 330)
fill(rounded(paper, 14), top: gray(1), bottom: gray(0.97), shadow: (16, -4, color(0, 0.1, 0.4, 0.35)))
ctx.setFillColor(color(0.76, 0.81, 0.88))
for (index, width) in [140.0, 256, 256, 200, 256].enumerated() {
    let line = CGRect(x: paper.minX + 48, y: paper.maxY - 66 - Double(index) * 46, width: width, height: index == 0 ? 20 : 14)
    ctx.addPath(rounded(line, line.height / 2))
    ctx.fillPath()
}

// MARK: scanned page coming out the front, in perspective
let output = polygon([(300, 330), (724, 330), (770, 196), (254, 196)])
fill(output, top: gray(0.90), bottom: gray(1), shadow: (22, -8, color(0, 0.1, 0.4, 0.4)))
ctx.setFillColor(color(0.76, 0.81, 0.88))
for (index, y) in [286.0, 252, 218].enumerated() {
    // lines widen toward the viewer with the page
    let spread = (330 - y) / 134 * 46
    let left = 300 - spread + 52, right = 724 + spread - 52
    let lineWidth = index == 2 ? (right - left) * 0.6 : right - left
    ctx.addPath(rounded(CGRect(x: left, y: y, width: lineWidth, height: 12), 6))
    ctx.fillPath()
}

// MARK: body
let body = rounded(CGRect(x: 204, y: 306, width: 616, height: 232), 56)
fill(body, top: gray(1), bottom: gray(0.86), shadow: (30, -12, color(0, 0.08, 0.35, 0.5)))
// feed slot along the top, glowing where the page is being read
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 26, color: color(0.35, 0.9, 1.0, 1))
ctx.addPath(rounded(CGRect(x: 300, y: 508, width: 424, height: 12), 6))
ctx.setFillColor(color(0.75, 0.97, 1.0))
ctx.fillPath()
ctx.restoreGState()
// exit slot
ctx.addPath(rounded(CGRect(x: 268, y: 322, width: 488, height: 14), 7))
ctx.setFillColor(gray(0.22))
ctx.fillPath()

// MARK: touchscreen with the blue Scan button
let screen = rounded(CGRect(x: 402, y: 366, width: 220, height: 124), 18)
fill(screen, top: color(0.16, 0.18, 0.22), bottom: color(0.07, 0.08, 0.10))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 22, color: color(0.25, 0.65, 1.0, 0.95))
ctx.addPath(CGPath(ellipseIn: CGRect(x: 512 - 36, y: 428 - 36, width: 72, height: 72), transform: nil))
ctx.setFillColor(color(0.18, 0.56, 1.0))
ctx.fillPath()
ctx.restoreGState()
fill(CGPath(ellipseIn: CGRect(x: 512 - 36, y: 428 - 36, width: 72, height: 72), transform: nil),
     top: color(0.40, 0.75, 1.0), bottom: color(0.10, 0.45, 0.98))

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
