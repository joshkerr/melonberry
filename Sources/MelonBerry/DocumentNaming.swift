import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Names a PDF after what is on its first page: the document's date, its most prominent line of
/// text (usually the letterhead or a heading) and, if a word like "Invoice" or "Statement" appears
/// anywhere on the page, the kind of document. Everything runs on-device with the Vision framework.
///
///     2026-02-19 Pacific Gas and Electric Statement.pdf
///     2026-03-02 Acme Plumbing Invoice.pdf
///     2026-10-28 Dr Alvarez Referral.pdf          ← no date on the page, so the scan date is used
enum DocumentNaming {
    /// One line of recognized text with its position on the page. `top` and `height` are
    /// fractions of the page height; `top` is 0 at the top edge.
    struct Line {
        let text: String
        let top: Double
        let height: Double
    }

    /// Vision compiles its text model the first time a binary uses it, which can take the better
    /// part of a minute. Doing that at launch keeps it out of the first scan.
    nonisolated static func warmUp() {
        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let blank = context.makeImage() else { return }
        _ = recognizeLines(in: blank)
    }

    /// The base name (without extension) for a PDF whose first page is `url`, or nil when the
    /// page has nothing usable on it, in which case the caller falls back to a timestamp.
    nonisolated static func suggestedName(forFirstPage url: URL, scanned: Date = Date()) -> String? {
        guard let image = loadForRecognition(url) else { return nil }
        return name(from: recognizeLines(in: image), scanned: scanned)
    }

    /// Composes the name from recognized lines. Separate from the Vision step so it can be
    /// exercised without an image.
    nonisolated static func name(from lines: [Line], scanned: Date) -> String? {
        let kind = documentKind(in: lines)
        let title = title(in: lines, excluding: kind)
        guard title != nil || kind != nil else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var parts = [formatter.string(from: documentDate(in: lines, scanned: scanned) ?? scanned)]
        if let title { parts.append(title) }
        if let kind, !(title?.range(of: kind, options: .caseInsensitive) != nil) { parts.append(kind) }
        return parts.joined(separator: " ")
    }

    // MARK: - Recognition

    /// Vision doesn't need 300 dpi; a smaller image is read several times faster.
    nonisolated private static func loadForRecognition(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2200,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated static func recognizeLines(in image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }

        var read: [(text: String, box: CGRect, inverted: Bool)] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            // Vision reads upside-down text as happily as upright text; the corners of the
            // text's quad say which way up it was.
            let quad = try? candidate.boundingBox(for: candidate.string.startIndex..<candidate.string.endIndex)
            let inverted = quad.map { $0.topLeft.y < $0.bottomLeft.y } ?? false
            read.append((text, observation.boundingBox, inverted))
        }
        // A page fed in backwards has its top at the bottom of the image.
        let characters = read.reduce(0) { $0 + $1.text.count }
        let upsideDown = read.filter(\.inverted).reduce(0) { $0 + $1.text.count } > characters / 2
        return read
            .map { Line(text: $0.text, top: upsideDown ? $0.box.minY : 1 - $0.box.maxY, height: $0.box.height) }
            .sorted { $0.top < $1.top }  // reading order; boxes are normalized with the origin at the bottom-left
    }

    // MARK: - Date

    /// The first plausible date on the page, preferring one labelled as the document's date.
    /// Dates well in the future are skipped: those are due dates and expiry dates.
    nonisolated static func documentDate(in lines: [Line], scanned: Date) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let latest = Calendar.current.date(byAdding: .day, value: 45, to: scanned) ?? scanned
        let earliest = Calendar.current.date(from: DateComponents(year: 1970)) ?? .distantPast
        var labelled: Date?
        var first: Date?
        for line in lines {
            let text = line.text
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let date = match.date, let range = Range(match.range, in: text),
                      looksLikeCalendarDate(text[range]), date <= latest, date >= earliest
                else { continue }
                let label = text[..<range.lowerBound].lowercased()
                if label.contains("due") || label.contains("expir") || label.contains("valid") { continue }
                if labelled == nil, label.contains("date") || label.contains("issued") { labelled = date }
                if first == nil { first = date }
            }
        }
        return labelled ?? first
    }

    /// NSDataDetector also matches "tomorrow" and "10/30", so insist on a written-out year.
    nonisolated private static func looksLikeCalendarDate(_ text: Substring) -> Bool {
        text.range(of: #"\b(19|20)\d{2}\b|\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2}\b"#, options: .regularExpression) != nil
    }

    // MARK: - Title

    /// The largest line of text in the top half of the page that isn't a date, a number or
    /// just the document kind on its own.
    nonisolated static func title(in lines: [Line], excluding kind: String?) -> String? {
        let candidates = lines.filter { line in
            guard line.top < 0.5, line.text.count <= 80 else { return false }
            let letters = line.text.filter(\.isLetter).count
            guard letters >= 3, Double(letters) >= Double(line.text.count) * 0.5 else { return false }
            if looksLikeCalendarDate(line.text[...]) { return false }
            if let kind, line.text.compare(kind, options: .caseInsensitive) == .orderedSame { return false }
            return true
        }
        guard let largest = candidates.max(by: { $0.height < $1.height }) else { return nil }
        return clean(largest.text)
    }

    nonisolated private static func clean(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: #"[/:\\|*?"<>\p{Cc}]"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-_"))
        if text.count > 60 {
            text = String(text.prefix(60))
            if let space = text.lastIndex(of: " ") { text = String(text[..<space]) }
        }
        return isShouting(text) ? capitalized(text) : text
    }

    nonisolated private static func isShouting(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 6 && letters == letters.uppercased()
    }

    /// "PACIFIC GAS AND ELECTRIC" → "Pacific Gas and Electric". A lone short word ("IBM", "DMV")
    /// and anything with an ampersand ("PG&E", "AT&T") is left as the acronym it probably is.
    nonisolated private static func capitalized(_ text: String) -> String {
        let small: Set<String> = ["a", "an", "and", "at", "by", "de", "for", "in", "of", "on", "or", "the", "to"]
        let acronyms: Set<String> = ["llc", "llp", "plc", "usa", "us", "uk", "dmv", "irs", "ssa", "va", "hoa", "ups", "usps", "md", "dds", "cpa"]
        let words = text.split(separator: " ")
        if words.count == 1, text.filter(\.isLetter).count <= 4 { return text }
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, small.contains(lower) { return lower }
            if word.contains("&") || acronyms.contains(lower.filter(\.isLetter)) { return String(word) }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    // MARK: - Document kind

    /// Words that say what a document is. Longer phrases come first so "Purchase Order" wins
    /// over "Order"; "Bill" excludes the "Bill To" block on invoices.
    nonisolated private static let kinds: [(pattern: String, name: String)] = [
        ("explanation of benefits", "Explanation of Benefits"), ("purchase order", "Purchase Order"),
        ("work order", "Work Order"), ("credit note", "Credit Note"), ("packing slip", "Packing Slip"),
        ("pay ?stub", "Pay Stub"), ("tax return", "Tax Return"), ("w-2", "W-2"), ("1099", "1099"), ("1098", "1098"),
        ("invoice", "Invoice"), ("receipt", "Receipt"), ("statement", "Statement"), (#"bill(?!\s+to\b)"#, "Bill"),
        ("estimate", "Estimate"), ("quotation", "Quote"), ("quote", "Quote"), ("contract", "Contract"),
        ("agreement", "Agreement"), ("lease", "Lease"), ("notice", "Notice"), ("report", "Report"),
        ("policy", "Policy"), ("claim", "Claim"), ("certificate", "Certificate"), ("warranty", "Warranty"),
        ("prescription", "Prescription"), ("referral", "Referral"), ("application", "Application"),
        ("renewal", "Renewal"), ("remittance", "Remittance"), ("confirmation", "Confirmation"),
        ("reminder", "Reminder"), ("itinerary", "Itinerary"), ("transcript", "Transcript"), ("memo", "Memo"),
        ("minutes", "Minutes"), ("manual", "Manual"), ("summary", "Summary"),
    ]

    /// The kind named in the largest text that names one, since "INVOICE" as a heading beats
    /// "statement" in the small print.
    nonisolated static func documentKind(in lines: [Line]) -> String? {
        var best: (name: String, height: Double)?
        for line in lines {
            for kind in kinds where line.text.range(of: #"\b"# + kind.pattern + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                if best == nil || line.height > best!.height { best = (kind.name, line.height) }
                break
            }
        }
        return best?.name
    }
}
