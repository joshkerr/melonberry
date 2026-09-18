import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // menu bar apps aren't active by default, so the window would open behind everything
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MelonBerry Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        return window
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.destination) private var destination = Prefs.defaultDestination
    @AppStorage(Prefs.Key.autoScan) private var autoScan = true
    @AppStorage(Prefs.Key.showWindow) private var showWindow = true
    @AppStorage(Prefs.Key.autoClose) private var autoClose = true
    @AppStorage(Prefs.Key.closeDelay) private var closeDelay = 6.0
    @AppStorage(Prefs.Key.duplex) private var duplex = true
    @AppStorage(Prefs.Key.colorMode) private var colorMode = "Color"
    @AppStorage(Prefs.Key.skipBlank) private var skipBlank = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Save Scans To") {
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: destination))
                        .resizable().frame(width: 20, height: 20)
                    Text((destination as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseDestination)
                }
            }

            Section("Scanning") {
                Toggle("Scan automatically when paper is loaded", isOn: $autoScan)
                Picker("Sides", selection: $duplex) {
                    Text("Both sides").tag(true)
                    Text("Front only").tag(false)
                }
                Picker("Color", selection: $colorMode) {
                    Text("Color").tag("Color")
                    Text("Grayscale").tag("Gray")
                }
                Toggle("Skip blank pages", isOn: $skipBlank)
            }

            Section("Scan Window") {
                Toggle("Show pages in a window while scanning", isOn: $showWindow)
                Toggle("Close the window automatically when finished", isOn: $autoClose)
                    .disabled(!showWindow)
                Picker("Close after", selection: $closeDelay) {
                    Text("3 seconds").tag(3.0)
                    Text("6 seconds").tag(6.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .disabled(!showWindow || !autoClose)
            }

            Section {
                Toggle("Open MelonBerry at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: destination)
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
