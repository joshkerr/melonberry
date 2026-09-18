import AppKit
import SwiftUI

/// Floating panel that shows pages as they come off the scanner. It never takes focus,
/// so it can appear and disappear without interrupting whatever the user is doing.
@MainActor
final class ScanWindowManager {
    static let shared = ScanWindowManager()
    private var panel: NSPanel?

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.center()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        let host = NSHostingView(rootView: ScanWindowView())
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect
        return panel
    }
}

struct ScanWindowView: View {
    @ObservedObject private var controller = ScanController.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            pageStrip
            footer
        }
        .frame(width: 640, height: 400)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(symbolColor)
                .symbolEffect(.pulse, isActive: controller.stage == .scanning)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 14)
    }

    private var symbol: String {
        switch controller.stage {
        case .processing: return "text.viewfinder"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "doc.viewfinder"
        }
    }

    private var symbolColor: Color {
        switch controller.stage {
        case .done: return .green
        case .failed: return .orange
        default: return .accentColor
        }
    }

    private var title: String {
        switch controller.stage {
        case .processing: return "Creating PDF…"
        case .done: return "Scan Complete"
        case .failed: return "Scan Failed"
        default: return "Scanning…"
        }
    }

    private var subtitle: String {
        let count = controller.pages.count
        let blanks = controller.skippedBlanks
        let pageText = "\(count) page\(count == 1 ? "" : "s")" + (blanks > 0 ? " · \(blanks) blank skipped" : "")
        switch controller.stage {
        case .done(let url): return "\(pageText) · \(url.lastPathComponent)"
        case .failed(let reason): return reason
        case .processing: return "\(pageText) · recognizing text"
        default: return controller.pages.isEmpty ? "Feeding paper" : pageText
        }
    }

    // MARK: Pages

    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 18) {
                    // numbered by position in the PDF, not by scanner side, so skipped blanks leave no gaps
                    ForEach(Array(controller.pages.enumerated()), id: \.element.id) { index, page in
                        PageThumbnail(page: page, number: index + 1)
                            .id(page.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(minWidth: 640, alignment: controller.pages.count < 4 ? .center : .leading)
            }
            .onChange(of: controller.pages.count) {
                guard let last = controller.pages.last else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(last.id, anchor: .trailing) }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay {
            if controller.pages.isEmpty && controller.stage == .scanning {
                ProgressView().controlSize(.large)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            switch controller.stage {
            case .processing:
                ProgressView().progressViewStyle(.linear)
            case .done(let url):
                Label(url.deletingLastPathComponent().lastPathComponent, systemImage: "folder")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            default:
                Spacer()
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}

private struct PageThumbnail: View {
    let page: ScannedPage
    let number: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: page.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
