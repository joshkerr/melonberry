import AppKit
import ImageIO
import os
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ScannedPage: Identifiable {
    let id: Int  // 1-based page number from scanimage
    let thumbnail: NSImage
}

/// Watches the scanner's hopper sensor and runs the scan → JPEG → PDF → OCR pipeline.
@MainActor
final class ScanController: ObservableObject {
    static let shared = ScanController()

    enum ScannerStatus: Equatable {
        case starting
        case missingTools([String])
        case offline
        case ready
        case paperDetected
        case busy
    }

    enum Stage: Equatable {
        case scanning
        case processing
        case done(URL)
        case failed(String)
    }

    @Published private(set) var scanner: ScannerStatus = .starting {
        didSet { if scanner != oldValue { log.info("scanner: \(String(describing: self.scanner), privacy: .public)") } }
    }
    @Published private(set) var stage: Stage? {
        didSet { if stage != oldValue { log.info("stage: \(String(describing: self.stage), privacy: .public)") } }
    }
    /// Pages that will go into the PDF; blank sides are counted in `skippedBlanks` instead.
    @Published private(set) var pages: [ScannedPage] = []
    @Published private(set) var skippedBlanks = 0
    @Published private(set) var lastOutput: URL?

    nonisolated private static let device = "fujitsu"
    nonisolated private static let dpi = 300
    nonisolated private static let jpegQuality = 0.85
    nonisolated private static let settleSeconds = 3.0

    private let log = Logger(subsystem: "com.joshkerr.MelonBerry", category: "scan")
    private var loopTask: Task<Void, Never>?
    private var scanRequested = false
    /// Cleared after a scan until the hopper is seen empty, so a jam can't retrigger in a loop.
    private var armed = true
    private var jobID = 0
    private var conversions: [Int: Task<URL?, Never>] = [:]

    private enum Paper { case loaded, empty, offline }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { await monitorLoop() }
    }

    /// Puts the controller in a fixed state without touching the scanner (used by `--screenshots`).
    func loadDemo(pages: [ScannedPage], skippedBlanks: Int, stage: Stage) {
        self.pages = pages
        self.skippedBlanks = skippedBlanks
        self.stage = stage
    }

    func requestScan() {
        scanRequested = true
    }

    var canScan: Bool { scanner == .ready || scanner == .paperDetected }

    var statusText: String {
        switch scanner {
        case .starting: return "Starting…"
        case .missingTools(let tools): return "Missing: \(tools.joined(separator: ", ")) — install with Homebrew"
        case .offline: return scanSnapHomeRunning ? "Scanner busy — quit ScanSnap Home" : "Scanner not connected"
        case .ready: return Prefs.autoScan ? "Ready — load paper to scan" : "Ready"
        case .paperDetected: return "Paper loaded"
        case .busy: return stage == .processing ? "Creating PDF…" : "Scanning…"
        }
    }

    var menuBarIcon: NSImage {
        switch scanner {
        case .busy: return MenuBarIcon.scanning
        case .missingTools:
            return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Missing tools") ?? MenuBarIcon.idle
        default: return MenuBarIcon.idle
        }
    }

    /// ScanSnap Home's helpers hold the USB device, which makes the scanner look offline to SANE.
    private var scanSnapHomeRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path.contains("ScanSnapHome") == true }
    }

    // MARK: - Monitoring

    private func monitorLoop() async {
        while !Task.isCancelled {
            let missing = Tools.missing
            guard missing.isEmpty, let scanimage = Tools.find("scanimage") else {
                scanner = .missingTools(missing)
                await sleep(10)
                continue
            }

            let paper = await paperState(scanimage)
            if scanRequested {
                scanRequested = false
                if paper != .offline {
                    await performScan(scanimage)
                    continue
                }
            }

            switch paper {
            case .offline:
                scanner = .offline
                await sleep(4)
            case .empty:
                scanner = .ready
                armed = true
                await sleep(1)
            case .loaded:
                scanner = .paperDetected
                if Prefs.autoScan && armed {
                    // give the user a moment to square the stack
                    await sleep(Self.settleSeconds)
                    if await paperState(scanimage) == .loaded, Prefs.autoScan {
                        await performScan(scanimage)
                    }
                } else {
                    await sleep(1)
                }
            }
        }
    }

    private func paperState(_ scanimage: URL) async -> Paper {
        let result = await runProcess(scanimage, ["-d", Self.device, "-A"])
        guard result.status == 0,
              let line = result.stdout.split(separator: "\n").first(where: { $0.contains("--page-loaded") })
        else { return .offline }
        return line.contains("[yes]") ? .loaded : .empty
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Scanning

    private func performScan(_ scanimage: URL) async {
        guard let img2pdf = Tools.find("img2pdf"), let ocrmypdf = Tools.find("ocrmypdf") else { return }

        jobID += 1
        armed = false
        scanner = .busy
        pages = []
        skippedBlanks = 0
        conversions = [:]
        stage = .scanning
        let windowShown = Prefs.showWindow
        if windowShown { ScanWindowManager.shared.show() }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("MelonBerry-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // scanimage exits non-zero when the feeder runs empty, which is how every batch
        // ends — success is judged by whether any pages came out.
        let scan = await runProcess(scanimage, [
            "-d", Self.device,
            "--source", Prefs.duplex ? "ADF Duplex" : "ADF Front",
            "--mode", Prefs.colorMode,
            "--resolution", String(Self.dpi),
            // no --swdeskew: the driver's deskew spins blank and sparse pages to wild angles
            "--swcrop=yes",
            "--format=png", "--batch=\(work.path)/p%04d.png",
        ], onStderrLine: { [weak self] line in
            guard let number = Self.scannedPageNumber(in: line) else { return }
            Task { @MainActor in self?.pageScanned(number, in: work) }
        })

        // catch any page whose progress line hasn't been delivered yet
        let pngs = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)) ?? []
        for png in pngs where png.pathExtension == "png" {
            if let number = Int(png.deletingPathExtension().lastPathComponent.dropFirst()) {
                pageScanned(number, in: work)
            }
        }

        var jpegs: [URL] = []
        for number in conversions.keys.sorted() {
            if let jpeg = await conversions[number]?.value { jpegs.append(jpeg) }
        }
        guard !jpegs.isEmpty else {
            let reason = conversions.isEmpty ? Self.failureReason(from: scan.stderr)
                : skippedBlanks > 0 && pages.isEmpty ? "Every page was blank." : "Couldn't process the scanned pages."
            log.error("scan failed: \(scan.stderr, privacy: .public)")
            finish(.failed(reason), windowShown: windowShown)
            return
        }

        stage = .processing
        let raw = work.appendingPathComponent("raw.pdf")
        let assembled = await runProcess(img2pdf, ["--imgsize", "\(Self.dpi)dpi"] + jpegs.map(\.path) + ["-o", raw.path])
        guard assembled.status == 0 else {
            finish(.failed("Couldn't assemble the PDF."), windowShown: windowShown)
            return
        }

        // If OCR fails, keep the image-only PDF rather than losing the scan.
        let ocr = work.appendingPathComponent("ocr.pdf")
        let recognized = await runProcess(ocrmypdf, [
            "--quiet", "--deskew", "--rotate-pages", "--rotate-pages-threshold", "3",
            "--output-type", "pdf", "--optimize", "1", raw.path, ocr.path,
        ])
        let finished = recognized.status == 0 ? ocr : raw

        do {
            let destination = try Self.uniqueDestination()
            try FileManager.default.moveItem(at: finished, to: destination)
            lastOutput = destination
            finish(.done(destination), windowShown: windowShown)
        } catch {
            finish(.failed("Couldn't save to \(Prefs.destination.path)."), windowShown: windowShown)
        }
    }

    private func pageScanned(_ number: Int, in work: URL) {
        guard conversions[number] == nil else { return }
        let png = work.appendingPathComponent(String(format: "p%04d.png", number))
        let jpeg = png.deletingPathExtension().appendingPathExtension("jpg")
        let skipBlank = Prefs.skipBlank
        conversions[number] = Task.detached(priority: .userInitiated) { [weak self] in
            // scanimage announces a page just before renaming its .part file into place
            for _ in 0..<60 where !FileManager.default.fileExists(atPath: png.path) {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            let isBlank = skipBlank && PageAnalysis.inkPercentage(of: image) < PageAnalysis.blankThreshold
            if isBlank {
                await self?.blankSkipped()
                return nil
            }
            if let thumbnail = Self.thumbnail(from: source) {
                await self?.addPage(number, thumbnail: thumbnail)
            }
            return Self.writeJPEG(image, to: jpeg) ? jpeg : nil
        }
    }

    private func blankSkipped() {
        skippedBlanks += 1
    }

    private func addPage(_ number: Int, thumbnail: CGImage) {
        let page = ScannedPage(id: number, thumbnail: NSImage(cgImage: thumbnail, size: .zero))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            pages.append(page)
            pages.sort { $0.id < $1.id }
        }
    }

    private func finish(_ result: Stage, windowShown: Bool) {
        withAnimation { stage = result }
        scanner = .ready

        if windowShown {
            if Prefs.autoClose {
                let job = jobID
                // failures stay up at least 10s so the reason can be read
                let delay = result.isFailure ? max(Prefs.closeDelay, 10) : Prefs.closeDelay
                Task {
                    await sleep(delay)
                    if job == jobID { ScanWindowManager.shared.close() }
                }
            }
        } else {
            notify(result)
        }
    }

    private func notify(_ result: Stage) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        switch result {
        case .done(let url):
            content.title = "Scan Complete"
            content.body = "\(pages.count) page\(pages.count == 1 ? "" : "s") → \(url.lastPathComponent)"
        case .failed(let reason):
            content.title = "Scan Failed"
            content.body = reason
        default:
            return
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Helpers

    /// Matches scanimage's "Scanned page 3. (scanner status = 5)".
    nonisolated private static func scannedPageNumber(in line: String) -> Int? {
        guard line.hasPrefix("Scanned page ") else { return nil }
        return Int(line.dropFirst("Scanned page ".count).prefix { $0.isNumber })
    }

    nonisolated private static func failureReason(from stderr: String) -> String {
        let lower = stderr.lowercased()
        if lower.contains("jam") { return "Paper jam — clear the feeder and try again." }
        if lower.contains("cover") { return "The scanner cover is open." }
        if lower.contains("out of documents") { return "No paper in the feeder." }
        return "No pages came through the scanner."
    }

    nonisolated private static func thumbnail(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 520,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func writeJPEG(_ scanned: CGImage, to url: URL) -> Bool {
        // snap near-standard pages to an exact paper size so the PDF's pages are uniform
        let image = PageAnalysis.standardCanvas(width: scanned.width, height: scanned.height, dpi: dpi)
            .flatMap { PageAnalysis.centered(scanned, on: $0) } ?? scanned
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func uniqueDestination() throws -> URL {
        let folder = Prefs.destination
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Scan \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).pdf")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(suffix).pdf")
            suffix += 1
        }
        return url
    }
}

extension ScanController.Stage {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
