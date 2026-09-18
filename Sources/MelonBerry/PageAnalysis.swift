import CoreGraphics

/// Image-level cleanup applied to each page before it goes into the PDF.
enum PageAnalysis {
    /// Pages with less than this percentage of dark pixels are treated as blank. Measured on
    /// real scans: blank sides score ~0.00, a page holding only a short line of text ~0.05.
    static let blankThreshold = 0.03

    /// Percentage of dark pixels in the middle 90% of the page (the edges pick up feed shadows).
    static func inkPercentage(of image: CGImage) -> Double {
        let width = max(image.width / 4, 1), height = max(image.height / 4, 1)
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 100 }

        let marginX = width / 20, marginY = height / 20
        var dark = 0, total = 0
        for y in marginY..<(height - marginY) {
            for x in marginX..<(width - marginX) {
                total += 1
                if pixels[y * width + x] < 166 { dark += 1 }  // darker than 65% gray
            }
        }
        return total == 0 ? 100 : Double(dark) / Double(total) * 100
    }

    /// The driver's auto-crop trims every sheet a little differently, which makes a PDF look
    /// ragged. If a page is close to a standard paper size, return that exact size in pixels
    /// so it can be centered on a uniform canvas. Odd sizes (receipts, cards) return nil.
    static func standardCanvas(width: Int, height: Int, dpi: Int) -> (width: Int, height: Int)? {
        let inches: [(Double, Double)] = [(8.5, 11), (8.27, 11.69), (8.5, 14)]  // Letter, A4, Legal
        for (w, h) in inches {
            let sw = w * Double(dpi), sh = h * Double(dpi)
            let fitsInside = Double(width) <= sw * 1.03 && Double(height) <= sh * 1.03
            let fillsMost = Double(width) >= sw * 0.90 && Double(height) >= sh * 0.85
            if fitsInside && fillsMost { return (Int(sw.rounded()), Int(sh.rounded())) }
        }
        return nil
    }

    /// Centers `image` on a white canvas of the given size.
    static func centered(_ image: CGImage, on canvas: (width: Int, height: Int)) -> CGImage? {
        let gray = image.colorSpace?.model == .monochrome
        guard let context = CGContext(
            data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (gray ? CGImageAlphaInfo.none : CGImageAlphaInfo.noneSkipLast).rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        context.draw(image, in: CGRect(
            x: (canvas.width - image.width) / 2, y: (canvas.height - image.height) / 2,
            width: image.width, height: image.height))
        return context.makeImage()
    }
}
